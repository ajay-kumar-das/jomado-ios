import Foundation

enum SharedCompanionEventKind: String, Codable, Sendable {
    case open
    case dismissed
    case remindLater
    case completed
}

struct SharedCompanionEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let routineID: UUID
    let kind: SharedCompanionEventKind
    let scheduledAt: Date
    let contentID: String?
    let timestamp: Date
}

enum SharedCompanionEventQueue {
    private static let key = "jomado.companion.events"
    private static let maxEvents = 100
    private static var defaults: UserDefaults { .standard }

    static func append(
        routineID: UUID,
        kind: SharedCompanionEventKind,
        scheduledAt: Date,
        contentID: String?
    ) {
        var events = read()
        events.append(.init(
            id: UUID(),
            routineID: routineID,
            kind: kind,
            scheduledAt: scheduledAt,
            contentID: contentID,
            timestamp: Date()
        ))
        events = Array(events.suffix(maxEvents))
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: key)
    }

    static func peek() -> [SharedCompanionEvent] { read() }

    static func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let remaining = read().filter { !ids.contains($0.id) }
        if remaining.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: key)
        }
    }

    private static func read() -> [SharedCompanionEvent] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SharedCompanionEvent].self, from: data)) ?? []
    }
}
