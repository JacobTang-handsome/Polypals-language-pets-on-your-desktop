import Foundation
import Testing
@testable import PolyPals

@Suite("Global scheduler")
struct SchedulerTests {
    private let scheduler = GlobalScheduler()

    @Test("Quiet hours cross midnight")
    func quietHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 23)))
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12)))
        #expect(scheduler.isQuietHour(late, calendar: calendar, start: 22, end: 9))
        #expect(!scheduler.isQuietHour(noon, calendar: calendar, start: 22, end: 9))
    }

    @Test("Higher priority wins")
    func priority() {
        let now = Date()
        let occasional = InvitationCandidate(petID: .sol, priority: .occasional, createdAt: now, expiresAt: now.addingTimeInterval(600), title: "a", body: "a")
        let course = InvitationCandidate(petID: .mousse, priority: .courseSchedule, createdAt: now, expiresAt: now.addingTimeInterval(600), title: "b", body: "b")
        var snapshot = SchedulerSnapshot(now: now)
        snapshot.quietStartHour = 0
        snapshot.quietEndHour = 0
        #expect(scheduler.decide(candidates: [occasional, course], snapshot: snapshot) == .deliver(course))
    }

    @Test("Presentation mode suppresses everything")
    func presentation() {
        let now = Date()
        let candidate = InvitationCandidate(petID: .ash, priority: .courseSchedule, createdAt: now, expiresAt: now.addingTimeInterval(600), title: "x", body: "x")
        var snapshot = SchedulerSnapshot(now: now)
        snapshot.presentationMode = true
        #expect(scheduler.decide(candidates: [candidate], snapshot: snapshot) == .suppress(reason: "演示模式"))
    }

    @Test("Three declines create quiet-until")
    func declines() {
        var snapshot = SchedulerSnapshot(now: Date())
        snapshot = scheduler.snapshotAfterDecline(snapshot, petID: .sol)
        snapshot = scheduler.snapshotAfterDecline(snapshot, petID: .mousse)
        snapshot = scheduler.snapshotAfterDecline(snapshot, petID: .ash)
        #expect(snapshot.consecutiveDeclines == 3)
        #expect(snapshot.quietUntil != nil)
    }
}

@Suite("Calendar schedule policy")
struct CalendarScheduleTests {
    @Test("Daily occurrence follows the supplied time zone across DST")
    func dailyAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let fireDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 30)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 10, minute: 0)))
        let occurrence = try #require(ScheduleOccurrenceResolver.mostRecent(
            fireDate: fireDate, recurrence: "daily", now: now, calendar: calendar
        ))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: occurrence)
        #expect(components.day == 9)
        #expect(components.hour == 9)
        #expect(components.minute == 30)
    }

    @Test("Weekly occurrence preserves weekday")
    func weeklyOccurrence() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let fireDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 14, minute: 0)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 18, minute: 0)))
        let occurrence = try #require(ScheduleOccurrenceResolver.mostRecent(
            fireDate: fireDate, recurrence: "weekly", now: now, calendar: calendar
        ))
        #expect(calendar.component(.weekday, from: occurrence) == calendar.component(.weekday, from: fireDate))
        #expect(calendar.component(.hour, from: occurrence) == 14)
    }

    @Test("Notifications inside one minute collide")
    func notificationCollision() {
        let proposed = Date(timeIntervalSince1970: 10_000)
        #expect(NotificationCollisionPolicy.collides(proposed: proposed, existing: [proposed.addingTimeInterval(59)]))
        #expect(!NotificationCollisionPolicy.collides(proposed: proposed, existing: [proposed.addingTimeInterval(60)]))
    }
}

@Suite("Natural language schedules")
struct ScheduleParserTests {
    @Test("Parses weekday, afternoon time, and pet")
    func chineseSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10))!
        let draft = ScheduleParser().parse("每周三下午六点让 Mousse 带来复习", now: now, calendar: calendar)
        #expect(draft.petID == .mousse)
        #expect(draft.recurrence == "weekly")
        #expect(draft.confidence >= 0.75)
        #expect(calendar.component(.hour, from: try #require(draft.fireDate)) == 18)
        #expect(calendar.component(.weekday, from: try #require(draft.fireDate)) == 4)
    }

    @Test("Parses focus completion without a calendar time")
    func focusSchedule() {
        let draft = ScheduleParser().parse("专注50分钟后让 Ash 邀请我休息")
        #expect(draft.trigger == .focusCompletion)
        #expect(draft.petID == .ash)
        #expect(draft.fireDate == nil)
    }

    @Test("每周计划正确选择未来的不同星期")
    func futureDifferentWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10))) // Wednesday
        let draft = ScheduleParser().parse("每周一上午九点让 Sol 带来故事", now: now, calendar: calendar)
        let fireDate = try #require(draft.fireDate)
        #expect(calendar.component(.weekday, from: fireDate) == 2)
        #expect(fireDate > now)
        #expect(calendar.component(.hour, from: fireDate) == 9)
    }

    @Test("明天计划保持为单次")
    func tomorrowIsOneShot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 18)))
        let draft = ScheduleParser().parse("明天上午九点让 Ash 提醒我", now: now, calendar: calendar)
        #expect(draft.recurrence == nil)
        #expect(calendar.component(.day, from: try #require(draft.fireDate)) == 10)
    }
}
