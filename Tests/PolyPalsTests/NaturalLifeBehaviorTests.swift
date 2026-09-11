import CoreGraphics
import Foundation
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
            PerchWindow(windowNumber: 4, ownerPID: 1, ownerName: "Fullscreen", frame: CGRect(x: 0, y: 0, width: 1_440, height: 900), layer: 0, isOnScreen: true),
            PerchWindow(windowNumber: 5, ownerPID: 1, ownerName: "Minimized", frame: CGRect(x: 100, y: 100, width: 800, height: 600), layer: 0, isOnScreen: false)
        ]
        #expect(selector.select(windows: bad, context: context, desktopTop: 900) == nil)

        let reservedContext = PerchSelectionContext(
            petID: context.petID,
            petSize: context.petSize,
            petFrame: context.petFrame,
            screenFrame: context.screenFrame,
            screenID: context.screenID,
            ownPID: context.ownPID,
            frontmostPID: context.frontmostPID,
            reservedRanges: [context.screenFrame.minX...context.screenFrame.maxX]
        )
        let otherwiseSafe = PerchWindow(windowNumber: 6, ownerPID: 42, ownerName: "Reserved", frame: CGRect(x: 100, y: 100, width: 800, height: 500), layer: 0, isOnScreen: true)
        #expect(selector.select(windows: [otherwiseSafe], context: reservedContext, desktopTop: 900) == nil)
    }

    @Test("Selection stays on the pet's current display")
    func multipleDisplays() throws {
        let secondScreen = PerchSelectionContext(
            petID: .sol,
            petSize: context.petSize,
            petFrame: CGRect(x: 1_700, y: 40, width: 128, height: 138),
            screenFrame: CGRect(x: 1_440, y: 0, width: 1_200, height: 900),
            screenID: "second",
            ownPID: 99,
            frontmostPID: 42,
            reservedRanges: []
        )
        let windows = [
            PerchWindow(windowNumber: 1, ownerPID: 42, ownerName: "Other screen", frame: CGRect(x: 100, y: 100, width: 800, height: 500), layer: 0, isOnScreen: true),
            PerchWindow(windowNumber: 2, ownerPID: 42, ownerName: "Current screen", frame: CGRect(x: 1_550, y: 100, width: 800, height: 500), layer: 0, isOnScreen: true)
        ]
        let target = try #require(PerchTargetSelector().select(windows: windows, context: secondScreen, desktopTop: 900))
        #expect(target.windowNumber == 2)
        #expect(target.screenID == "second")
    }

    @Test("Moved and resized targets resolve smoothly while invalid targets leave")
    func followingTarget() throws {
        let window = PerchWindow(windowNumber: 2, ownerPID: 42, ownerName: "Front", frame: CGRect(x: 180, y: 80, width: 900, height: 620), layer: 0, isOnScreen: true)
        let target = try #require(PerchTargetSelector().select(windows: [window], context: context, desktopTop: 900))
        let moved = try #require(PerchFollowResolver.origin(
            for: target,
            updatedQuartzFrame: CGRect(x: 220, y: 100, width: 760, height: 560),
            desktopTop: 900,
            screenFrame: context.screenFrame,
            petSize: context.petSize
        ))
        #expect(moved.x >= 220 + 112)
        #expect(moved.x <= 220 + 760 - 28 - context.petSize.width)
        #expect(PerchFollowResolver.origin(
            for: target,
            updatedQuartzFrame: CGRect(x: 100, y: 100, width: 200, height: 100),
            desktopTop: 900,
            screenFrame: context.screenFrame,
            petSize: context.petSize
        ) == nil)
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
        #expect(machine.state == .perched(target, .sitting))
        machine.setPerchActivity(.napping)
        #expect(machine.state == .perched(target, .napping))
        machine.beginLeaving()
        #expect(machine.state == .jumpingDown)
        machine.beginReturning()
        #expect(machine.state == .returning)
        machine.finish()
        #expect(machine.state == .idle)
        let beganNap = machine.perform(.nap)
        #expect(beganNap)
        let overlappingStretch = machine.perform(.stretch)
        #expect(!overlappingStretch)
        machine.cancel()
        #expect(machine.state == .idle)
    }

    @Test("Every pet exposes three stable personality actions")
    func personality() {
        for pet in PetID.allCases {
            #expect(PetPersonalityBehavior.actions(for: pet).count == 3)
            #expect(PetPersonalityBehavior.action(for: pet, stableSeed: 5) == PetPersonalityBehavior.action(for: pet, stableSeed: 5))
        }
        #expect((0..<12).allSatisfy { PetPersonalityBehavior.action(for: .sol, stableSeed: $0) != .solEarTwitch })
    }

    @Test("Pointer following enforces dead zone and throttle")
    func pointerFiltering() {
        let start = Date(timeIntervalSince1970: 100)
        var filter = PointerMotionFilter(point: CGPoint(x: 20, y: 20), date: start)
        let insideDeadZone = filter.accepts(point: CGPoint(x: 22, y: 21), at: start.addingTimeInterval(1))
        let tooSoon = filter.accepts(point: CGPoint(x: 30, y: 20), at: start.addingTimeInterval(0.04))
        let accepted = filter.accepts(point: CGPoint(x: 30, y: 20), at: start.addingTimeInterval(0.09))
        let secondDeadZone = filter.accepts(point: CGPoint(x: 31, y: 20), at: start.addingTimeInterval(0.2))
        #expect(!insideDeadZone)
        #expect(!tooSoon)
        #expect(accepted)
        #expect(!secondDeadZone)
    }

    @Test("Recent typing or dragging suppresses natural behavior")
    func userActivityGate() {
        #expect(!SystemActivityGate.isQuiet(keyboardIdle: 2, draggingIdle: 20))
        #expect(!SystemActivityGate.isQuiet(keyboardIdle: 20, draggingIdle: 2))
        #expect(SystemActivityGate.isQuiet(keyboardIdle: 20, draggingIdle: 20))
    }

    @Test("Temporary perch positions never replace the saved home")
    func temporaryPositionPersistence() {
        #expect(PetPositionPersistencePolicy.shouldPersist(hasTemporaryPerch: false))
        #expect(!PetPositionPersistencePolicy.shouldPersist(hasTemporaryPerch: true))
    }

    @Test("Window movement interpolation reaches both endpoints")
    func movementInterpolation() {
        let start = CGPoint(x: 100, y: 200)
        let end = CGPoint(x: 500, y: 600)
        #expect(PetWindowMotion.origin(from: start, to: end, progress: 0) == start)
        #expect(PetWindowMotion.origin(from: start, to: end, progress: 1) == end)
        #expect(PetWindowMotion.origin(from: start, to: end, progress: 0.5) == CGPoint(x: 300, y: 400))
    }
}
