import Foundation

protocol AmbientBehaviorDeciding: Sendable {
    func decide(context: PetActivityContext) -> AmbientBehaviorDecision?
}

struct AmbientBehaviorEngine: AmbientBehaviorDeciding {
    let minimumIdleTime: TimeInterval = 15 * 60
    let minimumActionInterval: TimeInterval = 60

    func decide(context: PetActivityContext) -> AmbientBehaviorDecision? {
        guard context.isVisible, !context.isSleeping, !context.focusActive,
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
            (.perch, restPeriod ? 8 : perchWeight(for: context.petID), 30, "想找个窗口边缘坐一会儿"),
            (.personality, restPeriod ? 10 : personalityWeight(for: context.petID), 4, "想活动一下")
        ]
        let recent = Set(context.recentActions.prefix(2))
        let eligible = candidates.filter { !recent.contains($0.0) && $0.1 > 0 }
        guard let best = eligible.max(by: { lhs, rhs in
            if lhs.1 == rhs.1 { return stableValue(for: lhs.0, context: context) < stableValue(for: rhs.0, context: context) }
            return lhs.1 < rhs.1
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
        let seed = "\(context.petID.rawValue)|\(Calendar.current.component(.day, from: context.now))|\(Calendar.current.component(.hour, from: context.now))|\(action.rawValue)"
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
