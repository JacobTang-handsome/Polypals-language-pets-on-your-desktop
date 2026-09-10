import Testing
@testable import PolyPals

@Suite("Seed content")
struct SeedContentTests {
    @Test("Each pet covers all seven card types")
    func coverage() {
        for pet in PetID.allCases {
            let cards = SeedContent.cards(for: pet)
            #expect(cards.count == 42)
            #expect(Set(cards.map(\.type)) == Set(CardType.allCases))
            for type in CardType.allCases {
                #expect(cards.filter { $0.type == type }.count == 6)
            }
            #expect(cards.allSatisfy { $0.isValid })
        }
    }

    @Test("Packages are finite and bounded")
    func boundedPackage() {
        #expect(SeedContent.package(for: .sol, energy: .focused, count: 0).count == 1)
        #expect(SeedContent.package(for: .sol, energy: .bored, count: 2).count == 2)
        #expect(SeedContent.package(for: .sol, energy: .curious, count: 99).count == 3)
    }

    @Test("Culture cards carry sources")
    func cultureSources() {
        for pet in PetID.allCases {
            let card = SeedContent.cards(for: pet).first { $0.type == .culture }
            #expect(card?.sourceTitle?.isEmpty == false)
            #expect(card?.sourceURL?.hasPrefix("https://") == true)
        }
    }
}
