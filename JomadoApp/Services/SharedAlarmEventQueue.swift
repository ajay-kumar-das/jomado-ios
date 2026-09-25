import Foundation

enum SharedAlarmEventKind: String, Codable, Equatable, Sendable {
    case acknowledged
    case open
}

struct SharedAlarmEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let alarmID: UUID
    let kind: SharedAlarmEventKind
    let timestamp: Date
    let timeZoneIdentifier: String?
}

enum SharedAlarmEventQueue {

    private static let key = "jomado.alarm.events"
    private static let maxEvents = 100
    private static let duplicateWindow: TimeInterval = 5 * 60

    private static var defaults: UserDefaults {
        UserDefaults.standard
    }

    static func append(
        alarmID: UUID,
        kind: SharedAlarmEventKind,
        timestamp: Date = Date()
    ) {
        var events = read()

        // App intents can be retried by the system. Coalesce an immediate retry while
        // still allowing the same recurring alarm to produce a new event next time.
        if let latest = events.last(where: { $0.alarmID == alarmID && $0.kind == kind }),
           abs(timestamp.timeIntervalSince(latest.timestamp)) < duplicateWindow {
            return
        }

        events.append(
            SharedAlarmEvent(
                id: UUID(),
                alarmID: alarmID,
                kind: kind,
                timestamp: timestamp,
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            )
        )

        // Prevent this lightweight queue from growing forever.
        let trimmedEvents = Array(events.suffix(maxEvents))

        guard let data = try? JSONEncoder().encode(trimmedEvents) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    static func drain() -> [SharedAlarmEvent] {
        let events = read()

        defaults.removeObject(forKey: key)

        return events
    }

    static func peek() -> [SharedAlarmEvent] {
        read()
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    private static func read() -> [SharedAlarmEvent] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (
            try? JSONDecoder().decode(
                [SharedAlarmEvent].self,
                from: data
            )
        ) ?? []
    }
}
