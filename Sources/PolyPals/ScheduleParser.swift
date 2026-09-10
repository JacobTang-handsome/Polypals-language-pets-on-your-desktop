import Foundation

struct ParsedScheduleDraft: Sendable, Equatable {
    let petID: PetID?
    let trigger: ScheduleTrigger
    let fireDate: Date?
    let recurrence: String?
    let contentPreference: String
    let confidence: Double
    let clarification: String?
}

struct ScheduleParser: Sendable {
    func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedScheduleDraft {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pet: PetID? = normalized.contains("Sol") || normalized.contains("西语") || normalized.contains("西班牙") ? .sol
            : normalized.contains("Mousse") || normalized.contains("法语") || normalized.contains("法文") ? .mousse
            : normalized.contains("Ash") || normalized.contains("英语") || normalized.contains("英文") ? .ash : nil
        if normalized.contains("专注") || normalized.contains("番茄") {
            return .init(petID: pet, trigger: .focusCompletion, fireDate: nil, recurrence: nil, contentPreference: normalized, confidence: pet == nil ? 0.68 : 0.92, clarification: pet == nil ? "请指定由哪只宠物出现。" : nil)
        }
        let recurrence = normalized.contains("每天") || normalized.contains("每日") ? "daily"
            : normalized.contains("每周") || normalized.contains("每星期") ? "weekly" : nil
        let weekday = weekday(in: normalized)
        let hourMinute = time(in: normalized) ?? (normalized.contains("课前") ? (9, 0) : nil)
        guard let hourMinute else {
            return .init(petID: pet, trigger: .calendar, fireDate: now.addingTimeInterval(3600), recurrence: recurrence, contentPreference: normalized, confidence: 0.45, clarification: "请补充具体时间，例如下午三点。")
        }
        let date: Date?
        if recurrence == "weekly", let weekday {
            date = calendar.nextDate(
                after: now,
                matching: DateComponents(hour: hourMinute.hour, minute: hourMinute.minute, weekday: weekday),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        } else if normalized.contains("明天") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            date = tomorrow.flatMap { calendar.date(bySettingHour: hourMinute.hour, minute: hourMinute.minute, second: 0, of: $0) }
        } else {
            let today = calendar.date(bySettingHour: hourMinute.hour, minute: hourMinute.minute, second: 0, of: now)
            if recurrence == "daily" || (today.map { $0 <= now } ?? false) {
                date = calendar.nextDate(
                    after: now,
                    matching: DateComponents(hour: hourMinute.hour, minute: hourMinute.minute),
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                )
            } else {
                date = today
            }
        }
        let inferredCourseTime = time(in: normalized) == nil && normalized.contains("课前")
        let confidence = (pet == nil ? 0.72 : 0.92) * (recurrence == nil ? 0.8 : 1) * (inferredCourseTime ? 0.86 : 1)
        let clarification: String?
        if pet == nil { clarification = "请指定宠物，或确认使用最近互动的宠物。" }
        else if inferredCourseTime { clarification = "已按上午9:00安排课前提醒；如果课程时间不同，请在下方调整。" }
        else { clarification = nil }
        return .init(petID: pet, trigger: .calendar, fireDate: date, recurrence: recurrence, contentPreference: normalized, confidence: confidence, clarification: clarification)
    }

    private func weekday(in text: String) -> Int? {
        let symbols = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
        guard let range = text.range(of: "周") ?? text.range(of: "星期") else { return nil }
        let tail = text[range.upperBound...]
        return tail.first.flatMap { symbols[String($0)] }
    }

    private func time(in text: String) -> (hour: Int, minute: Int)? {
        guard let marker = text.firstIndex(where: { $0 == "点" || $0 == "时" }) else { return nil }
        let before = text[..<marker]
        var digitStart = before.endIndex
        while digitStart > before.startIndex {
            let previous = before.index(before: digitStart)
            guard before[previous].isNumber || "零一二三四五六七八九十".contains(before[previous]) else { break }
            digitStart = previous
        }
        guard digitStart < before.endIndex else { return nil }
        let hourToken = String(before[digitStart...])
        guard var hour = Int(hourToken) ?? chineseNumber(hourToken) else { return nil }
        let after = text[text.index(after: marker)...]
        var minute = 0
        var minuteDigits = ""
        for character in after {
            guard character.isNumber else { break }
            minuteDigits.append(character)
        }
        if !minuteDigits.isEmpty { minute = Int(minuteDigits) ?? 0 }
        let period = before.contains("下午") ? "下午" : before.contains("晚上") ? "晚上" : before.contains("夜里") ? "夜里" : before.contains("上午") ? "上午" : before.contains("早上") ? "早上" : nil
        if (period == "下午" || period == "晚上" || period == "夜里") && hour < 12 { hour += 12 }
        return (min(23, max(0, hour)), min(59, max(0, minute)))
    }

    private func chineseNumber(_ value: String) -> Int? {
        let digits = ["零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if value == "十" { return 10 }
        if value.count == 2, value.first == "十", let last = value.last, let ones = digits[String(last)] { return 10 + ones }
        if value.count == 2, let first = value.first, let last = value.last, first != "十", let tens = digits[String(first)], last == "十" { return tens * 10 }
        if value.count == 1 { return digits[value] }
        return nil
    }
}
