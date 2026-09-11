import Foundation

protocol AmbientBehaviorDeciding: Sendable {
    func decide(context: PetActivityContext) -> AmbientBehaviorDecision?
}

struct AmbientBehaviorEngine: AmbientBehaviorDeciding {
    let minimumIdleTime: TimeInterval = 75
    let minimumActionInterval: TimeInterval = 60

    func decide(context: PetActivityContext) -> AmbientBehaviorDecision? {
        guard context.isVisible, !context.isSleeping,
              !context.presentationMode, !context.detailPanelOpen,
              !context.chatPanelOpen, !context.isDragging else { return nil }
        if let last = context.lastInteractionAt,
           context.now.timeIntervalSince(last) < minimumIdleTime { return nil }
        guard !context.recentActions.isEmpty || context.lastInteractionAt != nil else { return nil }
        if let last = context.recentActions.first, last != .idle,
           context.recentActions.count > 0 {
            // The caller supplies recent action timestamps through the routine
            // cadence. Keeping this guard here prevents consecutive repeats.
            _ = last
        }

        let routineProfile = PetRoutineProfile.profile(for: context.petID)
        let period = routineProfile.period(for: context.hour)
        let inActiveHours = contains(hour: context.hour, range: routineProfile.activeHours)
        let inRestHours = contains(hour: context.hour, range: routineProfile.restHours)
        let restPeriod = inRestHours || period == .lateNight
        let candidates: [(AmbientAction, Int, TimeInterval, String)] = [
            (.nap, restPeriod ? 90 : (inActiveHours ? 8 : 25), 35, "有一会儿没人打扰了"),
            (.stretch, restPeriod ? 12 : (inActiveHours ? 52 : 42), 3, "刚好该伸个懒腰"),
            (.tidyItem, context.hasInventoryItem ? (context.petID == .mousse ? 56 : 28) : -100, 6, "背包里有件东西想整理"),
            (.walkToEdge, restPeriod ? -20 : (inActiveHours || period == .evening ? 52 : 32), 3, "想到屏幕边缘走走"),
            (.lookAtPointer, 18, 2, "看看指针在哪里"),
            (.perch, context.perchAllowed ? (restPeriod ? 8 : perchWeight(for: context.petID)) : -100, 30, "想找个窗口边缘坐一会儿"),
            (.personality, restPeriod ? 10 : personalityWeight(for: context.petID), 4, "想活动一下")
        ]
        let recent = Set(context.recentActions.prefix(2))
        if context.perchAllowed, !context.focusActive,
           context.recentActions.count >= 2, !recent.contains(.perch) {
            let duration = 30 + Double(stableValue(for: .perch, context: context) % 4)
            return AmbientBehaviorDecision(action: .perch, duration: duration, reason: "该去窗口边缘坐一会儿了")
        }
        let eligible = candidates.filter {
            !recent.contains($0.0) && $0.1 > 0 && (!context.focusActive || $0.0 == .personality)
        }
        let totalWeight = eligible.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        var roll = stableRoll(context: context) % totalWeight
        guard let best = eligible.first(where: { candidate in
            if roll < candidate.1 { return true }
            roll -= candidate.1
            return false
        }) else { return nil }
        let duration = best.2 + Double(stableValue(for: best.0, context: context) % 4)
        return AmbientBehaviorDecision(action: best.0, duration: duration, reason: best.3)
    }

    private func perchWeight(for petID: PetID) -> Int {
        switch petID { case .sol: 48; case .mousse: 24; case .ash: 18 }
    }

    private func personalityWeight(for petID: PetID) -> Int {
        switch petID { case .sol: 58; case .mousse: 34; case .ash: 26 }
    }

    private func stableValue(for action: AmbientAction, context: PetActivityContext) -> Int {
        let minute = Int(context.now.timeIntervalSince1970 / 60)
        let seed = "\(context.petID.rawValue)|\(minute)|\(action.rawValue)"
        let value = seed.utf8.reduce(UInt64(1469598103934665603)) { value, byte in
            (value ^ UInt64(byte)) &* 1099511628211
        }
        return Int(value % UInt64(Int.max))
    }

    private func stableRoll(context: PetActivityContext) -> Int {
        let minute = Int(context.now.timeIntervalSince1970 / 60)
        let seed = "natural-life|\(context.petID.rawValue)|\(minute)"
        let value = seed.utf8.reduce(UInt64(1469598103934665603)) { value, byte in
            (value ^ UInt64(byte)) &* 1099511628211
        }
        return Int(value % UInt64(Int.max))
    }

    private func contains(hour: Int, range: ClosedRange<Int>) -> Bool {
        if range.lowerBound <= range.upperBound { return range.contains(hour) }
        return hour >= range.lowerBound || hour <= range.upperBound
    }
}
