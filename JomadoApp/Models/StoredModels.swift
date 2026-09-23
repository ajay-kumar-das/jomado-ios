import Foundation
import SwiftData
import JomadoCore

@Model
final class HydrationScheduleEntity {
    @Attribute(.unique) var id: UUID
    var hour: Int
    var minute: Int
    var weekdaysCSV: String
    var enabled: Bool
    @Attribute(.unique) var alarmID: UUID
    var createdAt: Date

    init(id: UUID = UUID(), hour: Int, minute: Int, weekdays: [Int], enabled: Bool = true, alarmID: UUID = UUID()) {
        self.id = id; self.hour = hour; self.minute = minute
        self.weekdaysCSV = weekdays.map(String.init).joined(separator: ",")
        self.enabled = enabled; self.alarmID = alarmID; self.createdAt = Date()
    }

    var weekdays: [Int] {
        weekdaysCSV.split(separator: ",").compactMap { Int($0) }
    }

    var timeText: String {
        var comps = DateComponents(); comps.hour = hour; comps.minute = minute
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

@Model
final class ReminderOccurrenceEntity {
    @Attribute(.unique) var id: UUID
    var scheduleID: UUID?
    var stateRaw: String
    var scheduledAt: Date
    var alarmFiredAt: Date?
    var acknowledgedAt: Date?
    var actionStartedAt: Date?
    var completedAt: Date?
    var skippedAt: Date?
    var contentID: String
    var strategyRaw: String
    var mascotRaw: String
    var score: Int?

    init(id: UUID = UUID(), scheduleID: UUID?, state: ReminderState, scheduledAt: Date, content: ContentItem) {
        self.id = id; self.scheduleID = scheduleID; self.stateRaw = state.rawValue; self.scheduledAt = scheduledAt
        self.contentID = content.id; self.strategyRaw = content.strategy.rawValue; self.mascotRaw = content.mascot.id.rawValue
    }

    var state: ReminderState { get { ReminderState(rawValue: stateRaw) ?? .scheduled } set { stateRaw = newValue.rawValue } }
}

@Model
final class ContentExposureEntity {
    @Attribute(.unique) var id: UUID
    var contentID: String
    var strategyRaw: String
    var mascotRaw: String
    var shownAt: Date
    var completedAt: Date?
    var skippedAt: Date?
    var feedback: Int?

    init(content: ContentItem, shownAt: Date = Date()) {
        self.id = UUID(); self.contentID = content.id; self.strategyRaw = content.strategy.rawValue; self.mascotRaw = content.mascot.id.rawValue; self.shownAt = shownAt
    }
}
