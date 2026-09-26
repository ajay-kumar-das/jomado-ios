import Foundation

public struct BehaviorEvent: Codable, Hashable, Sendable {
    public let scheduledAt: Date
    public let completedAt: Date?
    public let skippedAt: Date?
    public let expiredAt: Date?
    public let contentID: String
    public let strategy: Strategy
    public let mascot: MascotID
    public init(scheduledAt: Date, completedAt: Date?, skippedAt: Date?, expiredAt: Date? = nil, contentID: String, strategy: Strategy, mascot: MascotID) {
        self.scheduledAt = scheduledAt; self.completedAt = completedAt; self.skippedAt = skippedAt; self.expiredAt = expiredAt
        self.contentID = contentID; self.strategy = strategy; self.mascot = mascot
    }
}

public struct BehaviorSummary: Sendable {
    public let total: Int
    public let resolved: Int
    public let open: Int
    public let completed: Int
    public let skipped: Int
    public let expired: Int
    /// Completion among terminal outcomes only. Open reminders must never depress or inflate this rate.
    public let completionRate: Double
    public let within2Minutes: Double
    public let within5Minutes: Double
    public let within15Minutes: Double
    public let medianLatency: TimeInterval?
}

public enum BehaviorAnalytics {
    public static func summarize(_ events: [BehaviorEvent]) -> BehaviorSummary {
        let completedEvents = events.compactMap { event -> TimeInterval? in
            guard let completed = event.completedAt else { return nil }
            return max(0, completed.timeIntervalSince(event.scheduledAt))
        }.sorted()
        func fraction(within seconds: TimeInterval) -> Double {
            guard !events.isEmpty else { return 0 }
            return Double(completedEvents.filter { $0 <= seconds }.count) / Double(events.count)
        }
        let median: TimeInterval? = completedEvents.isEmpty ? nil : {
            let middle = completedEvents.count / 2
            if completedEvents.count % 2 == 0 { return (completedEvents[middle - 1] + completedEvents[middle]) / 2 }
            return completedEvents[middle]
        }()
        let completed = completedEvents.count
        let skipped = events.filter { $0.skippedAt != nil }.count
        let expired = events.filter { $0.expiredAt != nil }.count
        let resolved = events.filter { $0.completedAt != nil || $0.skippedAt != nil || $0.expiredAt != nil }.count
        let open = max(0, events.count - resolved)
        let completionRate = resolved == 0 ? 0 : Double(completed) / Double(resolved)
        return BehaviorSummary(total: events.count, resolved: resolved, open: open, completed: completed, skipped: skipped, expired: expired, completionRate: completionRate, within2Minutes: fraction(within: 120), within5Minutes: fraction(within: 300), within15Minutes: fraction(within: 900), medianLatency: median)
    }
}
