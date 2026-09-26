import Foundation
import SwiftData
import JomadoCore

@Model
final class HydrationScheduleEntity {
    @Attribute(.unique) var id: UUID
    var hour: Int
    var minute: Int
    var endHour: Int?
    var endMinute: Int?
    var intervalMinutes: Int?
    var weekdaysCSV: String
    var enabled: Bool
    var deliveryModeRaw: String?
    @Attribute(.unique) var alarmID: UUID
    var createdAt: Date
    var updatedAt: Date?
    var lastReconciledAt: Date?

    init(
        id: UUID = UUID(),
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        intervalMinutes: Int,
        weekdays: [Int],
        deliveryMode: ReminderDeliveryMode = .companion,
        enabled: Bool = true,
        alarmID: UUID = UUID()
    ) {
        self.id = id; self.hour = startHour; self.minute = startMinute
        self.endHour = endHour; self.endMinute = endMinute; self.intervalMinutes = intervalMinutes
        self.weekdaysCSV = weekdays.map(String.init).joined(separator: ",")
        self.enabled = enabled; self.deliveryModeRaw = deliveryMode.rawValue; self.alarmID = alarmID; self.createdAt = Date(); self.updatedAt = Date()
    }

    var weekdays: [Int] {
        get { weekdaysCSV.split(separator: ",").compactMap { Int($0) }.sorted() }
        set { weekdaysCSV = Array(Set(newValue)).sorted().map(String.init).joined(separator: ",") }
    }

    var startMinuteOfDay: Int { hour * 60 + minute }
    var resolvedEndHour: Int { endHour ?? hour }
    var resolvedEndMinute: Int { endMinute ?? minute }
    var endMinuteOfDay: Int { resolvedEndHour * 60 + resolvedEndMinute }
    var resolvedIntervalMinutes: Int { intervalMinutes ?? 60 }

    var deliveryMode: ReminderDeliveryMode {
        get { ReminderDeliveryMode(rawValue: deliveryModeRaw ?? "") ?? .alarm }
        set { deliveryModeRaw = newValue.rawValue }
    }

    var configuration: HydrationRoutineConfiguration {
        .init(
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            intervalMinutes: resolvedIntervalMinutes,
            weekdays: weekdays
        )
    }

    var startTimeText: String { Self.timeText(hour: hour, minute: minute) }
    var endTimeText: String { Self.timeText(hour: resolvedEndHour, minute: resolvedEndMinute) }

    var intervalText: String {
        let minutes = resolvedIntervalMinutes
        if minutes < 60 { return "Every \(minutes) min" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "Every \(hours) hr\(hours == 1 ? "" : "s")"
        }
        return "Every \(minutes / 60) hr \(minutes % 60) min"
    }

    func update(
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        intervalMinutes: Int,
        weekdays: [Int],
        deliveryMode: ReminderDeliveryMode
    ) {
        hour = startHour
        minute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.intervalMinutes = intervalMinutes
        self.weekdays = weekdays
        self.deliveryMode = deliveryMode
        updatedAt = Date()
    }

    private static func timeText(hour: Int, minute: Int) -> String {
        var comps = DateComponents(); comps.hour = hour; comps.minute = minute
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

@Model
final class HydrationAlarmEntity {
    @Attribute(.unique) var id: UUID
    var routineID: UUID
    var minuteOfDay: Int
    var configurationSignature: String
    var createdAt: Date
    var lastScheduledAt: Date?
    var lastScheduleError: String?

    init(
        id: UUID = UUID(),
        routineID: UUID,
        minuteOfDay: Int,
        configurationSignature: String
    ) {
        self.id = id
        self.routineID = routineID
        self.minuteOfDay = minuteOfDay
        self.configurationSignature = configurationSignature
        self.createdAt = Date()
    }

    var hour: Int { minuteOfDay / 60 }
    var minute: Int { minuteOfDay % 60 }
}

@Model
final class ReminderOccurrenceEntity {
    @Attribute(.unique) var id: UUID
    var scheduleID: UUID?
    var alarmID: UUID?
    var occurrenceKey: String?
    var timeZoneIdentifier: String?
    var stateRaw: String
    var scheduledAt: Date
    var alarmFiredAt: Date?
    var acknowledgedAt: Date?
    var actionStartedAt: Date?
    var completedAt: Date?
    var skippedAt: Date?
    var expiredAt: Date?
    var contentID: String
    var strategyRaw: String
    var mascotRaw: String
    var score: Int?
    var firstPresentedAt: Date?
    var isSimulationValue: Bool?

    init(
        id: UUID = UUID(),
        scheduleID: UUID?,
        alarmID: UUID? = nil,
        occurrenceKey: String? = nil,
        timeZoneIdentifier: String? = nil,
        state: ReminderState,
        scheduledAt: Date,
        content: ContentItem,
        isSimulation: Bool = false
    ) {
        self.id = id; self.scheduleID = scheduleID; self.alarmID = alarmID
        self.occurrenceKey = occurrenceKey; self.timeZoneIdentifier = timeZoneIdentifier
        self.stateRaw = state.rawValue; self.scheduledAt = scheduledAt
        self.contentID = content.id; self.strategyRaw = content.strategy.rawValue; self.mascotRaw = content.mascot.id.rawValue
        self.firstPresentedAt = Date(); self.isSimulationValue = isSimulation
    }

    var state: ReminderState { get { ReminderState(rawValue: stateRaw) ?? .scheduled } set { stateRaw = newValue.rawValue } }
    var isSimulation: Bool { isSimulationValue ?? false }
}

@Model
final class ContentExposureEntity {
    @Attribute(.unique) var id: UUID
    var contentID: String
    var occurrenceID: UUID?
    var strategyRaw: String
    var mascotRaw: String
    var shownAt: Date
    var completedAt: Date?
    var skippedAt: Date?
    var feedback: Int?
    var isSimulationValue: Bool?

    init(content: ContentItem, occurrenceID: UUID? = nil, shownAt: Date = Date(), isSimulation: Bool = false) {
        self.id = UUID(); self.contentID = content.id; self.occurrenceID = occurrenceID
        self.strategyRaw = content.strategy.rawValue; self.mascotRaw = content.mascot.id.rawValue; self.shownAt = shownAt
        self.isSimulationValue = isSimulation
    }

    var isSimulation: Bool { isSimulationValue ?? false }
}

@Model
final class AlarmEventReceiptEntity {
    @Attribute(.unique) var id: UUID
    var alarmID: UUID
    var kindRaw: String
    var timestamp: Date
    var processedAt: Date

    init(event: SharedAlarmEvent) {
        self.id = event.id
        self.alarmID = event.alarmID
        self.kindRaw = event.kind.rawValue
        self.timestamp = event.timestamp
        self.processedAt = Date()
    }
}
