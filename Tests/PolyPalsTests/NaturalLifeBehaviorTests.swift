import CoreGraphics
import Testing
@testable import PolyPals

@Suite("Natural life and window perching")
struct NaturalLifeBehaviorTests {
    private let context = PerchSelectionContext(
        petID: .sol,
        petSize: CGSize(width: 128, height: 138),
        petFrame: CGRect(x: 900, y: 40, width: 128, height: 138),
        screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        screenID: "main",
        ownPID: 99,
        frontmostPID: 42,
        reservedRanges: []
    )

    @Test("Quartz frames convert to AppKit coordinates")
    func coordinateConversion() {
        let result = PerchCoordinateConverter.appKitFrame(
            fromQuartz: CGRect(x: 100, y: 80, width: 800, height: 600),
            desktopTop: 900
        )
        #expect(result == CGRect(x: 100, y: 220, width: 800, height: 600))
    }

    @Test("Selector prefers the frontmost safe normal window")
    func selection() throws {
        let windows = [
            PerchWindow(windowNumber: 1, ownerPID: 7, ownerName: "Background", frame: CGRect(x: 80, y: 100, width: 800, height: 500), layer: 0, isOnScreen: true),
            PerchWindow(windowNumber: 2, ownerPID: 42, ownerName: "Front", frame: CGRect(x: 180, y: 80, width: 900, height: 620), layer: 0, isOnScreen: true),
            PerchWindow(windowNumber: 3, ownerPID: 99, ownerName: "PolyPals", frame: CGRect(x: 300, y: 120, width: 700, height: 500), layer: 0, isOnScreen: true)
        ]
        let target = try #require(PerchTargetSelector().select(windows: windows, context: context, desktopTop: 900))
        #expect(target.windowNumber == 2)
        #expect(target.ownerPID == 42)
        #expect(target.anchor.x >= target.windowFrame.minX + 112)
        #expect(target.anchor.x <= target.windowFrame.maxX - 28 - context.petSize.width)
    }

    @Test("Small, overlay, own, fullscreen and occupied windows are rejected")
    func filtering() {
        let selector = PerchTargetSelector()
        let bad = [
            PerchWindow(windowNumber: 1, ownerPID: 1, ownerName: "Tiny", frame: CGRect(x: 10, y: 10, width: 200, height: 100), layer: 0, isOnScreen: true),
            PerchWindow(windowNumber: 2, ownerPID: 1, ownerName: "Overlay", frame: CGRect(x: 10, y: 10, width: 800, height: 600), layer: 3, isOnScreen: true),
            PerchWindow(windowNumber: 3, ownerPID: 99, ownerName: "Own", frame: CGRect(x: 10, y: 10, width: 800, height: 600), layer: 0, isOnScreen: true),
            PerchWindow(windowNumber: 4, ownerPID: 1, ownerName: "Fullscreen", frame: CGRect(x: 0, y: 0, width: 1_440, height: 900), layer: 0, isOnScreen: true)
        ]
        #expect(selector.select(windows: bad, context: context, desktopTop: 900) == nil)
    }

    @Test("Permission-free mode has a bounded screen-edge target")
    func screenFallback() {
        let target = PerchTargetSelector().screenEdgeFallback(context: context)
        #expect(target.kind == .screenEdge)
        #expect(context.screenFrame.contains(target.anchor))
        #expect(target.anchor.x >= context.screenFrame.minX + 28)
    }

    @Test("Perch state machine follows the complete lifecycle and cancels")
    func stateMachine() {
        let target = PerchTargetSelector().screenEdgeFallback(context: context)
        var machine = PetBehaviorStateMachine()
        let beganChoosing = machine.beginChoosing()
        #expect(beganChoosing)
        machine.walk(to: target)
        #expect(machine.state == .walkingToPerch(target))
        machine.reachedPerch()
        #expect(machine.state == .jumpingOntoPerch(target))
        machine.landed()
        #expect(machine.state == .perched(target))
        machine.beginLeaving()
        #expect(machine.state == .jumpingDown)
        machine.beginReturning()
        #expect(machine.state == .returning)
        machine.finish()
        #expect(machine.state == .idle)
        let beganNap = machine.perform(.nap)
        #expect(beganNap)
        machine.cancel()
        #expect(machine.state == .idle)
    }

    @Test("Every pet exposes three stable personality actions")
    func personality() {
        for pet in PetID.allCases {
            #expect(PetPersonalityBehavior.actions(for: pet).count == 3)
            #expect(PetPersonalityBehavior.action(for: pet, stableSeed: 5) == PetPersonalityBehavior.action(for: pet, stableSeed: 5))
        }
    }
}
