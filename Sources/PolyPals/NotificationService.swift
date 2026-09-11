import AppKit
import Foundation
// Xcode 16.4's SDK does not yet expose the Sendable annotations present in newer SDKs.
@preconcurrency import UserNotifications

enum NotificationScheduleResult: Sendable, Equatable {
    case scheduled
    case runtimeFallback
    case suppressedConflict
    case permissionDenied
    case failed

    var usesSystemNotification: Bool { self == .scheduled }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private static let categoryIdentifier = "polypals.plan"
    private static let snoozeAction = "polypals.snooze-hour"
    private static let skipAction = "polypals.skip-today"
    private static let cancelAction = "polypals.cancel-plan"
    private let center = UNUserNotificationCenter.current()
    private var suspendedRequests: [UNNotificationRequest] = []
    var onOpenPet: ((PetID) -> Void)?
    var onCancelSchedule: ((PetID, UUID) -> Void)?
    var onScheduleAction: ((PetID, UUID, ScheduleExecutionOutcome) -> Void)?

    override private init() {
        super.init()
        center.delegate = self
        configureCategories()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .badge])
        @unknown default: return false
        }
    }

    @discardableResult
    func schedule(_ schedule: ScheduleEntity, pet: PetDefinition) async throws -> NotificationScheduleResult {
        guard schedule.triggerType == ScheduleTrigger.calendar.rawValue,
              let fireDate = schedule.fireDate else { return .runtimeFallback }
        guard try await requestAuthorizationIfNeeded() else { return .permissionDenied }

        let content = UNMutableNotificationContent()
        content.title = "\(pet.name) 带来了一点东西"
        content.body = schedule.contentPreference
        content.sound = nil
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["petID": pet.id.rawValue, "scheduleID": schedule.id.uuidString]

        let trigger: UNNotificationTrigger
        if schedule.recurrence == "weekly" {
            let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else if schedule.recurrence == "daily" {
            let components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: identifier(petID: pet.id, scheduleID: schedule.id),
            content: content,
            trigger: trigger
        )
        let pending = await center.pendingNotificationRequests()
        let proposedDate = nextDate(for: trigger)
        let collides = NotificationCollisionPolicy.collides(
            proposed: proposedDate,
            existing: pending.compactMap { nextDate(for: $0.trigger) }
        )
        // A colliding notification is intentionally dropped, not converted into
        // a simultaneous pet action and not backfilled later.
        guard !collides else { return .suppressedConflict }
        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed
        }
    }

    func setPresentationMode(_ enabled: Bool) async {
        if enabled {
            guard suspendedRequests.isEmpty else { return }
            suspendedRequests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("polypals.") }
            center.removePendingNotificationRequests(withIdentifiers: suspendedRequests.map(\.identifier))
        } else {
            let requests = suspendedRequests
            suspendedRequests = []
            for request in requests { try? await center.add(request) }
        }
    }

    func cancel(petID: PetID, scheduleID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(petID: petID, scheduleID: scheduleID)])
    }

    func cancelAll(for petID: PetID) async {
        let requests = await center.pendingNotificationRequests()
        let prefix = "polypals.\(petID.rawValue)."
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let request = response.notification.request
        let actionIdentifier = response.actionIdentifier
        let requestIdentifier = request.identifier
        let title = request.content.title
        let body = request.content.body
        let raw = request.content.userInfo["petID"] as? String
        let scheduleRaw = request.content.userInfo["scheduleID"] as? String
        Task { @MainActor in
            if actionIdentifier == Self.snoozeAction {
                if let raw, let pet = PetID(rawValue: raw), let scheduleRaw, let scheduleID = UUID(uuidString: scheduleRaw) {
                    self.onScheduleAction?(pet, scheduleID, .snoozed)
                }
                await self.snooze(
                    originalIdentifier: requestIdentifier,
                    title: title,
                    body: body,
                    petRawValue: raw,
                    scheduleRawValue: scheduleRaw
                )
            } else if actionIdentifier == Self.cancelAction,
                      let raw, let pet = PetID(rawValue: raw),
                      let scheduleRaw, let scheduleID = UUID(uuidString: scheduleRaw) {
                self.onCancelSchedule?(pet, scheduleID)
            } else if actionIdentifier == Self.skipAction {
                if let raw, let pet = PetID(rawValue: raw), let scheduleRaw, let scheduleID = UUID(uuidString: scheduleRaw) {
                    self.onScheduleAction?(pet, scheduleID, .skipped)
                }
            } else if actionIdentifier != Self.skipAction,
                      let raw, let pet = PetID(rawValue: raw) {
                self.onOpenPet?(pet)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler(AppModel.shared.presentationMode ? [] : [.banner])
        }
    }

    private func identifier(petID: PetID, scheduleID: UUID) -> String {
        "polypals.\(petID.rawValue).\(scheduleID.uuidString)"
    }

    private func configureCategories() {
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "稍后一小时")
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "今天跳过")
        let cancel = UNNotificationAction(identifier: Self.cancelAction, title: "取消计划", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [snooze, skip, cancel],
                intentIdentifiers: []
            )
        ])
    }

    private func snooze(
        originalIdentifier: String,
        title: String,
        body: String,
        petRawValue: String?,
        scheduleRawValue: String?
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "petID": petRawValue ?? "",
            "scheduleID": scheduleRawValue ?? ""
        ]
        let snoozed = UNNotificationRequest(
            identifier: "\(originalIdentifier).snooze.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3_600, repeats: false)
        )
        try? await center.add(snoozed)
    }

    private func nextDate(for trigger: UNNotificationTrigger?) -> Date? {
        if let calendar = trigger as? UNCalendarNotificationTrigger { return calendar.nextTriggerDate() }
        if let interval = trigger as? UNTimeIntervalNotificationTrigger { return interval.nextTriggerDate() }
        return nil
    }
}
