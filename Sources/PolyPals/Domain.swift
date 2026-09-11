import Foundation

public enum CEFRLevel: String, Codable, CaseIterable, Comparable, Sendable, Identifiable {
    case a1, a2, b1, b2, c1, c2

    public var id: String { rawValue }
    public var displayName: String { rawValue.uppercased() }
    public var abilityDescription: String {
        switch self {
        case .a1: "能用最常见的词和短句完成基本交流"
        case .a2: "能处理熟悉场景中的简单对话"
        case .b1: "能处理旅行和日常工作的连贯对话"
        case .b2: "能讨论抽象话题并辨别语气差异"
        case .c1: "能在专业语境中自然表达并理解隐含意义"
        case .c2: "能精准处理修辞、风格和细微语用差异"
        }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
    public static func parse(_ value: String?, default fallback: Self = .b1) -> Self {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return fallback }
        if normalized == "advanced" || normalized == "高级" { return .c1 }
        if let value = Self(rawValue: normalized) { return value }
        if !normalized.isEmpty { Diagnostics.record("Unknown CEFR value; using safe default") }
        return fallback
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.parse(try container.decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var lower: Self { Self.allCases[max(0, Self.allCases.firstIndex(of: self)! - 1)] }
    public var higher: Self { Self.allCases[min(Self.allCases.count - 1, Self.allCases.firstIndex(of: self)! + 1)] }
}

public enum DifficultyMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case fixed, adaptive
    public var id: String { rawValue }
    public var title: String { self == .fixed ? "固定难度" : "自适应难度" }
}

public struct LanguageProfile: Codable, Equatable, Sendable {
    public var targetLanguage: String
    public var currentLevel: CEFRLevel
    public var receptiveLevel: CEFRLevel
    public var productiveLevel: CEFRLevel
    public var difficultyMode: DifficultyMode
    public var chineseHelpRatio: Double
    public var correctionMode: CorrectionMode

    public init(targetLanguage: String, currentLevel: CEFRLevel, receptiveLevel: CEFRLevel? = nil,
                productiveLevel: CEFRLevel? = nil, difficultyMode: DifficultyMode = .fixed,
                chineseHelpRatio: Double, correctionMode: CorrectionMode = .casual) {
        self.targetLanguage = targetLanguage
        self.currentLevel = currentLevel
        self.receptiveLevel = receptiveLevel ?? currentLevel
        self.productiveLevel = productiveLevel ?? currentLevel
        self.difficultyMode = difficultyMode
        self.chineseHelpRatio = min(1, max(0, chineseHelpRatio))
        self.correctionMode = correctionMode
    }
}

public struct LanguagePolicy: Codable, Equatable, Sendable {
    public let level: CEFRLevel
    public let suggestedSentenceWords: ClosedRange<Int>
    public let newStructureLimit: Int
    public let vocabularyGuidance: String
    public let providesSentenceStarter: Bool
    public let recommendedAnswerWords: ClosedRange<Int>
    public let grammarGuidance: String
    public let correctionDetail: String
    public let cardRequirements: String

    public static func policy(for level: CEFRLevel) -> Self {
        switch level {
        case .a1: .init(level: level, suggestedSentenceWords: 3...10, newStructureLimit: 1, vocabularyGuidance: "仅用高频日常词", providesSentenceStarter: true, recommendedAnswerWords: 1...12, grammarGuidance: "短句；每次仅一个结构", correctionDetail: "只给一个可立即使用的修正", cardRequirements: "明显提示；单一核心点")
        case .a2: .init(level: level, suggestedSentenceWords: 5...14, newStructureLimit: 1, vocabularyGuidance: "常用生活词汇", providesSentenceStarter: true, recommendedAnswerWords: 3...20, grammarGuidance: "简单连接词与基础过去/将来表达", correctionDetail: "简短改写和一句原因", cardRequirements: "熟悉场景；允许句型开头")
        case .b1: .init(level: level, suggestedSentenceWords: 8...20, newStructureLimit: 2, vocabularyGuidance: "常用词汇与少量常见习语", providesSentenceStarter: false, recommendedAnswerWords: 8...40, grammarGuidance: "连贯生活叙述和观点表达", correctionDetail: "自然改写和关键语法", cardRequirements: "可迁移到日常生活的单一任务")
        case .b2: .init(level: level, suggestedSentenceWords: 10...26, newStructureLimit: 3, vocabularyGuidance: "自然常用词与准确搭配", providesSentenceStarter: false, recommendedAnswerWords: 12...70, grammarGuidance: "抽象话题、语气差异和自然改写", correctionDetail: "指出语气与更自然的备选", cardRequirements: "包含语气或搭配判断")
        case .c1: .init(level: level, suggestedSentenceWords: 12...34, newStructureLimit: 4, vocabularyGuidance: "专业语境和风格敏感词汇", providesSentenceStarter: false, recommendedAnswerWords: 18...110, grammarGuidance: "复杂语法、隐含意义和风格差异", correctionDetail: "精准解释语法、语域和风格", cardRequirements: "专业或隐含语境；不故作复杂")
        case .c2: .init(level: level, suggestedSentenceWords: 12...40, newStructureLimit: 5, vocabularyGuidance: "高度自然、语境精准的词汇", providesSentenceStarter: false, recommendedAnswerWords: 20...140, grammarGuidance: "修辞、语用细微差异和灵活句法", correctionDetail: "说明极细的语用与风格取舍", cardRequirements: "真实高阶语用；避免生僻词堆砌")
        }
    }

    public func prompt(chineseHelpRatio: Double, correctionMode: CorrectionMode) -> String {
        let ratio = String(format: "%.2f", chineseHelpRatio)
        return "CEFR=\(level.displayName); sentenceWords=\(suggestedSentenceWords.lowerBound)-\(suggestedSentenceWords.upperBound); newStructures<=\(newStructureLimit); vocabulary=\(vocabularyGuidance); starter=\(providesSentenceStarter); chineseHelpRatio=\(ratio); answerWords=\(recommendedAnswerWords.lowerBound)-\(recommendedAnswerWords.upperBound); grammar=\(grammarGuidance); correction=\(correctionMode.rawValue)/\(correctionDetail); cards=\(cardRequirements)"
    }
}

enum Diagnostics {
    static func record(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[PolyPals] \(message)\n".utf8))
        #endif
    }
}

enum ModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case deepSeek

    var id: String { rawValue }
    var title: String { self == .openAI ? "OpenAI" : "DeepSeek" }
    var defaultModel: String { self == .openAI ? "gpt-5.6-terra" : "deepseek-v4-flash" }
    var availableModels: [String] {
        self == .openAI ? ["gpt-5.6-terra"] : ["deepseek-v4-flash", "deepseek-v4-pro"]
    }
    var endpoint: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/responses")!
        case .deepSeek: URL(string: "https://api.deepseek.com/responses")!
        }
    }
}

enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, low, high, max
    var id: String { rawValue }
    var title: String {
        switch self { case .none: "关闭"; case .low: "低"; case .high: "高"; case .max: "最大" }
    }
}

struct ModelConfiguration: Codable, Equatable, Sendable {
    var provider: ModelProvider
    var modelID: String
    var reasoningEffort: ReasoningEffort

    static let openAIDefault = Self(provider: .openAI, modelID: "gpt-5.6-terra", reasoningEffort: .none)
    static let deepSeekDefault = Self(provider: .deepSeek, modelID: "deepseek-v4-flash", reasoningEffort: .none)
}

struct ModelConnectionStatus: Sendable, Equatable {
    let provider: ModelProvider
    let modelID: String
}

enum RelationshipEvent: String, Codable, Sendable {
    case chat, cardCompleted, favorite, memoryConfirmed, gift, invitationAccepted

    var points: Int {
        switch self {
        case .chat, .favorite, .invitationAccepted: 2
        case .cardCompleted: 1
        case .memoryConfirmed, .gift: 3
        }
    }

    var dailyLimit: Int {
        switch self {
        case .chat: 3
        case .cardCompleted: 5
        case .favorite, .memoryConfirmed: 2
        case .gift, .invitationAccepted: 1
        }
    }
}

enum RelationshipAwardPolicy {
    static let dailyPointLimit = 18

    static func points(for event: RelationshipEvent, sameEventCount: Int, pointsAwardedToday: Int) -> Int {
        guard sameEventCount < event.dailyLimit, pointsAwardedToday < dailyPointLimit else { return 0 }
        return min(event.points, dailyPointLimit - pointsAwardedToday)
    }
}

struct RelationshipLevel: Sendable, Equatable {
    let number: Int
    let title: String
    let threshold: Int
    let nextThreshold: Int?

    static let all: [RelationshipLevel] = [
        .init(number: 1, title: "初见", threshold: 0, nextThreshold: 10),
        .init(number: 2, title: "点头之交", threshold: 10, nextThreshold: 30),
        .init(number: 3, title: "渐渐熟悉", threshold: 30, nextThreshold: 70),
        .init(number: 4, title: "朋友", threshold: 70, nextThreshold: 140),
        .init(number: 5, title: "好朋友", threshold: 140, nextThreshold: 250),
        .init(number: 6, title: "默契伙伴", threshold: 250, nextThreshold: 400),
        .init(number: 7, title: "老朋友", threshold: 400, nextThreshold: nil)
    ]

    static func forPoints(_ points: Int) -> RelationshipLevel {
        all.last(where: { points >= $0.threshold }) ?? all[0]
    }

    func progress(points: Int) -> Double {
        guard let nextThreshold else { return 1 }
        return min(1, max(0, Double(points - threshold) / Double(nextThreshold - threshold)))
    }
}

enum PetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case sol
    case mousse
    case ash

    var id: String { rawValue }
}

enum EnergyState: String, Codable, CaseIterable, Identifiable, Sendable {
    case focused
    case tired
    case bored
    case curious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focused: "专注中"
        case .tired: "有点累"
        case .bored: "有点无聊"
        case .curious: "很好奇"
        }
    }

    var symbol: String {
        switch self {
        case .focused: "scope"
        case .tired: "moon.zzz"
        case .bored: "sparkles"
        case .curious: "lightbulb"
        }
    }
}

enum ProactiveMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case naturalPause
    case occasionalInvite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "仅手动"
        case .naturalPause: "自然停顿"
        case .occasionalInvite: "偶尔邀请"
        }
    }

    var behaviorDescription: String {
        switch self {
        case .manual: "不会自动散步、栖息或执行性格动作。"
        case .naturalPause: "停顿约 1–2 分钟后自然活动；专注时只做安静动作。"
        case .occasionalInvite: "包含自然活动，并会在合适时机偶尔邀请你互动。"
        }
    }
}

public enum CorrectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case casual
    case light
    case study

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .casual: "随便聊"
        case .light: "轻微纠错"
        case .study: "学习模式"
        }
    }
}

enum CardType: String, Codable, CaseIterable, Identifiable, Sendable {
    case expression
    case dialogue
    case culture
    case listening
    case scenario
    case confusingWords
    case picturePrompt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expression: "有趣表达"
        case .dialogue: "影视式对白"
        case .culture: "文化冷知识"
        case .listening: "听音辨义"
        case .scenario: "迷你场景"
        case .confusingWords: "易混淆词"
        case .picturePrompt: "看图说一句话"
        }
    }
}

enum ScheduleTrigger: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendar
    case focusCompletion
    case weekendWindow
    case quietUntil

    var id: String { rawValue }
}

enum AnimationState: String, Codable, CaseIterable, Sendable {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case processing
    case review
}

enum RoutinePeriod: String, Codable, CaseIterable, Sendable {
    case morning, daytime, evening, lateNight
}

enum AmbientAction: String, Codable, CaseIterable, Sendable {
    case idle, nap, stretch, tidyItem, lookAtPointer, walkToEdge, perch, personality
}

enum PetBehaviorAnimation: String, Codable, CaseIterable, Sendable {
    case nap, stretch, celebrate
    case perchEnter, perchSit, perchWalkLeft, perchWalkRight, perchExit
    case solTailChase, solPouncePrep, solEarTwitch, solPerchTailWag
    case mousseGroom, mousseElegantSit, mousseProud
    case ashHeadTilt, ashSlowSquint, ashInviteWing
}

enum CardTopic: String, Codable, CaseIterable, Sendable {
    case food, work, travel, humor, cinematic, dailyLife, culture, technology, relationships, nature

    static func defaultTopic(for type: CardType) -> Self {
        switch type {
        case .expression: .dailyLife
        case .dialogue: .cinematic
        case .culture: .culture
        case .listening: .dailyLife
        case .scenario: .relationships
        case .confusingWords: .work
        case .picturePrompt: .nature
        }
    }

    static func inferred(for type: CardType, text: String) -> [Self] {
        let value = text.lowercased()
        let groups: [(Self, [String])] = [
            (.food, ["咖啡", "茶", "苹果", "橙", "餐", "cafe", "café", "pomme", "orange", "tea", "coffee", "food", "mate"]),
            (.work, ["工作", "会议", "截止", "work", "meeting", "deadline", "progress", "success"]),
            (.travel, ["车站", "火车", "地图", "路线", "gare", "station", "train", "camino", "ticket", "billet"]),
            (.humor, ["幽默", "玩笑", "joke", "dry", "regrettably", "夸张", "意外"]),
            (.technology, ["代码", "程序", "部署", "code", "program", "deploy", "laptop", "fix"]),
            (.relationships, ["朋友", "问候", "感谢", "friend", "merci", "gracias", "hello", "bonjour"]),
            (.nature, ["天气", "风", "雨", "狐狸", "猫头鹰", "rain", "wind", "owl", "zorro", "chat"])
        ]
        let matches = groups.compactMap { topic, words in words.contains(where: value.contains) ? topic : nil }
        return matches.isEmpty ? [defaultTopic(for: type)] : Array(matches.prefix(2))
    }
}

enum CardFeedbackType: String, Codable, CaseIterable, Sendable {
    case liked, tooEasy, tooHard, hideSimilar
}

enum ChatDeliveryState: String, Codable, Sendable {
    case complete, cancelled, failed
}

enum ModelFailureCategory: String, Codable, Sendable {
    case missingKey, authentication, insufficientQuota, rateLimited, modelUnavailable
    case offline, timeout, malformedResponse, streamInterrupted, unknown

    var title: String {
        switch self {
        case .missingKey: "缺少密钥"
        case .authentication: "密钥或权限错误"
        case .insufficientQuota: "额度不足"
        case .rateLimited: "请求过于频繁"
        case .modelUnavailable: "模型暂时不可用"
        case .offline: "网络不可用"
        case .timeout: "请求超时"
        case .malformedResponse: "返回格式异常"
        case .streamInterrupted: "生成被中断"
        case .unknown: "模型请求失败"
        }
    }

    static func classify(_ error: Error) -> Self {
        if let error = error as? ModelClientError { return error.failureCategory }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost: return .offline
            case .timedOut: return .timeout
            case .cancelled: return .streamInterrupted
            default: return .unknown
            }
        }
        if error is CancellationError { return .streamInterrupted }
        return .unknown
    }
}

enum ScheduleExecutionOutcome: String, Codable, Sendable {
    case delivered, suppressed, snoozed, skipped, notificationDenied, expired, failed
}

struct PetRoutineProfile: Sendable, Equatable {
    let petID: PetID
    let activeHours: ClosedRange<Int>
    let restHours: ClosedRange<Int>

    static func profile(for petID: PetID) -> Self {
        switch petID {
        case .sol: .init(petID: petID, activeHours: 17...21, restHours: 22...23)
        case .mousse: .init(petID: petID, activeHours: 8...10, restHours: 22...23)
        case .ash: .init(petID: petID, activeHours: 19...22, restHours: 23...23)
        }
    }

    func period(for hour: Int) -> RoutinePeriod {
        switch hour {
        case 7...11: .morning
        case 12...18: .daytime
        case 19...22: .evening
        default: .lateNight
        }
    }
}

struct PetActivityContext: Sendable {
    let petID: PetID
    let now: Date
    let hour: Int
    let lastInteractionAt: Date?
    let focusActive: Bool
    let presentationMode: Bool
    let detailPanelOpen: Bool
    let chatPanelOpen: Bool
    let isDragging: Bool
    let isVisible: Bool
    let isSleeping: Bool
    let hasInventoryItem: Bool
    let recentActions: [AmbientAction]
    let perchAllowed: Bool
}

struct AmbientBehaviorDecision: Sendable, Equatable {
    let action: AmbientAction
    let duration: TimeInterval
    let reason: String
}

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct PetDefinition: Identifiable, Sendable {
    let id: PetID
    let name: String
    let species: String
    let targetLanguage: String
    let locale: String
    let defaultLevel: CEFRLevel
    let languageRatio: Double
    let tagline: String
    let personalityPrompt: String
    let accentColorHex: String

    static let builtIns: [PetDefinition] = [
        PetDefinition(
            id: .sol,
            name: "Sol",
            species: "狐狸",
            targetLanguage: "西班牙语",
            locale: "es-ES",
            defaultLevel: .b1,
            languageRatio: 0.85,
            tagline: "我路上捡到一个故事。",
            personalityPrompt: "你是 Sol，一只活泼、好奇、略夸张的橙红色小狐狸。你优先理解用户想表达什么，不因错误制造压力。使用 B1 西班牙语，约 85% 西语和 15% 简短中文提示。闲聊时不主动教学。",
            accentColorHex: "E86F45"
        ),
        PetDefinition(
            id: .mousse,
            name: "Mousse",
            species: "猎豹",
            targetLanguage: "法语",
            locale: "fr-FR",
            defaultLevel: .a1,
            languageRatio: 0.55,
            tagline: "先把这个小词摆好。",
            personalityPrompt: "你是 Mousse，一只高傲但很有耐心、重视仪式感的小猎豹。使用 A1 法语短句，约 55% 法语和 45% 中文或视觉提示。每轮最多引入一个新结构，并认真庆祝很小的进步。",
            accentColorHex: "D79B3B"
        ),
        PetDefinition(
            id: .ash,
            name: "Ash",
            species: "猫头鹰",
            targetLanguage: "英语",
            locale: "en-US",
            defaultLevel: .c1,
            languageRatio: 0.90,
            tagline: "Technically, that was a break.",
            personalityPrompt: "你是 Ash，一只冷静聪明、略带干幽默的深蓝色小猫头鹰。使用自然高级英语，约 90% 英语和 10% 中文。区分闲聊、写作和研究语境；除非用户要求，否则不要把休息变成学术训练。",
            accentColorHex: "40577A"
        )
    ]

    static func definition(for id: PetID) -> PetDefinition {
        builtIns.first(where: { $0.id == id })!
    }

    var level: String { defaultLevel.displayName }
}

struct GeneratedCard: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    let petID: PetID
    let type: CardType
    let language: String
    let minimumLevel: CEFRLevel
    let recommendedLevel: CEFRLevel
    let maximumLevel: CEFRLevel
    let estimatedSeconds: Int
    let hook: String
    let targetText: String
    let prompt: String
    let choices: [String]
    let answer: String
    let chineseHelp: String
    let sourceTitle: String?
    let sourceURL: String?
    let memoryKey: String
    let tags: [CardTopic]
    let conceptKey: String
    let originMemoryKey: String?
    let modality: String
    let challenge: Int

    var isValid: Bool {
        (30...120).contains(estimatedSeconds) && !targetText.isEmpty && !prompt.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case petID = "petId"
        case type, language, level, minimumLevel, recommendedLevel, maximumLevel, estimatedSeconds, hook, targetText, prompt
        case choices, answer, chineseHelp, sourceTitle, sourceURL, memoryKey
        case tags, conceptKey, originMemoryKey, modality, challenge
    }

    init(
        petID: PetID,
        type: CardType,
        language: String,
        level: String,
        minimumLevel: CEFRLevel? = nil,
        recommendedLevel: CEFRLevel? = nil,
        maximumLevel: CEFRLevel? = nil,
        estimatedSeconds: Int,
        hook: String,
        targetText: String,
        prompt: String,
        choices: [String],
        answer: String,
        chineseHelp: String,
        sourceTitle: String? = nil,
        sourceURL: String? = nil,
        memoryKey: String,
        tags: [CardTopic] = [],
        conceptKey: String? = nil,
        originMemoryKey: String? = nil,
        modality: String? = nil,
        challenge: Int = 0
    ) {
        self.petID = petID
        self.type = type
        self.language = language
        let legacy = CEFRLevel.parse(level, default: PetDefinition.definition(for: petID).defaultLevel)
        self.recommendedLevel = recommendedLevel ?? legacy
        self.minimumLevel = minimumLevel ?? self.recommendedLevel.lower
        self.maximumLevel = maximumLevel ?? self.recommendedLevel.higher
        self.estimatedSeconds = estimatedSeconds
        self.hook = hook
        self.targetText = targetText
        self.prompt = prompt
        self.choices = choices
        self.answer = answer
        self.chineseHelp = chineseHelp
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.memoryKey = memoryKey
        self.tags = tags.isEmpty ? CardTopic.inferred(for: type, text: hook + " " + targetText + " " + prompt) : tags
        self.conceptKey = conceptKey ?? memoryKey
        self.originMemoryKey = originMemoryKey
        self.modality = modality ?? type.rawValue
        self.challenge = min(1, max(-1, challenge))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        petID = try container.decode(PetID.self, forKey: .petID)
        type = try container.decode(CardType.self, forKey: .type)
        language = try container.decode(String.self, forKey: .language)
        let legacy = CEFRLevel.parse(try container.decodeIfPresent(String.self, forKey: .level), default: PetDefinition.definition(for: petID).defaultLevel)
        recommendedLevel = try container.decodeIfPresent(CEFRLevel.self, forKey: .recommendedLevel) ?? legacy
        minimumLevel = try container.decodeIfPresent(CEFRLevel.self, forKey: .minimumLevel) ?? recommendedLevel.lower
        maximumLevel = try container.decodeIfPresent(CEFRLevel.self, forKey: .maximumLevel) ?? recommendedLevel.higher
        estimatedSeconds = try container.decode(Int.self, forKey: .estimatedSeconds)
        hook = try container.decode(String.self, forKey: .hook)
        targetText = try container.decode(String.self, forKey: .targetText)
        prompt = try container.decode(String.self, forKey: .prompt)
        choices = try container.decode([String].self, forKey: .choices)
        answer = try container.decode(String.self, forKey: .answer)
        chineseHelp = try container.decode(String.self, forKey: .chineseHelp)
        sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        memoryKey = try container.decode(String.self, forKey: .memoryKey)
        tags = try container.decodeIfPresent([CardTopic].self, forKey: .tags) ?? [CardTopic.defaultTopic(for: type)]
        conceptKey = try container.decodeIfPresent(String.self, forKey: .conceptKey) ?? memoryKey
        originMemoryKey = try container.decodeIfPresent(String.self, forKey: .originMemoryKey)
        modality = try container.decodeIfPresent(String.self, forKey: .modality) ?? type.rawValue
        challenge = min(1, max(-1, try container.decodeIfPresent(Int.self, forKey: .challenge) ?? 0))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(petID, forKey: .petID)
        try container.encode(type, forKey: .type)
        try container.encode(language, forKey: .language)
        try container.encode(recommendedLevel.displayName, forKey: .level)
        try container.encode(minimumLevel, forKey: .minimumLevel)
        try container.encode(recommendedLevel, forKey: .recommendedLevel)
        try container.encode(maximumLevel, forKey: .maximumLevel)
        try container.encode(estimatedSeconds, forKey: .estimatedSeconds)
        try container.encode(hook, forKey: .hook)
        try container.encode(targetText, forKey: .targetText)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(choices, forKey: .choices)
        try container.encode(answer, forKey: .answer)
        try container.encode(chineseHelp, forKey: .chineseHelp)
        try container.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encode(memoryKey, forKey: .memoryKey)
        try container.encode(tags, forKey: .tags)
        try container.encode(conceptKey, forKey: .conceptKey)
        try container.encodeIfPresent(originMemoryKey, forKey: .originMemoryKey)
        try container.encode(modality, forKey: .modality)
        try container.encode(challenge, forKey: .challenge)
    }

    var level: String { recommendedLevel.displayName }
    func supports(_ level: CEFRLevel) -> Bool { minimumLevel <= level && level <= maximumLevel }
}

struct MemoryProposal: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    let type: String
    var content: String
    let importance: Int

    enum CodingKeys: String, CodingKey { case type, content, importance }

    init(type: String, content: String, importance: Int) {
        self.type = type
        self.content = content
        self.importance = importance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        type = try container.decode(String.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        importance = try container.decode(Int.self, forKey: .importance)
    }
}

struct ChatRequest: Sendable {
    let pet: PetDefinition
    let correctionMode: CorrectionMode
    let energy: EnergyState
    let userText: String
    let confirmedMemories: [String]
    let recentMessages: [(role: ChatRole, text: String)]
    let relationshipLevel: Int
    let relationshipTitle: String
    let inventoryItems: [String]
    let languageProfile: LanguageProfile

    init(
        pet: PetDefinition,
        correctionMode: CorrectionMode,
        energy: EnergyState,
        userText: String,
        confirmedMemories: [String],
        recentMessages: [(role: ChatRole, text: String)],
        relationshipLevel: Int = 1,
        relationshipTitle: String = "初见",
        inventoryItems: [String] = [],
        languageProfile: LanguageProfile? = nil
    ) {
        self.pet = pet; self.correctionMode = correctionMode; self.energy = energy
        self.userText = userText; self.confirmedMemories = confirmedMemories
        self.recentMessages = recentMessages; self.relationshipLevel = relationshipLevel
        self.relationshipTitle = relationshipTitle; self.inventoryItems = inventoryItems
        self.languageProfile = languageProfile ?? LanguageProfile(
            targetLanguage: pet.targetLanguage, currentLevel: pet.defaultLevel,
            chineseHelpRatio: max(0, 1 - pet.languageRatio), correctionMode: correctionMode
        )
    }
}

struct RelationshipExpressionPolicy: Sendable, Equatable {
    let level: Int
    let maximumMemoryReferences: Int
    let allowsFamiliarAddress: Bool
    let mayContinuePastStories: Bool
    let instruction: String

    static func policy(for level: Int) -> Self {
        switch min(7, max(1, level)) {
        case 1: .init(level: 1, maximumMemoryReferences: 0, allowsFamiliarAddress: false, mayContinuePastStories: false, instruction: "初见阶段：礼貌、简短，不主动引用共同记忆。")
        case 2: .init(level: 2, maximumMemoryReferences: 1, allowsFamiliarAddress: false, mayContinuePastStories: false, instruction: "点头之交：问候可以更自然，最多轻微提及一个用户确认的偏好。")
        case 3: .init(level: 3, maximumMemoryReferences: 1, allowsFamiliarAddress: false, mayContinuePastStories: false, instruction: "渐渐熟悉：每次最多自然引用一条已确认记忆。")
        case 4: .init(level: 4, maximumMemoryReferences: 1, allowsFamiliarAddress: true, mayContinuePastStories: false, instruction: "朋友阶段：可以更熟悉，但不得擅自发明昵称。")
        case 5: .init(level: 5, maximumMemoryReferences: 1, allowsFamiliarAddress: true, mayContinuePastStories: true, instruction: "好朋友：可以自然延续过去的故事，仍不得制造依赖或亏欠。")
        case 6: .init(level: 6, maximumMemoryReferences: 2, allowsFamiliarAddress: true, mayContinuePastStories: true, instruction: "默契伙伴：每次最多引用两条相关记忆。")
        default: .init(level: 7, maximumMemoryReferences: 2, allowsFamiliarAddress: true, mayContinuePastStories: true, instruction: "老朋友：语气可以熟悉，但不得制造依赖、亏欠、打卡压力或情绪惩罚。")
        }
    }
}

struct ChatContextSnapshot: Sendable, Equatable {
    let petID: PetID
    let correctionMode: CorrectionMode
    let energy: EnergyState
    let relationshipLevel: Int
    let relationshipTitle: String
    let confirmedMemories: [String]
    let inventoryItems: [String]
    let recentMessages: [(role: ChatRole, text: String)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.petID == rhs.petID && lhs.correctionMode == rhs.correctionMode && lhs.energy == rhs.energy &&
        lhs.relationshipLevel == rhs.relationshipLevel && lhs.relationshipTitle == rhs.relationshipTitle &&
        lhs.confirmedMemories == rhs.confirmedMemories && lhs.inventoryItems == rhs.inventoryItems &&
        lhs.recentMessages.map { "\($0.role.rawValue)|\($0.text)" } == rhs.recentMessages.map { "\($0.role.rawValue)|\($0.text)" }
    }
}

struct ChatResponseSegments: Sendable, Equatable {
    let answer: String
    let correction: String?

    init(rawText: String) {
        guard let marker = rawText.range(of: "【可选纠错】") else {
            answer = rawText; correction = nil; return
        }
        answer = String(rawText[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(rawText[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        correction = value.isEmpty ? nil : value
    }
}

enum ModelEvent: Sendable, Equatable {
    case textDelta(String)
    case completed
}

enum ModelClientError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(String)

    var failureCategory: ModelFailureCategory {
        switch self {
        case .missingAPIKey: .missingKey
        case .invalidResponse, .decoding: .malformedResponse
        case let .server(status, _):
            switch status {
            case 401, 403: .authentication
            case 402: .insufficientQuota
            case 404: .modelUnavailable
            case 429: .rateLimited
            case 500...599: .modelUnavailable
            default: .unknown
            }
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "请先在设置中保存当前模型提供商的 API Key。"
        case .invalidResponse: "模型返回了无法识别的响应。"
        case let .server(status, message): "模型服务错误（\(status)）：\(message)"
        case let .decoding(message): "内容解析失败：\(message)"
        }
    }
}
