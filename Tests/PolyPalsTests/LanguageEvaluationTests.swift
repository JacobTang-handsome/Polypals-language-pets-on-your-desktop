import Foundation
import Testing
@testable import PolyPals

@Suite("Fixed personality and CEFR evaluation set")
struct LanguageEvaluationTests {
    struct EvaluationCase: Sendable {
        let pet: PetID
        let level: CEFRLevel
        let correction: CorrectionMode
        let chineseHelpRatio: Double
    }

    static let cases: [EvaluationCase] = [
        .init(pet: .mousse, level: .a1, correction: .casual, chineseHelpRatio: 0.45),
        .init(pet: .mousse, level: .a2, correction: .light, chineseHelpRatio: 0.35),
        .init(pet: .sol, level: .b1, correction: .light, chineseHelpRatio: 0.15),
        .init(pet: .sol, level: .b2, correction: .study, chineseHelpRatio: 0.10),
        .init(pet: .ash, level: .b2, correction: .casual, chineseHelpRatio: 0.20),
        .init(pet: .ash, level: .c1, correction: .study, chineseHelpRatio: 0.10)
    ]

    @Test("Every required persona-level-mode case emits the same provider-independent constraints", arguments: cases)
    func promptContract(item: EvaluationCase) async throws {
        let pet = PetDefinition.definition(for: item.pet)
        let language = LanguageProfile(targetLanguage: pet.targetLanguage, currentLevel: item.level,
                                       chineseHelpRatio: item.chineseHelpRatio, correctionMode: item.correction)
        let request = ChatRequest(pet: pet, correctionMode: item.correction, energy: .focused,
                                  userText: "evaluation", confirmedMemories: [], recentMessages: [],
                                  languageProfile: language)
        let openAI = OpenAIResponsesClient(keyStore: InMemoryAPIKeyStore(), configuration: .openAIDefault)
        let deepSeek = OpenAIResponsesClient(keyStore: InMemoryAPIKeyStore(), configuration: .deepSeekDefault)
        let openBody = try await openAI.chatBody(request)
        let deepBody = try await deepSeek.chatBody(request)
        let openJSON = try #require(JSONSerialization.jsonObject(with: openBody) as? [String: Any])
        let deepJSON = try #require(JSONSerialization.jsonObject(with: deepBody) as? [String: Any])
        let openInstructions = try #require(openJSON["instructions"] as? String)
        let deepInstructions = try #require(deepJSON["instructions"] as? String)
        for value in ["CEFR=\(item.level.displayName)", "correction=\(item.correction.rawValue)", "chineseHelpRatio=\(String(format: "%.2f", item.chineseHelpRatio))", pet.name] {
            #expect(openInstructions.contains(value))
            #expect(deepInstructions.contains(value))
        }
        #expect(openInstructions == deepInstructions)
        #expect(openJSON["store"] as? Bool == false)
        #expect(deepJSON["store"] as? Bool == false)
    }
}
