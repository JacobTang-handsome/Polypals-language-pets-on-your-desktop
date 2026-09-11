import AppKit
import ApplicationServices
import Foundation

struct PointerMotionFilter: Sendable {
    let deadZone: CGFloat
    let minimumInterval: TimeInterval
    private(set) var lastPoint: CGPoint
    private(set) var lastUpdate: Date

    init(deadZone: CGFloat = 3, minimumInterval: TimeInterval = 0.08, point: CGPoint = .zero, date: Date = .distantPast) {
        self.deadZone = deadZone
        self.minimumInterval = minimumInterval
        lastPoint = point
        lastUpdate = date
    }

    mutating func reset(point: CGPoint, at date: Date = .distantPast) {
        lastPoint = point
        lastUpdate = date
    }

    mutating func accepts(point: CGPoint, at date: Date) -> Bool {
        guard hypot(point.x - lastPoint.x, point.y - lastPoint.y) > deadZone,
              date.timeIntervalSince(lastUpdate) >= minimumInterval else { return false }
        lastPoint = point
        lastUpdate = date
        return true
    }
}

enum SystemActivityGate {
    static let quietInterval: TimeInterval = 2.5

    static var hasQuietKeyboardAndPointer: Bool {
        let source = CGEventSourceStateID.combinedSessionState
        let keyboard = CGEventSource.secondsSinceLastEventType(source, eventType: .keyDown)
        let dragging = min(
            CGEventSource.secondsSinceLastEventType(source, eventType: .leftMouseDragged),
            CGEventSource.secondsSinceLastEventType(source, eventType: .rightMouseDragged)
        )
        return isQuiet(keyboardIdle: keyboard, draggingIdle: dragging)
    }

    static func isQuiet(keyboardIdle: TimeInterval, draggingIdle: TimeInterval) -> Bool {
        keyboardIdle >= quietInterval && draggingIdle >= quietInterval
    }
}

enum IdleAnimationCadence {
    static func waits(for petID: PetID) -> [TimeInterval] {
        switch petID {
        case .sol: [6.5, 10.5, 8]
        case .mousse: [10, 15, 12]
        case .ash: [13, 19, 16]
        }
    }
}

enum PetWindowMotion {
    static func origin(from start: CGPoint, to end: CGPoint, progress: Double) -> CGPoint {
        let clamped = min(1, max(0, progress))
        let eased = clamped * clamped * (3 - 2 * clamped)
        return CGPoint(
            x: start.x + (end.x - start.x) * eased,
            y: start.y + (end.y - start.y) * eased
        )
    }
}

enum PetPositionPersistencePolicy {
    static func shouldPersist(hasTemporaryPerch: Bool) -> Bool { !hasTemporaryPerch }
}

enum PetBehaviorState: Equatable, Sendable {
    case idle
    case choosingDestination
    case walkingToPerch(PerchTarget)
    case jumpingOntoPerch(PerchTarget)
    case perched(PerchTarget, PerchActivity)
    case jumpingDown
    case returning
    case performing(PetBehaviorAnimation)
}

enum PerchActivity: Equatable, Sendable {
    case sitting
    case edgeWalkingLeft
    case edgeWalkingRight
    case napping
    case lookingAtPointer
    case personality(PetBehaviorAnimation)
}

struct PerchWindow: Equatable, Sendable {
    let windowNumber: Int
    let ownerPID: pid_t
    let ownerName: String
    let frame: CGRect
    let layer: Int
    let isOnScreen: Bool
}

struct PerchTarget: Equatable, Sendable {
    enum Kind: String, Sendable { case applicationWindow, screenEdge }
    let kind: Kind
    let windowNumber: Int?
    let ownerPID: pid_t?
    let screenID: String
    let windowFrame: CGRect
    let anchor: CGPoint
    let safeHorizontalRange: ClosedRange<CGFloat>
}

struct PerchSelectionContext: Sendable {
    let petID: PetID
    let petSize: CGSize
    let petFrame: CGRect
    let screenFrame: CGRect
    let screenID: String
    let ownPID: pid_t
    let frontmostPID: pid_t?
    let reservedRanges: [ClosedRange<CGFloat>]
}

protocol WindowEdgeProviding {
    var hasAccessibilityPermission: Bool { get }
    func visibleWindows() -> [PerchWindow]
}

struct SystemWindowEdgeProvider: WindowEdgeProviding {
    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func visibleWindows() -> [PerchWindow] {
        // CGWindowList exposes public on-screen window geometry without AX trust.
        // Requiring AX here made every ad-hoc rebuild silently fall back to the
        // desktop edge even though usable window bounds were available.
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[CFString: Any]] else { return [] }
        return raw.compactMap { item in
            guard let number = item[kCGWindowNumber] as? Int,
                  let pid = item[kCGWindowOwnerPID] as? pid_t,
                  let bounds = item[kCGWindowBounds] as? [CFString: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return PerchWindow(
                windowNumber: number,
                ownerPID: pid,
                ownerName: item[kCGWindowOwnerName] as? String ?? "",
                frame: frame,
                layer: item[kCGWindowLayer] as? Int ?? 0,
                isOnScreen: item[kCGWindowIsOnscreen] as? Bool ?? true
            )
        }
    }
}

enum PerchCoordinateConverter {
    /// Quartz/Accessibility use a top-left desktop origin; AppKit uses a bottom-left origin.
    static func appKitFrame(fromQuartz frame: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: desktopTop - frame.maxY, width: frame.width, height: frame.height)
    }
}

struct PerchTargetSelector {
    let minimumWindowSize = CGSize(width: 360, height: 220)
    let controlButtonReserve: CGFloat = 112
    let edgePadding: CGFloat = 28

    func select(windows: [PerchWindow], context: PerchSelectionContext, desktopTop: CGFloat) -> PerchTarget? {
        let candidates = windows.compactMap { window -> (PerchTarget, Double)? in
            guard window.ownerPID != context.ownPID, window.layer == 0, window.isOnScreen,
                  window.frame.width >= minimumWindowSize.width,
                  window.frame.height >= minimumWindowSize.height else { return nil }
            let frame = PerchCoordinateConverter.appKitFrame(fromQuartz: window.frame, desktopTop: desktopTop)
            guard frame.intersects(context.screenFrame), !isFullscreen(frame, screen: context.screenFrame) else { return nil }
            let lower = max(frame.minX + controlButtonReserve, context.screenFrame.minX + edgePadding)
            let upper = min(frame.maxX - edgePadding - context.petSize.width, context.screenFrame.maxX - edgePadding - context.petSize.width)
            guard upper > lower else { return nil }
            let preferred = min(upper, max(lower, frame.midX + frame.width * 0.12 - context.petSize.width / 2))
            let occupied = context.reservedRanges.contains { $0.overlaps((preferred...(preferred + context.petSize.width))) }
            guard !occupied else { return nil }
            let target = PerchTarget(
                kind: .applicationWindow,
                windowNumber: window.windowNumber,
                ownerPID: window.ownerPID,
                screenID: context.screenID,
                windowFrame: frame,
                anchor: CGPoint(x: preferred, y: frame.maxY - context.petSize.height * 0.15),
                safeHorizontalRange: lower...upper
            )
            let frontmostBonus = window.ownerPID == context.frontmostPID ? 10_000.0 : 0
            let distance = hypot(preferred - context.petFrame.minX, frame.maxY - context.petFrame.minY)
            return (target, frontmostBonus - distance)
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    func screenEdgeFallback(context: PerchSelectionContext) -> PerchTarget {
        let lower = context.screenFrame.minX + edgePadding
        let upper = max(lower, context.screenFrame.maxX - edgePadding - context.petSize.width)
        let x = min(upper, max(lower, context.petFrame.minX))
        return PerchTarget(
            kind: .screenEdge,
            windowNumber: nil,
            ownerPID: nil,
            screenID: context.screenID,
            windowFrame: context.screenFrame,
            anchor: CGPoint(x: x, y: context.screenFrame.minY),
            safeHorizontalRange: lower...upper
        )
    }

    private func isFullscreen(_ frame: CGRect, screen: CGRect) -> Bool {
        abs(frame.width - screen.width) < 8 && abs(frame.height - screen.height) < 30
    }
}

enum PerchFollowResolver {
    static func origin(
        for target: PerchTarget,
        updatedQuartzFrame: CGRect,
        desktopTop: CGFloat,
        screenFrame: CGRect,
        petSize: CGSize,
        minimumWindowSize: CGSize = CGSize(width: 360, height: 220),
        controlButtonReserve: CGFloat = 112,
        edgePadding: CGFloat = 28
    ) -> CGPoint? {
        let frame = PerchCoordinateConverter.appKitFrame(fromQuartz: updatedQuartzFrame, desktopTop: desktopTop)
        let fullscreen = abs(frame.width - screenFrame.width) < 8 && abs(frame.height - screenFrame.height) < 30
        guard frame.width >= minimumWindowSize.width, frame.height >= minimumWindowSize.height,
              frame.intersects(screenFrame), !fullscreen else { return nil }
        let relativeX = target.anchor.x - target.windowFrame.minX
        let lower = max(frame.minX + controlButtonReserve, screenFrame.minX + edgePadding)
        let upper = min(frame.maxX - edgePadding - petSize.width, screenFrame.maxX - edgePadding - petSize.width)
        guard upper > lower else { return nil }
        return CGPoint(
            x: min(upper, max(lower, frame.minX + relativeX)),
            y: frame.maxY - petSize.height * 0.15
        )
    }
}

struct PetPersonalityBehavior {
    static func actions(for petID: PetID) -> [PetBehaviorAnimation] {
        switch petID {
        case .sol: [.solTailChase, .solPouncePrep, .solEarTwitch]
        case .mousse: [.mousseGroom, .mousseElegantSit, .mousseProud]
        case .ash: [.ashHeadTilt, .ashSlowSquint, .ashInviteWing]
        }
    }

    static func action(for petID: PetID, stableSeed: Int) -> PetBehaviorAnimation {
        let values: [PetBehaviorAnimation] = switch petID {
        // Ear twitch is reserved for app-known cues (for example an invitation),
        // never inferred from microphone input or selected as a random ambient action.
        case .sol: [.solTailChase, .solPouncePrep]
        case .mousse: actions(for: petID)
        case .ash: actions(for: petID)
        }
        return values[abs(stableSeed) % values.count]
    }

    static func focusAction(for petID: PetID, stableSeed: Int) -> PetBehaviorAnimation {
        switch petID {
        case .sol: .solPouncePrep
        case .mousse: stableSeed.isMultiple(of: 2) ? .mousseGroom : .mousseElegantSit
        case .ash: stableSeed.isMultiple(of: 2) ? .ashSlowSquint : .ashHeadTilt
        }
    }

    static func perchIdle(for petID: PetID, stableSeed: Int) -> PetBehaviorAnimation {
        switch petID {
        case .sol:
            switch abs(stableSeed) % 4 {
            case 0: .perchWalkLeft
            case 1: .perchWalkRight
            default: .solPerchTailWag
            }
        case .mousse:
            switch abs(stableSeed) % 5 {
            case 0: .nap
            case 1: .mousseGroom
            default: .mousseElegantSit
            }
        case .ash:
            switch abs(stableSeed) % 5 {
            case 0: .nap
            case 1: .ashHeadTilt
            default: .ashSlowSquint
            }
        }
    }
}

struct PetBehaviorStateMachine: Sendable {
    private(set) var state: PetBehaviorState = .idle

    mutating func beginChoosing() -> Bool {
        guard state == .idle else { return false }
        state = .choosingDestination
        return true
    }

    mutating func walk(to target: PerchTarget) {
        guard state == .choosingDestination else { return }
        state = .walkingToPerch(target)
    }

    mutating func reachedPerch() {
        guard case let .walkingToPerch(target) = state else { return }
        state = .jumpingOntoPerch(target)
    }

    mutating func landed() {
        guard case let .jumpingOntoPerch(target) = state else { return }
        state = .perched(target, .sitting)
    }

    mutating func setPerchActivity(_ activity: PerchActivity) {
        guard case let .perched(target, _) = state else { return }
        state = .perched(target, activity)
    }

    mutating func perform(_ animation: PetBehaviorAnimation) -> Bool {
        guard state == .idle else { return false }
        state = .performing(animation)
        return true
    }

    mutating func beginLeaving() {
        if case .perched = state { state = .jumpingDown }
    }

    mutating func beginReturning() { state = .returning }
    mutating func finish() { state = .idle }
    mutating func cancel() { state = .idle }
}

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
