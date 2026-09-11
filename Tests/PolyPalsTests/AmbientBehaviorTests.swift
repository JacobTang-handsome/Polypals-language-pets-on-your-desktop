import Foundation
import Testing
@testable import PolyPals

@Suite("Ambient behavior")
struct AmbientBehaviorTests {
    @Test("Focus permits only quiet personality actions while panels suppress everything")
    func suppression() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let base = PetActivityContext(petID: .sol, now: now, hour: 19, lastInteractionAt: now.addingTimeInterval(-2_000), focusActive: false, presentationMode: false, detailPanelOpen: false, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: false, recentActions: [], perchAllowed: true)
        #expect(AmbientBehaviorEngine().decide(context: base) != nil)
        let focused = AmbientBehaviorEngine().decide(context: .init(petID: .sol, now: now, hour: 19, lastInteractionAt: base.lastInteractionAt, focusActive: true, presentationMode: false, detailPanelOpen: false, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: false, recentActions: [], perchAllowed: true))
        #expect(focused?.action == .personality)
        let panelOpen = AmbientBehaviorEngine().decide(context: .init(petID: .sol, now: now, hour: 19, lastInteractionAt: base.lastInteractionAt, focusActive: false, presentationMode: false, detailPanelOpen: true, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: false, recentActions: [], perchAllowed: true))
        #expect(panelOpen == nil)
    }

    @Test("Recent action is not repeated and decision is deterministic")
    func deterministic() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let context = PetActivityContext(petID: .mousse, now: now, hour: 9, lastInteractionAt: now.addingTimeInterval(-2_000), focusActive: false, presentationMode: false, detailPanelOpen: false, chatPanelOpen: false, isDragging: false, isVisible: true, isSleeping: false, hasInventoryItem: true, recentActions: [.tidyItem], perchAllowed: true)
        let engine = AmbientBehaviorEngine()
        let first = engine.decide(context: context)
        let second = engine.decide(context: context)
        #expect(first == second)
        #expect(first?.action != .tidyItem)
    }

    @Test("Natural behavior cadence is low-distraction")
    func cadence() {
        #expect(AmbientBehaviorEngine().minimumIdleTime == 75)
        #expect(AmbientBehaviorEngine().minimumActionInterval == 60)
        let solActions = (0..<8).map { PetPersonalityBehavior.perchIdle(for: .sol, stableSeed: $0) }
        let mousseActions = (0..<8).map { PetPersonalityBehavior.perchIdle(for: .mousse, stableSeed: $0) }
        let ashActions = (0..<8).map { PetPersonalityBehavior.perchIdle(for: .ash, stableSeed: $0) }
        #expect(solActions.contains(.perchWalkLeft))
        #expect(solActions.contains(.perchWalkRight))
        #expect(!mousseActions.contains(.perchWalkLeft) && !mousseActions.contains(.perchWalkRight))
        #expect(!ashActions.contains(.perchWalkLeft) && !ashActions.contains(.perchWalkRight))
        #expect(IdleAnimationCadence.waits(for: .sol).min()! < IdleAnimationCadence.waits(for: .mousse).min()!)
        #expect(IdleAnimationCadence.waits(for: .mousse).min()! < IdleAnimationCadence.waits(for: .ash).min()!)
    }

    @Test("Weighted selection makes walking, personality, and perching reachable")
    func weightedReachability() {
        let engine = AmbientBehaviorEngine()
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        for pet in PetID.allCases {
            let actions = Set((0..<360).compactMap { minute in
                engine.decide(context: .init(
                    petID: pet,
                    now: start.addingTimeInterval(Double(minute * 60)),
                    hour: 19,
                    lastInteractionAt: start.addingTimeInterval(-2_000),
                    focusActive: false,
                    presentationMode: false,
                    detailPanelOpen: false,
                    chatPanelOpen: false,
                    isDragging: false,
                    isVisible: true,
                    isSleeping: false,
                    hasInventoryItem: false,
                    recentActions: [],
                    perchAllowed: true
                ))?.action
            })
            #expect(actions.contains(.walkToEdge))
            #expect(actions.contains(.personality))
            #expect(actions.contains(.perch))
        }
    }

    @Test("Perching is guaranteed after two other natural actions when available")
    func guaranteedPerch() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let decision = AmbientBehaviorEngine().decide(context: .init(
            petID: .ash,
            now: now,
            hour: 19,
            lastInteractionAt: now.addingTimeInterval(-2_000),
            focusActive: false,
            presentationMode: false,
            detailPanelOpen: false,
            chatPanelOpen: false,
            isDragging: false,
            isVisible: true,
            isSleeping: false,
            hasInventoryItem: false,
            recentActions: [.walkToEdge, .stretch],
            perchAllowed: true
        ))
        #expect(decision?.action == .perch)
    }
}
