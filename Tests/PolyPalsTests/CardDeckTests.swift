import Foundation
import Testing
@testable import PolyPals

@Suite("Card deck rotation")
struct CardDeckTests {
    @Test("Avoids recent cards and same type when alternatives exist")
    func avoidsRecent() {
        let cards = SeedContent.cards(for: .sol)
        let recent = cards.prefix(10).enumerated().map { index, card in
            CardPresentationRecord(memoryKey: card.memoryKey, type: card.type, presentedAt: Date().addingTimeInterval(Double(index)))
        }
        let selected = CardDeckService(randomizer: SeededCardRandomizer(seed: 7))
            .select(from: cards, history: recent, energy: .curious, count: 3)
        #expect(selected.count == 3)
        #expect(Set(selected.map(\.memoryKey)).isDisjoint(with: Set(recent.map(\.memoryKey))))
        #expect(Set(selected.map(\.memoryKey)).count == 3)
    }

    @Test("Fingerprints are stable and ignore spacing and case")
    func fingerprints() {
        let original = SeedContent.cards(for: .ash)[0]
        let equivalent = GeneratedCard(
            petID: original.petID, type: original.type, language: original.language, level: original.level,
            estimatedSeconds: original.estimatedSeconds, hook: original.hook,
            targetText: "  \(original.targetText.uppercased()) ", prompt: original.prompt,
            choices: original.choices, answer: original.answer, chineseHelp: original.chineseHelp,
            memoryKey: "different-key"
        )
        #expect(CardFingerprint.make(original) == CardFingerprint.make(equivalent))
    }
}
