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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let rawRoutineID = info["routineID"] as? String,
              let routineID = UUID(uuidString: rawRoutineID),
              let scheduledSeconds = info["scheduledAt"] as? TimeInterval else { return }

        let scheduledAt: Date = {
            guard (info["isRepeatingSchedule"] as? Bool) == true,
                  let hour = info["scheduledHour"] as? Int,
                  let minute = info["scheduledMinute"] as? Int else {
                return Date(timeIntervalSince1970: scheduledSeconds)
            }
            var calendar = Calendar.autoupdatingCurrent
            calendar.timeZone = .autoupdatingCurrent
            let deliveredAt = response.notification.date
            return calendar.date(
                bySettingHour: hour, minute: minute, second: 0,
                of: calendar.startOfDay(for: deliveredAt),
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first, direction: .forward
            ) ?? deliveredAt
        }()

        let contentID = info["contentID"] as? String
        let kind: SharedCompanionEventKind
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            kind = .dismissed
        case CompanionNotificationScheduler.completeActionIdentifier:
            kind = .completed
        case CompanionNotificationScheduler.laterActionIdentifier:
            kind = .remindLater
            let taskType = (info["taskType"] as? String).flatMap(TaskType.init(rawValue:)) ?? .hydration
            let mascot = (info["mascot"] as? String).flatMap(MascotID.init(rawValue:))
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
