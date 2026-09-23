import Foundation

public struct BehaviorEvent: Codable, Hashable, Sendable {
    public let scheduledAt: Date
    public let completedAt: Date?
    public let skippedAt: Date?
    public let contentID: String
    public let strategy: Strategy
    public let mascot: MascotID
    public init(scheduledAt: Date, completedAt: Date?, skippedAt: Date?, contentID: String, strategy: Strategy, mascot: MascotID) {
        self.scheduledAt = scheduledAt; self.completedAt = completedAt; self.skippedAt = skippedAt; self.contentID = contentID; self.strategy = strategy; self.mascot = mascot
    }
}

public struct BehaviorSummary: Sendable {
    public let total: Int
    public let completed: Int
    public let skipped: Int
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
            return completed.timeIntervalSince(event.scheduledAt)
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
        return BehaviorSummary(total: events.count, completed: completed, skipped: skipped, completionRate: events.isEmpty ? 0 : Double(completed) / Double(events.count), within2Minutes: fraction(within: 120), within5Minutes: fraction(within: 300), within15Minutes: fraction(within: 900), medianLatency: median)
    }
}
