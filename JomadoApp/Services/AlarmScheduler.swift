import Foundation
import SwiftUI
import AlarmKit
import AppIntents
import JomadoCore

struct HydrationAlarmMetadata: AlarmMetadata {
    let routineID: UUID
    let minuteOfDay: Int
}

enum AlarmAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .authorized: "Allowed"
        case .denied: "Denied"
        }
    }

    var systemImage: String {
        switch self {
        case .notDetermined: "questionmark.circle"
        case .authorized: "checkmark.circle.fill"
        case .denied: "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class AlarmScheduler {
    var authorizationStatus: AlarmAuthorizationStatus {
        switch AlarmManager.shared.authorizationState {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestAuthorization() async throws -> AlarmAuthorizationStatus {
        let state = try await AlarmManager.shared.requestAuthorization()
        switch state {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func registeredAlarmIDs() throws -> Set<UUID> {
        Set(try AlarmManager.shared.alarms.map(\.id))
    }

    func schedule(_ alarm: HydrationAlarmEntity, for routine: HydrationScheduleEntity) async throws {
        let time = Alarm.Schedule.Relative.Time(
            hour: alarm.hour,
            minute: alarm.minute
        )
        let localeDays = routine.weekdays.compactMap(Self.localeWeekday)
        let alarmSchedule = Alarm.Schedule.relative(
            .init(time: time, repeats: .weekly(localeDays))
        )

        let stopButton = AlarmButton(
            text: "Silence",
            textColor: .white,
            systemImageName: "speaker.slash.fill"
        )
        let openButton = AlarmButton(
            text: "Open task",
            textColor: .white,
            systemImageName: "drop.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: "Water time",
            stopButton: stopButton,
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: HydrationAlarmMetadata(
                routineID: routine.id,
                minuteOfDay: alarm.minuteOfDay
            ),
            tintColor: .cyan
        )

        typealias Configuration = AlarmManager.AlarmConfiguration<HydrationAlarmMetadata>
        let configuration = Configuration(
            schedule: alarmSchedule,
            attributes: attributes,
            stopIntent: AcknowledgeHydrationAlarmIntent(alarmID: alarm.id.uuidString),
            secondaryIntent: OpenHydrationIntent(alarmID: alarm.id.uuidString)
        )

        _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
    }

    func cancel(id: UUID) throws {
        try AlarmManager.shared.cancel(id: id)
    }

    static func localeWeekday(_ calendarWeekday: Int) -> Locale.Weekday? {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return nil
        }
    }
}
