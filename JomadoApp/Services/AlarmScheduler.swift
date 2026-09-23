import Foundation
import SwiftUI
import AlarmKit
import AppIntents

struct HydrationAlarmMetadata: AlarmMetadata {
    let scheduleID: UUID
}

@MainActor
final class AlarmScheduler {

    var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    func requestAuthorization() async -> Bool {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        } catch {
            return false
        }
    }

    func schedule(_ schedule: HydrationScheduleEntity) async throws {
        let time = Alarm.Schedule.Relative.Time(
            hour: schedule.hour,
            minute: schedule.minute
        )

        let localeDays = schedule.weekdays.compactMap(Self.localeWeekday)

        let recurrence: Alarm.Schedule.Relative.Recurrence =
            localeDays.isEmpty
            ? .never
            : .weekly(localeDays)

        let alarmSchedule = Alarm.Schedule.relative(
            .init(
                time: time,
                repeats: recurrence
            )
        )

        let stopButton = AlarmButton(
            text: "Silence",
            textColor: .white,
            systemImageName: "speaker.slash.fill"
        )

        let openButton = AlarmButton(
            text: "Drink now",
            textColor: .white,
            systemImageName: "drop.fill"
        )

        let alert = AlarmPresentation.Alert(
            title: "Water time 💧",
            stopButton: stopButton,
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: alert
            ),
            metadata: HydrationAlarmMetadata(
                scheduleID: schedule.id
            ),
            tintColor: .cyan
        )

        typealias Configuration =
            AlarmManager.AlarmConfiguration<HydrationAlarmMetadata>

        let configuration = Configuration(
            schedule: alarmSchedule,
            attributes: attributes,
            stopIntent: AcknowledgeHydrationAlarmIntent(
                alarmID: schedule.alarmID.uuidString
            ),
            secondaryIntent: OpenHydrationIntent(
                alarmID: schedule.alarmID.uuidString
            )
        )

        _ = try await AlarmManager.shared.schedule(
            id: schedule.alarmID,
            configuration: configuration
        )
    }

    func cancel(_ schedule: HydrationScheduleEntity) {
        try? AlarmManager.shared.cancel(
            id: schedule.alarmID
        )
    }

    static func localeWeekday(
        _ calendarWeekday: Int
    ) -> Locale.Weekday? {
        switch calendarWeekday {
        case 1:
            return .sunday
        case 2:
            return .monday
        case 3:
            return .tuesday
        case 4:
            return .wednesday
        case 5:
            return .thursday
        case 6:
            return .friday
        case 7:
            return .saturday
        default:
            return nil
        }
    }
}
