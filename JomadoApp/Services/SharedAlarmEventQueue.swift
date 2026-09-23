import Foundation

enum SharedAlarmEventKind: String, Codable { case acknowledged, open }

struct SharedAlarmEvent: Codable, Identifiable {
    let id: UUID
    let alarmID: UUID
    let kind: SharedAlarmEventKind
    let timestamp: Date
}

enum SharedAlarmEventQueue {
    static let suiteName = "group.com.example.jomado"
    private static let key = "jomado.alarm.events"

    static func append(alarmID: UUID, kind: SharedAlarmEventKind, timestamp: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        var events = read(defaults: defaults)
        events.append(.init(id: UUID(), alarmID: alarmID, kind: kind, timestamp: timestamp))
        if let data = try? JSONEncoder().encode(events.suffix(50)) { defaults.set(data, forKey: key) }
    }

    static func drain() -> [SharedAlarmEvent] {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [] }
        let events = read(defaults: defaults)
        defaults.removeObject(forKey: key)
        return events
    }

    private static func read(defaults: UserDefaults) -> [SharedAlarmEvent] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SharedAlarmEvent].self, from: data)) ?? []
    }
}
