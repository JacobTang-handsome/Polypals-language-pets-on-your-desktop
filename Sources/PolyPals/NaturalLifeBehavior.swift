import AppKit
import ApplicationServices
import Foundation

enum PetBehaviorState: Equatable, Sendable {
    case idle
    case choosingDestination
    case walkingToPerch(PerchTarget)
    case jumpingOntoPerch(PerchTarget)
    case perched(PerchTarget)
    case jumpingDown
    case returning
    case performing(PetBehaviorAnimation)
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
        guard hasAccessibilityPermission,
              let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
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

struct PetPersonalityBehavior {
    static func actions(for petID: PetID) -> [PetBehaviorAnimation] {
        switch petID {
        case .sol: [.solTailChase, .solPouncePrep, .solEarTwitch]
        case .mousse: [.mousseGroom, .mousseElegantSit, .mousseProud]
        case .ash: [.ashHeadTilt, .ashSlowSquint, .ashInviteWing]
        }
    }

    static func action(for petID: PetID, stableSeed: Int) -> PetBehaviorAnimation {
        let values = actions(for: petID)
        return values[abs(stableSeed) % values.count]
    }

    static func perchIdle(for petID: PetID, stableSeed: Int) -> PetBehaviorAnimation {
        switch petID {
        case .sol: stableSeed.isMultiple(of: 2) ? .solPerchTailWag : .perchWalkRight
        case .mousse: stableSeed.isMultiple(of: 3) ? .mousseGroom : .mousseElegantSit
        case .ash: stableSeed.isMultiple(of: 4) ? .ashHeadTilt : .perchSit
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
        state = .perched(target)
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
