import Foundation

protocol AIModelClient: Sendable {
    func streamChat(_ request: ChatRequest) async throws -> AsyncThrowingStream<ModelEvent, Error>
    func generateCard(for pet: PetDefinition, languageProfile: LanguageProfile, type: CardType, energy: EnergyState) async throws -> GeneratedCard
    func proposeMemories(for pet: PetDefinition, transcript: String) async throws -> [MemoryProposal]
    func testConnection() async throws -> ModelConnectionStatus
}

protocol ModelClientFactory: Sendable {
    func makeClient(configuration: ModelConfiguration) -> any AIModelClient
}

struct DefaultModelClientFactory: ModelClientFactory {
    let keyStore: any APIKeyProviding
    let session: URLSession

    init(keyStore: any APIKeyProviding = KeychainAPIKeyStore(), session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    func makeClient(configuration: ModelConfiguration) -> any AIModelClient {
        OpenAIResponsesClient(keyStore: keyStore, session: session, configuration: configuration)
    }
}

actor OpenAIResponsesClient: AIModelClient {
    private let keyStore: any APIKeyProviding
    private let session: URLSession
    private var configuration: ModelConfiguration

    init(
        keyStore: any APIKeyProviding = KeychainAPIKeyStore(),
        session: URLSession = .shared,
        model: String = "gpt-5.6-terra"
    ) {
        self.keyStore = keyStore
        self.session = session
        configuration = .init(provider: .openAI, modelID: model, reasoningEffort: .none)
    }

    init(
        keyStore: any APIKeyProviding = KeychainAPIKeyStore(),
        session: URLSession = .shared,
        configuration: ModelConfiguration
    ) {
        self.keyStore = keyStore
        self.session = session
        self.configuration = configuration
    }

    func setModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { configuration.modelID = trimmed }
    }

    func setConfiguration(_ configuration: ModelConfiguration) { self.configuration = configuration }

    func testConnection() async throws -> ModelConnectionStatus {
        let key = try requiredKey()
        var object: [String: Any] = [
            "model": configuration.modelID,
            "store": false,
            "max_output_tokens": 8,
            "instructions": "Reply with OK only.",
            "input": "OK"
        ]
        addReasoningIfNeeded(to: &object)
        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await performJSONRequest(key: key, body: body)
        return .init(provider: configuration.provider, modelID: configuration.modelID)
    }

    func streamChat(_ chat: ChatRequest) async throws -> AsyncThrowingStream<ModelEvent, Error> {
        let key = try requiredKey()
        let body = try chatBody(chat)
        var mutableRequest = makeRequest(key: key, body: body)
        mutableRequest.timeoutInterval = 60
        let request = mutableRequest
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ModelClientError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        // Consume the body so the connection can close, but never surface or log it:
                        // an upstream error payload can contain request-derived text.
                        for try await _ in bytes {}
                        throw sanitizedServerError(status: http.statusCode)
                    }
                    var eventName = ""
                    var completed = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            guard let data = payload.data(using: .utf8),
                                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                            let type = (object["type"] as? String) ?? eventName
                            if type == "response.output_text.delta", let delta = object["delta"] as? String {
                                continuation.yield(.textDelta(delta))
                            } else if type == "response.completed" {
                                continuation.yield(.completed)
                                completed = true
                            } else if type == "response.incomplete" || type == "response.failed" || type == "error" {
                                throw ModelClientError.invalidResponse
                            }
                        }
                    }
                    if !completed { continuation.yield(.completed) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func generateCard(for pet: PetDefinition, languageProfile: LanguageProfile, type: CardType, energy: EnergyState) async throws -> GeneratedCard {
        let key = try requiredKey()
        guard type != .culture else {
            return SeedContent.cards(for: pet.id).first(where: { $0.type == .culture })!
        }
        var lastError: Error = ModelClientError.invalidResponse
        for attempt in 0..<2 {
            do {
                let body = try cardBody(pet: pet, profile: languageProfile, type: type, energy: energy, repair: attempt == 1)
                let data = try await performJSONRequest(key: key, body: body)
                let text = try extractOutputText(from: data)
                guard let cardData = text.data(using: .utf8) else { throw ModelClientError.invalidResponse }
                let card = try JSONDecoder().decode(GeneratedCard.self, from: cardData)
                let report = CardQualityEvaluator().evaluate(card, pet: pet, languageProfile: languageProfile)
                guard card.petID == pet.id, card.type == type, card.isValid,
                      card.supports(languageProfile.currentLevel), report.score >= 70 else {
                    throw ModelClientError.decoding("字段或时长不符合卡片协议")
                }
                return card
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func generateCard(for pet: PetDefinition, type: CardType, energy: EnergyState) async throws -> GeneratedCard {
        try await generateCard(
            for: pet,
            languageProfile: LanguageProfile(targetLanguage: pet.targetLanguage, currentLevel: pet.defaultLevel,
                                             chineseHelpRatio: max(0, 1 - pet.languageRatio)),
            type: type,
            energy: energy
        )
    }

    func proposeMemories(for pet: PetDefinition, transcript: String) async throws -> [MemoryProposal] {
        let key = try requiredKey()
        let body = try memoryBody(pet: pet, transcript: transcript)
        let data = try await performJSONRequest(key: key, body: body)
        let text = try extractOutputText(from: data)
        guard let json = text.data(using: .utf8) else { throw ModelClientError.invalidResponse }
        struct Envelope: Decodable { let memories: [MemoryProposal] }
        return try JSONDecoder().decode(Envelope.self, from: json).memories
            .filter { !$0.content.isEmpty && (1...5).contains($0.importance) }
            .prefix(3).map { $0 }
    }

    private func requiredKey() throws -> String {
        guard let key = try keyStore.loadAPIKey(for: configuration.provider), !key.isEmpty else { throw ModelClientError.missingAPIKey }
        return key
    }

    private func makeRequest(key: String, body: Data) -> URLRequest {
        var request = URLRequest(url: configuration.provider.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performJSONRequest(key: String, body: Data) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(key: key, body: body))
        guard let http = response as? HTTPURLResponse else { throw ModelClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw sanitizedServerError(status: http.statusCode)
        }
        return data
    }

    func chatBody(_ chat: ChatRequest) throws -> Data {
        let policy = LanguagePolicy.policy(for: chat.languageProfile.productiveLevel)
        let correction: String = switch chat.correctionMode {
        case .casual: "先回应意思，不主动纠错。"
        case .light: "先回应意思；每轮最多纠正一个最重要的问题，用【可选纠错】折叠段落表示。"
        case .study: "提供自然改写、必要语法解释和最多三个生词，但保持简洁。"
        }
        let history = chat.recentMessages.suffix(16)
            .map { "\($0.role.rawValue): \(String($0.text.prefix(1_500)))" }
            .joined(separator: "\n")
            .prefix(12_000)
        let memories = chat.confirmedMemories
            .map { "- \(String($0.prefix(500)))" }
            .joined(separator: "\n")
        let inventory = chat.inventoryItems.prefix(2).map { "- \(String($0.prefix(120)))" }.joined(separator: "\n")
        let input = """
        当前精力：\(chat.energy.title)
        你和用户的熟悉等级：Lv.\(chat.relationshipLevel) · \(chat.relationshipTitle)
        已确认的共同记忆（只可引用这些长期记忆）：
        \(memories.isEmpty ? "无" : memories)
        可自然提及的背包物品（不要强行提到）：
        \(inventory.isEmpty ? "无" : inventory)
        最近聊天：
        \(history.isEmpty ? "无" : history)
        用户的新消息：\(chat.userText)
        """
        var object: [String: Any] = [
            "model": configuration.modelID,
            "store": false,
            "stream": true,
            "max_output_tokens": min(700, max(160, policy.recommendedAnswerWords.upperBound * 4)),
            "instructions": chat.pet.personalityPrompt + "\n权威语言策略（覆盖人格文案里的旧等级）：" + policy.prompt(chineseHelpRatio: chat.languageProfile.chineseHelpRatio, correctionMode: chat.languageProfile.correctionMode) + "\n理解等级=\(chat.languageProfile.receptiveLevel.displayName)；表达等级=\(chat.languageProfile.productiveLevel.displayName)。\n" + correction + "\n" + RelationshipExpressionPolicy.policy(for: chat.relationshipLevel).instruction + "\n不要声称读取了屏幕、代码或外部应用。不要制造打卡、内疚或未完成任务。",
            "input": input
        ]
        addReasoningIfNeeded(to: &object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func cardBody(pet: PetDefinition, profile: LanguageProfile, type: CardType, energy: EnergyState, repair: Bool) throws -> Data {
        let policy = LanguagePolicy.policy(for: profile.currentLevel)
        let prompt = "为 \(pet.name) 生成一张 \(type.title) 卡片。当前精力是\(energy.title)。权威语言策略：\(policy.prompt(chineseHelpRatio: profile.chineseHelpRatio, correctionMode: profile.correctionMode))。内容必须能在30到120秒内完成，只含一个核心点。\(repair ? "上次结构不合格；这次严格按 schema。" : "")"
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["petId", "type", "language", "level", "minimumLevel", "recommendedLevel", "maximumLevel", "estimatedSeconds", "hook", "targetText", "prompt", "choices", "answer", "chineseHelp", "sourceTitle", "sourceURL", "memoryKey", "tags", "conceptKey", "originMemoryKey", "modality", "challenge"],
            "properties": [
                "petId": ["type": "string", "enum": [pet.id.rawValue]],
                "type": ["type": "string", "enum": [type.rawValue]],
                "language": ["type": "string"],
                "level": ["type": "string", "enum": [profile.currentLevel.displayName]],
                "minimumLevel": ["type": "string", "enum": [profile.currentLevel.lower.rawValue]],
                "recommendedLevel": ["type": "string", "enum": [profile.currentLevel.rawValue]],
                "maximumLevel": ["type": "string", "enum": [profile.currentLevel.higher.rawValue]],
                "estimatedSeconds": ["type": "integer", "minimum": 30, "maximum": 120],
                "hook": ["type": "string"],
                "targetText": ["type": "string"],
                "prompt": ["type": "string"],
                "choices": ["type": "array", "items": ["type": "string"], "maxItems": 3],
                "answer": ["type": "string"],
                "chineseHelp": ["type": "string"],
                "sourceTitle": ["type": ["string", "null"]],
                "sourceURL": ["type": ["string", "null"]],
                "memoryKey": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string", "enum": CardTopic.allCases.map(\.rawValue)], "maxItems": 3],
                "conceptKey": ["type": "string"],
                "originMemoryKey": ["type": ["string", "null"]],
                "modality": ["type": "string"],
                "challenge": ["type": "integer", "minimum": -1, "maximum": 1]
            ]
        ]
        var object: [String: Any] = [
            "model": configuration.modelID,
            "store": false,
            "max_output_tokens": 700,
            "instructions": pet.personalityPrompt + "\n生成原创、无版权引用、无文化事实断言的微内容。",
            "input": prompt,
            "text": ["format": ["type": "json_schema", "name": "polypals_\(type.rawValue)", "strict": true, "schema": schema]]
        ]
        addReasoningIfNeeded(to: &object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func memoryBody(pet: PetDefinition, transcript: String) throws -> Data {
        let boundedTranscript = String(transcript.prefix(12_000))
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["memories"],
            "properties": [
                "memories": [
                    "type": "array",
                    "maxItems": 3,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["type", "content", "importance"],
                        "properties": [
                            "type": ["type": "string", "enum": ["preference", "topic", "shared-story", "learning-goal"]],
                            "content": ["type": "string"],
                            "importance": ["type": "integer", "minimum": 1, "maximum": 5]
                        ]
                    ]
                ]
            ]
        ]
        var object: [String: Any] = [
            "model": configuration.modelID,
            "store": false,
            "max_output_tokens": 400,
            "instructions": "只提出用户明确说过、且未来对 \(pet.name) 有帮助的长期记忆。不要推断敏感属性，不要保存临时情绪或外部应用信息。",
            "input": boundedTranscript,
            "text": ["format": ["type": "json_schema", "name": "polypals_memory_candidates", "strict": true, "schema": schema]]
        ]
        addReasoningIfNeeded(to: &object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func addReasoningIfNeeded(to object: inout [String: Any]) {
        guard configuration.provider == .deepSeek else { return }
        object["reasoning"] = ["effort": configuration.reasoningEffort.rawValue]
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelClientError.invalidResponse
        }
        if let text = root["output_text"] as? String { return text }
        guard let output = root["output"] as? [[String: Any]] else { throw ModelClientError.invalidResponse }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where (part["type"] as? String) == "output_text" {
                if let text = part["text"] as? String { return text }
            }
        }
        throw ModelClientError.invalidResponse
    }

    private func sanitizedServerError(status: Int) -> ModelClientError {
        let message: String = switch status {
        case 401, 403: "API Key 无效或无权限。"
        case 429: "请求过于频繁，请稍后手动重试。"
        case 500...599: "模型服务暂时不可用。"
        default: "模型请求失败。"
        }
        return .server(status: status, message: message)
    }
}
