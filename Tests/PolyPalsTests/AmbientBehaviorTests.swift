import Foundation
import Testing
@testable import PolyPals

@Suite("Ambient behavior")
struct AmbientBehaviorTests {
    @Test("Focus and panels suppress ambient actions")
    func suppression() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let base = PetActivityContext(petID: .sol, now: now, hour: 19, lastInteractionAt: now.addingTimeInterval(-2_000), focusActive: false, presentationMode: false, detailPanelOpen: false, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: false, recentActions: [])
        #expect(AmbientBehaviorEngine().decide(context: base) != nil)
        #expect(AmbientBehaviorEngine().decide(context: .init(petID: .sol, now: now, hour: 19, lastInteractionAt: base.lastInteractionAt, focusActive: true, presentationMode: false, detailPanelOpen: false, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: false, recentActions: [])) == nil)
    }

    @Test("Recent action is not repeated and decision is deterministic")
    func deterministic() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let context = PetActivityContext(petID: .mousse, now: now, hour: 9, lastInteractionAt: now.addingTimeInterval(-2_000), focusActive: false, presentationMode: false, detailPanelOpen: false, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: true, recentActions: [.tidyItem])
        let engine = AmbientBehaviorEngine()
        let first = engine.decide(context: context)
        let second = engine.decide(context: context)
        #expect(first == second)
        #expect(first?.action != .tidyItem)
    }
}
