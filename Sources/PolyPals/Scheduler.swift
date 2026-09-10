import Foundation

enum InvitationPriority: Int, Comparable, Sendable {
    case occasional = 10
    case ordinarySchedule = 20
    case focusCompletion = 30
    case courseSchedule = 40

    static func < (lhs: InvitationPriority, rhs: InvitationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct InvitationCandidate: Identifiable, Sendable, Equatable {
    let id: UUID
    let petID: PetID
    let priority: InvitationPriority
    let createdAt: Date
    let expiresAt: Date
    let title: String
    let body: String
    let sourceScheduleID: UUID?

    init(
        id: UUID = UUID(),
        petID: PetID,
        priority: InvitationPriority,
        createdAt: Date,
        expiresAt: Date,
        title: String,
        body: String,
        sourceScheduleID: UUID? = nil
    ) {
        self.id = id
        self.petID = petID
        self.priority = priority
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.title = title
        self.body = body
        self.sourceScheduleID = sourceScheduleID
    }
}

struct SchedulerSnapshot: Sendable {
    var now: Date
    var calendar: Calendar
    var presentationMode: Bool
    var isFullScreenSpace: Bool
    var focusSessionActive: Bool
    var quietStartHour: Int
    var quietEndHour: Int
    var quietUntil: Date?
    var todayOnlyPet: PetID?
    var lastGlobalInvitationAt: Date?
    var globalInvitationCountToday: Int
    var petInvitationCountToday: [PetID: Int]
    var rejectedPetsToday: Set<PetID>
    var consecutiveDeclines: Int

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        presentationMode = false
        isFullScreenSpace = false
        focusSessionActive = false
        quietStartHour = 22
        quietEndHour = 9
        quietUntil = nil
        todayOnlyPet = nil
        lastGlobalInvitationAt = nil
        globalInvitationCountToday = 0
        petInvitationCountToday = [:]
        rejectedPetsToday = []
        consecutiveDeclines = 0
    }
}

struct SchedulerLimits: Sendable, Equatable {
    var globalDailyLimit: Int = 2
    var perPetDailyLimit: Int = 1
    var minimumInterval: TimeInterval = 90 * 60
}

enum SchedulerDecision: Sendable, Equatable {
    case deliver(InvitationCandidate)
    case suppress(reason: String)
}

struct GlobalScheduler: Sendable {
    var limits: SchedulerLimits

    init(limits: SchedulerLimits = .init()) { self.limits = limits }

    func decide(candidates: [InvitationCandidate], snapshot: SchedulerSnapshot) -> SchedulerDecision {
        if snapshot.presentationMode { return .suppress(reason: "演示模式") }
        if snapshot.isFullScreenSpace { return .suppress(reason: "全屏空间") }
        if snapshot.focusSessionActive { return .suppress(reason: "专注中") }
        if let quietUntil = snapshot.quietUntil, snapshot.now < quietUntil {
            return .suppress(reason: "安静模式")
        }
        if isQuietHour(snapshot.now, calendar: snapshot.calendar, start: snapshot.quietStartHour, end: snapshot.quietEndHour) {
            return .suppress(reason: "安静时间")
        }
        if let last = snapshot.lastGlobalInvitationAt,
           snapshot.now.timeIntervalSince(last) < limits.minimumInterval {
            return .suppress(reason: "全局冷却中")
        }

        let eligible = candidates.filter { candidate in
            guard candidate.createdAt <= snapshot.now, candidate.expiresAt >= snapshot.now else { return false }
            if let only = snapshot.todayOnlyPet, candidate.petID != only { return false }
            if snapshot.rejectedPetsToday.contains(candidate.petID) { return false }
            if candidate.priority == .occasional {
                guard snapshot.globalInvitationCountToday < limits.globalDailyLimit else { return false }
                guard snapshot.petInvitationCountToday[candidate.petID, default: 0] < limits.perPetDailyLimit else { return false }
            }
            return true
        }

        guard let winner = eligible.sorted(by: {
            if $0.priority == $1.priority { return $0.createdAt < $1.createdAt }
            return $0.priority > $1.priority
        }).first else {
            return .suppress(reason: "没有符合条件的邀请")
        }
        return .deliver(winner)
    }

    func snapshotAfterDecline(_ snapshot: SchedulerSnapshot, petID: PetID) -> SchedulerSnapshot {
        var updated = snapshot
        updated.rejectedPetsToday.insert(petID)
        updated.consecutiveDeclines += 1
        if updated.consecutiveDeclines >= 3 {
            var nextMorning = updated.calendar.date(byAdding: .day, value: 1, to: updated.now) ?? updated.now.addingTimeInterval(86_400)
            nextMorning = updated.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextMorning) ?? nextMorning
            updated.quietUntil = nextMorning
        }
        return updated
    }

    func snapshotAfterDelivery(_ snapshot: SchedulerSnapshot, petID: PetID) -> SchedulerSnapshot {
        var updated = snapshot
        updated.lastGlobalInvitationAt = snapshot.now
        updated.globalInvitationCountToday += 1
        updated.petInvitationCountToday[petID, default: 0] += 1
        return updated
    }

    func snapshotAfterAcceptance(_ snapshot: SchedulerSnapshot, petID: PetID) -> SchedulerSnapshot {
        var updated = snapshot
        updated.consecutiveDeclines = 0
        return updated
    }

    func isQuietHour(_ date: Date, calendar: Calendar, start: Int, end: Int) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }
}

enum ScheduleOccurrenceResolver {
    static func mostRecent(
        fireDate: Date,
        recurrence: String?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        if recurrence == "daily" {
            let time = calendar.dateComponents([.hour, .minute], from: fireDate)
            return calendar.nextDate(
                after: now,
                matching: time,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .backward
            )
        }
        if recurrence == "weekly" {
            let time = calendar.dateComponents([.weekday, .hour, .minute], from: fireDate)
            return calendar.nextDate(
                after: now,
                matching: time,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .backward
            )
        }
        return fireDate <= now ? fireDate : nil
    }
}

enum NotificationCollisionPolicy {
    static func collides(proposed: Date?, existing: [Date], tolerance: TimeInterval = 60) -> Bool {
        guard let proposed else { return false }
        return existing.contains { abs(proposed.timeIntervalSince($0)) < tolerance }
    }
}
