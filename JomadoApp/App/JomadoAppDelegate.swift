import UIKit
import UserNotifications
import JomadoCore

final class JomadoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task { @MainActor in
            CompanionNotificationScheduler().registerCategories()
        }
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // UserNotifications objects are not Sendable in Swift 6. Extract primitive,
        // Sendable values while still in this nonisolated delegate callback, then hop
        // to MainActor for Jomado scheduling/state work.
        let info = response.notification.request.content.userInfo
        guard let rawRoutineID = info["routineID"] as? String,
              let routineID = UUID(uuidString: rawRoutineID),
              let scheduledSeconds = info["scheduledAt"] as? TimeInterval else { return }

        let deliveredAt = response.notification.date
        let isRepeatingSchedule = (info["isRepeatingSchedule"] as? Bool) == true
        let scheduledHour = info["scheduledHour"] as? Int
        let scheduledMinute = info["scheduledMinute"] as? Int
        let actionIdentifier = response.actionIdentifier
        let contentID = info["contentID"] as? String
        let taskTypeRaw = info["taskType"] as? String
        let mascotRaw = info["mascot"] as? String

        let scheduledAt: Date = {
            guard isRepeatingSchedule,
                  let hour = scheduledHour,
                  let minute = scheduledMinute else {
                return Date(timeIntervalSince1970: scheduledSeconds)
            }
            var calendar = Calendar.autoupdatingCurrent
            calendar.timeZone = .autoupdatingCurrent
            return calendar.date(
                bySettingHour: hour, minute: minute, second: 0,
                of: calendar.startOfDay(for: deliveredAt),
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first, direction: .forward
            ) ?? deliveredAt
        }()

        await Self.handleCompanionAction(
            actionIdentifier: actionIdentifier,
            routineID: routineID,
            scheduledAt: scheduledAt,
            contentID: contentID,
            taskTypeRaw: taskTypeRaw,
            mascotRaw: mascotRaw
        )
    }

    @MainActor
    private static func handleCompanionAction(
        actionIdentifier: String,
        routineID: UUID,
        scheduledAt: Date,
        contentID: String?,
        taskTypeRaw: String?,
        mascotRaw: String?
    ) async {
        let kind: SharedCompanionEventKind
        switch actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            kind = .dismissed
        case CompanionNotificationScheduler.completeActionIdentifier:
            kind = .completed
        case CompanionNotificationScheduler.laterActionIdentifier:
            kind = .remindLater
            let taskType = taskTypeRaw.flatMap(TaskType.init(rawValue:)) ?? .hydration
            let mascot = mascotRaw.flatMap(MascotID.init(rawValue:))
            try? await CompanionNotificationScheduler().scheduleFollowUp(
                routineID: routineID,
                scheduledAt: scheduledAt,
                taskType: taskType,
                contentID: contentID,
                mascot: mascot
            )
        default:
            kind = .open
        }

        SharedCompanionEventQueue.append(
            routineID: routineID,
            kind: kind,
            scheduledAt: scheduledAt,
            contentID: contentID
        )
    }
}