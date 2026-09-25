import Foundation

public enum TaskType: String, Codable, CaseIterable, Sendable { case hydration }
public enum ReminderState: String, Codable, CaseIterable, Sendable { case scheduled, alarming, acknowledged, overdue, actionStarted, completed, skipped, expired }
public enum UrgencyStage: String, Codable, CaseIterable, Sendable { case normal, lightOverdue, mediumOverdue, redZone }
public enum Strategy: String, Codable, CaseIterable, Sendable { case cutePositive, humor, challenge, microStory, gameRPG, supportive, playfulDramatic, minimal }
public enum MascotID: String, Codable, CaseIterable, Sendable { case momo, sparky, pip }
public enum MascotExpression: String, Codable, CaseIterable, Sendable { case idle, hello, waiting, concerned, urgent, celebrating }
public enum DayPart: String, Codable, CaseIterable, Sendable { case morning, afternoon, evening, night }

public struct ContentMessage: Codable, Hashable, Sendable {
    public let title: String
    public let body: String
    public init(title: String, body: String) { self.title = title; self.body = body }
}

public struct MascotPresentation: Codable, Hashable, Sendable {
    public let id: MascotID
    public let expression: MascotExpression
    public let animation: String
    public init(id: MascotID, expression: MascotExpression, animation: String) {
        self.id = id; self.expression = expression; self.animation = animation
    }
}

public struct ContentAttributes: Codable, Hashable, Sendable {
    public let energy: Int
    public let humor: Int
    public let pressure: Int
    public let warmth: Int
    public let playfulness: Int
    public init(energy: Int, humor: Int, pressure: Int, warmth: Int, playfulness: Int) {
        self.energy = energy; self.humor = humor; self.pressure = pressure; self.warmth = warmth; self.playfulness = playfulness
    }
}

public struct ContentContextRule: Codable, Hashable, Sendable {
    public let dayParts: [DayPart]
    public let urgencies: [UrgencyStage]
    public let minDelayMinutes: Int
    public let maxDelayMinutes: Int?
    public init(dayParts: [DayPart], urgencies: [UrgencyStage], minDelayMinutes: Int, maxDelayMinutes: Int?) {
        self.dayParts = dayParts; self.urgencies = urgencies; self.minDelayMinutes = minDelayMinutes; self.maxDelayMinutes = maxDelayMinutes
    }
}

public struct ContentSelectionRule: Codable, Hashable, Sendable {
    public let baseWeight: Double
    public let cooldownDays: Int
    public init(baseWeight: Double = 1.0, cooldownDays: Int = 21) {
        self.baseWeight = baseWeight; self.cooldownDays = cooldownDays
    }
}

public struct ContentItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let version: Int
    public let locale: String
    public let taskType: TaskType
    public let stage: UrgencyStage
    public let strategy: Strategy
    public let message: ContentMessage
    public let mascot: MascotPresentation
    public let attributes: ContentAttributes
    public let context: ContentContextRule
    public let selection: ContentSelectionRule
    public let tags: [String]

    public init(id: String, version: Int = 1, locale: String = "en", taskType: TaskType = .hydration, stage: UrgencyStage, strategy: Strategy, message: ContentMessage, mascot: MascotPresentation, attributes: ContentAttributes, context: ContentContextRule, selection: ContentSelectionRule = .init(), tags: [String] = []) {
        self.id = id; self.version = version; self.locale = locale; self.taskType = taskType; self.stage = stage; self.strategy = strategy; self.message = message; self.mascot = mascot; self.attributes = attributes; self.context = context; self.selection = selection; self.tags = tags
    }
}

public struct StrategyPerformance: Codable, Hashable, Sendable {
    public var exposures: Int
    public var completions: Int
    public var totalCompletionLatency: TimeInterval
    public init(exposures: Int = 0, completions: Int = 0, totalCompletionLatency: TimeInterval = 0) {
        self.exposures = exposures; self.completions = completions; self.totalCompletionLatency = totalCompletionLatency
    }
    public var completionRate: Double { exposures == 0 ? 0.5 : Double(completions) / Double(exposures) }
    public var averageLatency: TimeInterval? { completions == 0 ? nil : totalCompletionLatency / Double(completions) }
}

public struct ContentSelectionContext: Sendable {
    public let taskType: TaskType
    public let urgency: UrgencyStage
    public let now: Date
    public let delayMinutes: Int
    public let recentContentIDs: Set<String>
    public let lastSeen: [String: Date]
    public let strategyPerformance: [Strategy: StrategyPerformance]
    public let mascotPerformance: [MascotID: StrategyPerformance]
    public let disabledStrategies: Set<Strategy>
    public let disabledMascots: Set<MascotID>
    public init(taskType: TaskType = .hydration, urgency: UrgencyStage, now: Date, delayMinutes: Int, recentContentIDs: Set<String> = [], lastSeen: [String: Date] = [:], strategyPerformance: [Strategy: StrategyPerformance] = [:], mascotPerformance: [MascotID: StrategyPerformance] = [:], disabledStrategies: Set<Strategy> = [], disabledMascots: Set<MascotID> = []) {
        self.taskType = taskType; self.urgency = urgency; self.now = now; self.delayMinutes = delayMinutes; self.recentContentIDs = recentContentIDs; self.lastSeen = lastSeen; self.strategyPerformance = strategyPerformance; self.mascotPerformance = mascotPerformance; self.disabledStrategies = disabledStrategies; self.disabledMascots = disabledMascots
    }
}

public struct ScoredContent: Hashable, Sendable {
    public let item: ContentItem
    public let contextMatch: Double
    public let effectiveness: Double
    public let novelty: Double
    public let mascotAffinity: Double
    public let strategyAffinity: Double
    public let total: Double
}

public struct ReminderSnapshot: Codable, Hashable, Sendable {
    public var state: ReminderState
    public var scheduledAt: Date
    public var alarmFiredAt: Date?
    public var acknowledgedAt: Date?
    public var actionStartedAt: Date?
    public var completedAt: Date?
    public var skippedAt: Date?
    public var expiredAt: Date?
    public init(state: ReminderState = .scheduled, scheduledAt: Date) {
        self.state = state; self.scheduledAt = scheduledAt
    }
}
