import Foundation
import SwiftData
import Testing
@testable import PolyPals

@Suite("v0.3 content system")
struct CardSystemTests {
    @Test("Each pet has forty-two offline cards with topic tags")
    func offlinePoolSize() {
        for pet in PetID.allCases {
            let cards = SeedContent.cards(for: pet)
            #expect(cards.count == 42)
            #expect(cards.allSatisfy { !$0.tags.isEmpty })
            #expect(Set(cards.map(\.type)) == Set(CardType.allCases))
        }
    }

    @Test("Quality gate rejects mismatched AI cards")
    func qualityGate() {
        let base = SeedContent.cards(for: .sol)[0]
        let wrong = GeneratedCard(
            petID: .sol, type: .expression, language: "fr", level: "A1",
            estimatedSeconds: 45, hook: base.hook, targetText: base.targetText,
            prompt: base.prompt, choices: base.choices, answer: base.answer,
            chineseHelp: base.chineseHelp, memoryKey: "quality:bad"
        )
        let report = CardQualityEvaluator().evaluate(wrong, pet: .definition(for: .sol))
        #expect(report.score < 70)
        #expect(report.issues.contains("语言与宠物不匹配"))
    }

    @Test("Content pack validation requires sourced culture cards")
    @MainActor
    func contentPackValidation() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let card = SeedContent.cards(for: .sol)[0]
        let manifest = ContentPackManifest(id: "test-pack", title: "测试包", version: "1", author: "PolyPals", language: "es", license: nil)
        let document = ContentPackDocument(schemaVersion: 1, pack: manifest, cards: [card])
        let data = try JSONEncoder().encode(document)
        let imported = try ContentPackImporter(context: container.mainContext).importPack(data)
        #expect(imported == manifest)
        #expect(try container.mainContext.fetch(FetchDescriptor<ContentPackEntity>()).count == 1)
    }

    @Test("Feedback changes selection preference without hiding unrelated cards")
    @MainActor
    func feedbackPreference() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let repository = CardRepository(context: container.mainContext)
        let card = SeedContent.cards(for: .sol)[0]
        repository.recordFeedback(.liked, for: card)
        let preferences = repository.selectionPreferences(for: .sol)
        #expect(preferences.topicWeights[card.tags[0], default: 0] > 0)
        #expect(!preferences.hiddenConcepts.contains(SeedContent.cards(for: .sol)[1].memoryKey))
    }

    @Test("难度反馈方向、边界和宠物隔离")
    @MainActor
    func challengeFeedbackDirection() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let repository = CardRepository(context: container.mainContext)
        let sol = SeedContent.cards(for: .sol)[0]
        let ash = SeedContent.cards(for: .ash)[0]
        repository.recordFeedback(.tooEasy, for: sol)
        repository.recordFeedback(.tooEasy, for: sol)
        #expect(repository.selectionPreferences(for: .sol).challengeBias == 1)
        #expect(repository.selectionPreferences(for: .ash).challengeBias == 0)
        repository.recordFeedback(.tooHard, for: sol)
        repository.recordFeedback(.tooHard, for: sol)
        repository.recordFeedback(.tooHard, for: sol)
        #expect(repository.selectionPreferences(for: .sol).challengeBias == -1)
        repository.recordFeedback(.tooEasy, for: ash)
        #expect(repository.selectionPreferences(for: .ash).challengeBias == 1)
    }

    @Test("屏蔽卡片会同时屏蔽它的概念")
    @MainActor
    func hideSimilarUsesConcept() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let repository = CardRepository(context: container.mainContext)
        let original = SeedContent.cards(for: .sol)[0]
        _ = repository.upsertMetadata(for: original)
        repository.recordFeedback(.hideSimilar, for: original)
        let preferences = repository.selectionPreferences(for: .sol)
        #expect(preferences.hiddenConcepts.contains(original.memoryKey))
        #expect(preferences.hiddenConcepts.contains(original.conceptKey))
    }

    @Test("停用内容包后不再进入选卡池")
    @MainActor
    func disabledPackIsExcluded() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let repository = CardRepository(context: container.mainContext)
        let card = SeedContent.cards(for: .sol)[0]
        let manifest = ContentPackManifest(id: "toggle-pack", title: "开关包", version: "1", author: "PolyPals", language: "es", license: nil)
        let data = try JSONEncoder().encode(ContentPackDocument(schemaVersion: 1, pack: manifest, cards: [card]))
        _ = try ContentPackImporter(context: container.mainContext).importPack(data)
        let pack = try #require(repository.contentPacks().first)
        #expect(repository.cachedCards(for: .sol).contains { $0.memoryKey == card.memoryKey })
        repository.setContentPack(pack, enabled: false)
        #expect(!repository.cachedCards(for: .sol).contains { $0.memoryKey == card.memoryKey })
        #expect(repository.source(of: card) == "pack")
    }

    @Test("审核种子库包含跨形式复现关联")
    func reviewedRecurrenceLinksExist() {
        for petID in PetID.allCases {
            let linked = SeedContent.cards(for: petID).filter { $0.originMemoryKey != nil }
            #expect(linked.count >= 2)
            #expect(Set(linked.map(\.modality)).count >= 2)
        }
    }

    @Test("内容包先预览再导入并识别升级")
    @MainActor
    func contentPackPreview() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let importer = ContentPackImporter(context: container.mainContext)
        let card = SeedContent.cards(for: .mousse)[0]
        let manifest = ContentPackManifest(id: "preview-pack", title: "预览包", version: "1", author: "PolyPals", language: "fr", license: nil)
        let data = try JSONEncoder().encode(ContentPackDocument(schemaVersion: 1, pack: manifest, cards: [card]))
        let before = try importer.preview(data)
        #expect(before.cardCount == 1)
        #expect(!before.isUpgrade)
        _ = try importer.importPack(data)
        #expect(try importer.preview(data).isUpgrade)
    }
}
