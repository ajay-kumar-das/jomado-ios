import Foundation
import UserNotifications
import JomadoCore

enum CompanionNotificationAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied

    var title: String {
        switch self {
        case .notDetermined: return "Not requested"
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        }
    }

    var systemImage: String {
        switch self {
        case .notDetermined: return "questionmark.circle"
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        }
    }
}

struct CompanionNotificationDiagnostics: Equatable, Sendable {
    var authorization: CompanionNotificationAuthorizationStatus = .notDetermined
    var scheduledCount = 0
    var lastReconciledAt: Date?
    var detail = "Companion reminder status has not been checked yet."

    var needsAttention: Bool { authorization != .authorized }
}

struct CompanionNotificationPlan: Sendable {
    let identifier: String
    let routineID: UUID
    let scheduledAt: Date
    let taskType: TaskType
    let title: String
    let body: String
    let contentID: String
    let mascot: MascotID
    let weekdays: [Int]
}

@MainActor
final class CompanionNotificationScheduler {
    static let categoryIdentifier = "JOMADO_COMPANION_TASK"
    static let openActionIdentifier = "JOMADO_OPEN_TASK"
    static let laterActionIdentifier = "JOMADO_REMIND_LATER"
    static let completeActionIdentifier = "JOMADO_COMPLETE_TASK"
    static let identifierPrefix = "jomado.companion."
    static let followUpIdentifierPrefix = "jomado.companion.followup."
    static let maximumScheduledRequests = 56

    private let center = UNUserNotificationCenter.current()

    func registerCategories() {
        let complete = UNNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "I drank water",
            options: []
        )
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "Open Jomado",
            options: [.foreground]
        )
        let later = UNNotificationAction(
            identifier: Self.laterActionIdentifier,
            title: "Remind me in 10 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [complete, later, open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> CompanionNotificationAuthorizationStatus {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorization() async throws -> CompanionNotificationAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorizationStatus()
    }

    func reconcile(plans: [CompanionNotificationPlan]) async throws -> CompanionNotificationDiagnostics {
        registerCategories()
        let authorization = await authorizationStatus()
        let pending = await pendingRequests()
        // Reconciliation owns only the generated routine schedule. A user-requested
        // "Remind me in 10 min" follow-up is a separate pending commitment and must
        // survive app launch/foreground reconciliation. Removing every Jomado-prefixed
        // request here used to cancel those follow-ups as soon as the app reopened.
        let followUpRequests = pending.filter { $0.identifier.hasPrefix(Self.followUpIdentifierPrefix) }
        let generatedScheduleRequests = pending
            .map(\.identifier)
            .filter { identifier in
                identifier.hasPrefix(Self.identifierPrefix) &&
                    !identifier.hasPrefix(Self.followUpIdentifierPrefix)
            }
        center.removePendingNotificationRequests(withIdentifiers: generatedScheduleRequests)

        // Leave headroom for explicit user-requested follow-ups. iOS has a finite pending
        // notification budget; generated routine reminders must never crowd out a promise
        // the user explicitly made by tapping “Remind me in 10 min”.
        let generatedRequestBudget = max(0, Self.maximumScheduledRequests - followUpRequests.count)

        guard authorization == .authorized else {
            return CompanionNotificationDiagnostics(
                authorization: authorization,
                scheduledCount: 0,
                lastReconciledAt: Date(),
                detail: authorization == .denied
                    ? "Notification access is denied. Companion reminders cannot appear on the Lock Screen until access is allowed in Settings."
                    : "Notification access has not been requested yet."
            )
        }

        var scheduled = 0
        let sortedPlans = plans.sorted(by: { $0.scheduledAt < $1.scheduledAt })
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent

        // Decide recurrence at routine granularity. Partial recurring coverage is worse than
        // a finite rolling horizon because it silently makes only some configured times
        // reliable. A routine therefore becomes calendar-recurring only when *all* of its
        // weekday/time combinations fit in the remaining iOS notification budget.
        let grouped = Dictionary(grouping: sortedPlans, by: \.routineID)
        var recurringRoutineIDs = Set<UUID>()
        var reservedRecurringSlots = 0
        for (routineID, routinePlans) in grouped.sorted(by: {
            ($0.value.first?.scheduledAt ?? .distantFuture) < ($1.value.first?.scheduledAt ?? .distantFuture)
        }) {
            guard let sample = routinePlans.first else { continue }
            let weekdays = Set(sample.weekdays)
            let timeKeys = Set(routinePlans.map {
                "\(calendar.component(.hour, from: $0.scheduledAt)):\(calendar.component(.minute, from: $0.scheduledAt))"
            })
            let requiredSlots = weekdays == Set(1...7)
                ? timeKeys.count
                : timeKeys.count * weekdays.count
            guard requiredSlots > 0,
                  reservedRecurringSlots + requiredSlots <= generatedRequestBudget else { continue }
            recurringRoutineIDs.insert(routineID)
            reservedRecurringSlots += requiredSlots
        }

        var emittedRecurringKeys = Set<String>()
        for plan in sortedPlans {
            guard scheduled < generatedRequestBudget else { break }
            let hour = calendar.component(.hour, from: plan.scheduledAt)
            let minute = calendar.component(.minute, from: plan.scheduledAt)
            let isRecurringRoutine = recurringRoutineIDs.contains(plan.routineID)
            let isEveryDay = Set(plan.weekdays) == Set(1...7)

            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.threadIdentifier = "jomado.\(plan.taskType.rawValue)"
            content.userInfo = [
                "routineID": plan.routineID.uuidString,
                "scheduledAt": plan.scheduledAt.timeIntervalSince1970,
                "taskType": plan.taskType.rawValue,
                "contentID": plan.contentID,
                "mascot": plan.mascot.rawValue,
                "scheduledHour": hour,
                "scheduledMinute": minute,
                "isRepeatingSchedule": isRecurringRoutine
            ]

            if isRecurringRoutine {
                let weekdays = isEveryDay ? [0] : Array(Set(plan.weekdays)).sorted()
                for weekday in weekdays {
                    guard scheduled < generatedRequestBudget else { break }
                    let key = "\(plan.routineID.uuidString).\(weekday).\(hour).\(minute)"
                    guard emittedRecurringKeys.insert(key).inserted else { continue }
                    var components = DateComponents(hour: hour, minute: minute)
                    if !isEveryDay { components.weekday = weekday }
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let identifier = Self.identifierPrefix + "recurring." + key
                    try await add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    scheduled += 1
                }
            } else {
                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: plan.scheduledAt
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await add(UNNotificationRequest(
                    identifier: Self.identifierPrefix + plan.identifier,
                    content: content,
                    trigger: trigger
                ))
                scheduled += 1
            }
        }

        return CompanionNotificationDiagnostics(
            authorization: authorization,
            scheduledCount: scheduled,
            lastReconciledAt: Date(),
            detail: scheduled == 0
                ? "No enabled companion routine needs a notification right now."
                : recurringRoutineIDs.isEmpty
                    ? "\(scheduled) upcoming companion reminders are scheduled with iOS and continue working while Jomado is closed. Open Jomado periodically to replenish this schedule."
                    : recurringRoutineIDs.count == grouped.count
                        ? "\(scheduled) companion reminder slots repeat with iOS and continue indefinitely even while Jomado stays closed."
                        : "\(scheduled) companion reminder slots are scheduled. Some routines repeat indefinitely; dense schedules use a rolling horizon and should be replenished when Jomado opens."
        )
    }

    func scheduleFollowUp(
        routineID: UUID,
        scheduledAt originalScheduledAt: Date,
        taskType: TaskType,
        contentID: String?,
        mascot: MascotID?,
        delayMinutes: Int = 10
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Still with you 💧"
        content.body = "Your hydration task is still open. A few sips is enough to move it forward."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "jomado.\(taskType.rawValue)"
        var info: [String: Any] = [
            "routineID": routineID.uuidString,
            "scheduledAt": originalScheduledAt.timeIntervalSince1970,
            "taskType": taskType.rawValue
        ]
        if let contentID { info["contentID"] = contentID }
        if let mascot { info["mascot"] = mascot.rawValue }
        content.userInfo = info

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, delayMinutes) * 60),
            repeats: false
        )
        // One follow-up per occurrence. Repeated taps replace the existing request instead
        // of accumulating stale notifications and consuming the system notification budget.
        let identifier = followUpIdentifier(routineID: routineID, scheduledAt: originalScheduledAt)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancelFollowUp(routineID: UUID, scheduledAt: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [
            followUpIdentifier(routineID: routineID, scheduledAt: scheduledAt)
        ])
    }

    private func followUpIdentifier(routineID: UUID, scheduledAt: Date) -> String {
        // Milliseconds keep the identifier deterministic without depending on locale/timezone.
        let milliseconds = Int64((scheduledAt.timeIntervalSince1970 * 1_000).rounded())
        return Self.followUpIdentifierPrefix + routineID.uuidString + "." + String(milliseconds)
    }

    func removeAllCompanionRequests() async {
        let pending = await pendingRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) })
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}
