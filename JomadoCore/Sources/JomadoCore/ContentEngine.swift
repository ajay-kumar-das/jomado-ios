import Foundation

public struct ContentEngine: Sendable {
    public var explorationRate: Double
    public init(explorationRate: Double = 0.12) { self.explorationRate = explorationRate }

    public func rank(items: [ContentItem], context: ContentSelectionContext) -> [ScoredContent] {
        let dayPart = Self.dayPart(for: context.now)
        let calendar = Calendar.current
        return items.compactMap { item in
            guard item.taskType == context.taskType,
                  item.stage == context.urgency,
                  !context.disabledStrategies.contains(item.strategy),
                  !context.disabledMascots.contains(item.mascot.id),
                  item.context.urgencies.contains(context.urgency),
                  item.context.dayParts.isEmpty || item.context.dayParts.contains(dayPart),
                  context.delayMinutes >= item.context.minDelayMinutes,
                  item.context.maxDelayMinutes.map({ context.delayMinutes <= $0 }) ?? true
            else { return nil }

            if let last = context.lastSeen[item.id],
               let cutoff = calendar.date(byAdding: .day, value: -item.selection.cooldownDays, to: context.now),
               last > cutoff { return nil }

            let contextMatch = 1.0
            let strategyPerf = context.strategyPerformance[item.strategy] ?? .init()
            let mascotPerf = context.mascotPerformance[item.mascot.id] ?? .init()
            let effectiveness = normalizedEffectiveness(strategyPerf)
            let strategyAffinity = normalizedEffectiveness(strategyPerf)
            let mascotAffinity = normalizedEffectiveness(mascotPerf)
            let novelty = context.recentContentIDs.contains(item.id) ? 0.0 : 1.0
            let weighted = (0.25 * contextMatch) + (0.25 * effectiveness) + (0.20 * novelty) + (0.15 * mascotAffinity) + (0.15 * strategyAffinity)
            return ScoredContent(item: item, contextMatch: contextMatch, effectiveness: effectiveness, novelty: novelty, mascotAffinity: mascotAffinity, strategyAffinity: strategyAffinity, total: weighted * item.selection.baseWeight)
        }.sorted { lhs, rhs in
            if lhs.total == rhs.total { return lhs.item.id < rhs.item.id }
            return lhs.total > rhs.total
        }
    }

    public func select(items: [ContentItem], context: ContentSelectionContext, explorationRoll: Double = Double.random(in: 0..<1), randomUnit: Double = Double.random(in: 0..<1)) -> ContentItem? {
        let ranked = rank(items: items, context: context)
        guard !ranked.isEmpty else { return nil }
        if explorationRoll < explorationRate {
            let idx = min(Int(randomUnit * Double(ranked.count)), ranked.count - 1)
            return ranked[idx].item
        }
        return ranked[0].item
    }

    private func normalizedEffectiveness(_ performance: StrategyPerformance) -> Double {
        guard performance.exposures > 0 else { return 0.5 }
        let completion = performance.completionRate
        let latencyComponent: Double
        if let latency = performance.averageLatency {
            latencyComponent = max(0, min(1, 1 - latency / 1800))
        } else {
            latencyComponent = 0.25
        }
        return (completion * 0.75) + (latencyComponent * 0.25)
    }

    public static func dayPart(for date: Date, calendar: Calendar = .current) -> DayPart {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }
}
