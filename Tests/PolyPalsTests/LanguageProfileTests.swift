import Foundation
import SwiftData
import Testing
@testable import PolyPals

@Suite("CEFR language profiles")
struct LanguageProfileTests {
    @Test("Legacy values parse safely and levels remain ordered")
    func compatibility() {
        #expect(CEFRLevel.parse("Advanced") == .c1)
        #expect(CEFRLevel.parse(" B2 ") == .b2)
        #expect(CEFRLevel.parse("unknown", default: .a1) == .a1)
        #expect(CEFRLevel.allCases.sorted() == [.a1, .a2, .b1, .b2, .c1, .c2])
    }

    @Test("Every level produces an actionable policy")
    func policies() {
        for level in CEFRLevel.allCases {
            let policy = LanguagePolicy.policy(for: level)
            #expect(policy.suggestedSentenceWords.lowerBound > 0)
            #expect(policy.newStructureLimit > 0)
            #expect(policy.prompt(chineseHelpRatio: 0.25, correctionMode: .light).contains("CEFR=\(level.displayName)"))
        }
        #expect(LanguagePolicy.policy(for: .a1).providesSentenceStarter)
        #expect(!LanguagePolicy.policy(for: .c1).providesSentenceStarter)
    }

    @Test("Legacy cards gain a compatible range")
    func legacyCardRange() throws {
        let json = Data("""
        {"petId":"ash","type":"expression","language":"en","level":"Advanced","estimatedSeconds":45,"hook":"h","targetText":"That worked.","prompt":"p","choices":[],"answer":"a","chineseHelp":"h","memoryKey":"legacy"}
        """.utf8)
        let card = try JSONDecoder().decode(GeneratedCard.self, from: json)
        #expect(card.recommendedLevel == .c1)
        #expect(card.minimumLevel == .b2)
        #expect(card.maximumLevel == .c2)
    }

    @Test("Version 3 profile migrates to V4 without replacing old data")
    @MainActor
    func v3ToV4() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("polypals-v4-\(UUID().uuidString).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) } }
        let schema = Schema(versionedSchema: PolyPalsSchemaV3.self)
        let old = try ModelContainer(for: schema, configurations: .init(schema: schema, url: url))
        let row = PetProfileEntity(definition: .definition(for: .ash)); row.difficulty = "Advanced"; row.relationshipPoints = 77
        old.mainContext.insert(row); try old.mainContext.save()
        let migrated = try PersistenceFactory.makeContainer(at: url)
        let profiles = try migrated.mainContext.fetch(FetchDescriptor<PetProfileEntity>())
        let languages = try migrated.mainContext.fetch(FetchDescriptor<LanguageProfileEntity>())
        #expect(profiles.first?.relationshipPoints == 77)
        #expect(languages.first?.value.currentLevel == .c1)
    }
}
