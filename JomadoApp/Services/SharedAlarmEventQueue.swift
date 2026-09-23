import Foundation

enum SharedAlarmEventKind: String, Codable {
    case acknowledged
    case open
}

struct SharedAlarmEvent: Codable, Identifiable {
    let id: UUID
    let alarmID: UUID
    let kind: SharedAlarmEventKind
    let timestamp: Date
}

enum SharedAlarmEventQueue {

    private static let key = "jomado.alarm.events"
    private static let maxEvents = 50

    private static var defaults: UserDefaults {
        UserDefaults.standard
    }

    static func append(
        alarmID: UUID,
        kind: SharedAlarmEventKind,
        timestamp: Date = Date()
    ) {
        var events = read()

        events.append(
            SharedAlarmEvent(
                id: UUID(),
                alarmID: alarmID,
                kind: kind,
                timestamp: timestamp
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
