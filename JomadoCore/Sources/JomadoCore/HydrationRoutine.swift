import Foundation

public enum HydrationRoutineValidationError: Error, Equatable, LocalizedError, Sendable {
    case invalidStartTime
    case invalidEndTime
    case endBeforeStart
    case invalidInterval
    case noWeekdays
    case invalidWeekday
    case tooManyAlarms(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidStartTime:
            return "Choose a valid start time."
        case .invalidEndTime:
            return "Choose a valid end time."
        case .endBeforeStart:
            return "End time must be at or after the start time."
        case .invalidInterval:
            return "Choose an interval between 15 minutes and 6 hours."
        case .noWeekdays:
            return "Choose at least one day."
        case .invalidWeekday:
            return "Weekdays must use Calendar values 1 through 7."
        case .tooManyAlarms(let count):
            return "This routine would create \(count) alarms. Shorten the window or use a longer interval."
        }
    }
}

/// The user-facing hydration window. Times are stored as local wall-clock minutes so
/// AlarmKit can keep them aligned when the device's timezone changes.
public struct HydrationRoutineConfiguration: Codable, Hashable, Sendable {
    public static let minimumIntervalMinutes = 15
    public static let maximumIntervalMinutes = 6 * 60
    public static let maximumGeneratedAlarms = 48

    public let startMinuteOfDay: Int
    public let endMinuteOfDay: Int
    public let intervalMinutes: Int
    public let weekdays: [Int]

    public init(
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        intervalMinutes: Int,
        weekdays: [Int]
    ) {
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.intervalMinutes = intervalMinutes
        self.weekdays = Array(Set(weekdays)).sorted()
    }

    public func validate() throws {
        guard (0..<1_440).contains(startMinuteOfDay) else {
            throw HydrationRoutineValidationError.invalidStartTime
        }
        guard (0..<1_440).contains(endMinuteOfDay) else {
            throw HydrationRoutineValidationError.invalidEndTime
        }
        guard endMinuteOfDay >= startMinuteOfDay else {
            throw HydrationRoutineValidationError.endBeforeStart
        }
        guard (Self.minimumIntervalMinutes...Self.maximumIntervalMinutes).contains(intervalMinutes),
              intervalMinutes.isMultiple(of: 15) else {
            throw HydrationRoutineValidationError.invalidInterval
        }
        guard !weekdays.isEmpty else {
            throw HydrationRoutineValidationError.noWeekdays
        }
        guard weekdays.allSatisfy({ (1...7).contains($0) }) else {
            throw HydrationRoutineValidationError.invalidWeekday
        }

        let count = ((endMinuteOfDay - startMinuteOfDay) / intervalMinutes) + 1
        guard count <= Self.maximumGeneratedAlarms else {
            throw HydrationRoutineValidationError.tooManyAlarms(count)
        }
    }

    public var generatedMinutes: [Int] {
        guard (try? validate()) != nil else { return [] }
        return stride(
            from: startMinuteOfDay,
            through: endMinuteOfDay,
            by: intervalMinutes
        ).map { $0 }
    }

    public var alarmCount: Int { generatedMinutes.count }

    public func configurationSignature(for minuteOfDay: Int) -> String {
        "v1|\(minuteOfDay)|\(weekdays.map(String.init).joined(separator: ","))"
    }

    /// Returns the local occurrence on a day. During a spring-forward gap the next
    /// valid local time is used; during a repeated fall-back hour the first match wins.
    public func occurrence(
        on day: Date,
        minuteOfDay: Int,
        calendar sourceCalendar: Calendar
    ) -> Date? {
        guard generatedMinutes.contains(minuteOfDay) else { return nil }

        let calendar = sourceCalendar
        let startOfDay = calendar.startOfDay(for: day)
        let searchStart = calendar.date(byAdding: .second, value: -1, to: startOfDay) ?? startOfDay
        let components = DateComponents(
            hour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0
        )
        guard let candidate = calendar.nextDate(
            after: searchStart,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(candidate, inSameDayAs: day) else {
            return nil
        }
        return candidate
    }

    public func occurrences(on day: Date, calendar: Calendar) -> [Date] {
        guard weekdays.contains(calendar.component(.weekday, from: day)) else { return [] }
        return generatedMinutes.compactMap {
            occurrence(on: day, minuteOfDay: $0, calendar: calendar)
        }
    }

    public func latestOccurrence(
        onOrBefore date: Date,
        minuteOfDay: Int,
        calendar: Calendar,
        lookbackDays: Int = 8
    ) -> Date? {
        for offset in 0..<lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)),
                  let candidate = occurrence(on: day, minuteOfDay: minuteOfDay, calendar: calendar),
                  candidate <= date else { continue }
            return candidate
        }
        return nil
    }

    public func nextOccurrence(after date: Date, calendar: Calendar, lookaheadDays: Int = 8) -> Date? {
        var best: Date?
        for offset in 0..<lookaheadDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            for candidate in occurrences(on: day, calendar: calendar) where candidate > date {
                if best == nil || candidate < best! { best = candidate }
            }
            if best != nil { return best }
        }
        return best
    }

    public static func localDayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

public struct DesiredHydrationAlarm: Hashable, Sendable {
    public let routineID: UUID
    public let minuteOfDay: Int
    public let configurationSignature: String

    public init(routineID: UUID, minuteOfDay: Int, configurationSignature: String) {
        self.routineID = routineID
        self.minuteOfDay = minuteOfDay
        self.configurationSignature = configurationSignature
    }
}

public struct PersistedHydrationAlarm: Hashable, Sendable {
    public let id: UUID
    public let routineID: UUID
    public let minuteOfDay: Int
    public let configurationSignature: String

    public init(id: UUID, routineID: UUID, minuteOfDay: Int, configurationSignature: String) {
        self.id = id
        self.routineID = routineID
        self.minuteOfDay = minuteOfDay
        self.configurationSignature = configurationSignature
    }
}

public enum ExistingAlarmAction: Hashable, Sendable {
    case keep
    case schedule
    case reschedule
}

public struct ExistingAlarmAssignment: Hashable, Sendable {
    public let alarm: PersistedHydrationAlarm
    public let desired: DesiredHydrationAlarm
    public let action: ExistingAlarmAction
}

public struct HydrationAlarmReconciliationPlan: Equatable, Sendable {
    public let existing: [ExistingAlarmAssignment]
    public let create: [DesiredHydrationAlarm]
    public let cancelIDs: Set<UUID>
    public let deleteIDs: Set<UUID>
}

public enum HydrationAlarmReconciler {
    public static func plan(
        desired: [DesiredHydrationAlarm],
        persisted: [PersistedHydrationAlarm],
        systemAlarmIDs: Set<UUID>
    ) -> HydrationAlarmReconciliationPlan {
        let desiredByKey = Dictionary(
            uniqueKeysWithValues: desired.map { (key($0.routineID, $0.minuteOfDay), $0) }
        )
        let grouped = Dictionary(grouping: persisted) { key($0.routineID, $0.minuteOfDay) }

        var assignments: [ExistingAlarmAssignment] = []
        var creates: [DesiredHydrationAlarm] = []
        var deleteIDs = Set<UUID>()
        var retainedIDs = Set<UUID>()

        for desiredAlarm in desired.sorted(by: desiredSort) {
            let alarmKey = key(desiredAlarm.routineID, desiredAlarm.minuteOfDay)
            let candidates = (grouped[alarmKey] ?? []).sorted {
                $0.id.uuidString < $1.id.uuidString
            }
            guard let keeper = candidates.first else {
                creates.append(desiredAlarm)
                continue
            }

            retainedIDs.insert(keeper.id)
            deleteIDs.formUnion(candidates.dropFirst().map(\.id))

            let action: ExistingAlarmAction
            if keeper.configurationSignature != desiredAlarm.configurationSignature {
                action = systemAlarmIDs.contains(keeper.id) ? .reschedule : .schedule
            } else if !systemAlarmIDs.contains(keeper.id) {
                action = .schedule
            } else {
                action = .keep
            }
            assignments.append(.init(alarm: keeper, desired: desiredAlarm, action: action))
        }

        for record in persisted where desiredByKey[key(record.routineID, record.minuteOfDay)] == nil {
            deleteIDs.insert(record.id)
        }

        let cancelIDs = systemAlarmIDs.subtracting(retainedIDs).union(
            assignments.compactMap { $0.action == .reschedule ? $0.alarm.id : nil }
        )

        return HydrationAlarmReconciliationPlan(
            existing: assignments,
            create: creates,
            cancelIDs: cancelIDs,
            deleteIDs: deleteIDs
        )
    }

    private static func key(_ routineID: UUID, _ minuteOfDay: Int) -> String {
        "\(routineID.uuidString)|\(minuteOfDay)"
    }

    private static func desiredSort(_ lhs: DesiredHydrationAlarm, _ rhs: DesiredHydrationAlarm) -> Bool {
        if lhs.routineID != rhs.routineID {
            return lhs.routineID.uuidString < rhs.routineID.uuidString
        }
        return lhs.minuteOfDay < rhs.minuteOfDay
    }
}
