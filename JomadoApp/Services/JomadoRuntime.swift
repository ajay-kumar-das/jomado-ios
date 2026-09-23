import Foundation
import SwiftData
import SwiftUI
import JomadoCore

struct ActiveReminder: Identifiable {
    let id: UUID
    let scheduleID: UUID?
    var scheduledAt: Date
    var state: ReminderState
    var content: ContentItem

    var delayMinutes: Int { max(0, Int(Date().timeIntervalSince(scheduledAt) / 60)) }
    var urgency: UrgencyStage { UrgencyPolicy.stage(delayMinutes: delayMinutes) }
}

@MainActor
final class JomadoRuntime: ObservableObject {
    @Published var activeReminder: ActiveReminder?
    @Published var contentCount = 0
    @Published var lastError: String?

    let alarmScheduler = AlarmScheduler()
    private let contentRepository = ContentRepository()
    private let engine = ContentEngine(explorationRate: 0.12)
    private var modelContext: ModelContext?

    init() { contentCount = contentRepository.items.count }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        consumeSharedEvents()
    }

    func createSchedule(hour: Int, minute: Int, weekdays: [Int]) async {
        guard let context = modelContext else { return }
        let schedule = HydrationScheduleEntity(hour: hour, minute: minute, weekdays: weekdays)
        context.insert(schedule)
        do {
            try context.save()
            guard await alarmScheduler.requestAuthorization() else {
                lastError = "Alarm permission is required to schedule prominent hydration alarms."
                return
            }
            try await alarmScheduler.schedule(schedule)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteSchedule(_ schedule: HydrationScheduleEntity) {
        alarmScheduler.cancel(schedule)
        modelContext?.delete(schedule)
        try? modelContext?.save()
    }

    func consumeSharedEvents() {
        for event in SharedAlarmEventQueue.drain() {
            handleSharedEvent(event)
        }
    }

    func triggerDeveloperReminder(minutesLate: Int = 0, forcedStrategy: Strategy? = nil) {
        let scheduledAt = Date().addingTimeInterval(TimeInterval(-minutesLate * 60))
        presentReminder(scheduleID: nil, scheduledAt: scheduledAt, initialState: minutesLate > 0 ? .overdue : .alarming, forcedStrategy: forcedStrategy)
    }

    func refreshContentForCurrentUrgency() {
        guard let current = activeReminder else { return }
        presentReminder(scheduleID: current.scheduleID, scheduledAt: current.scheduledAt, initialState: current.state)
    }

    func acknowledge() {
        guard var current = activeReminder else { return }
        current.state = .acknowledged
        activeReminder = current
    }

    func startAction() {
        guard var current = activeReminder else { return }
        current.state = .actionStarted
        activeReminder = current
    }

    func complete() {
        guard let current = activeReminder, let context = modelContext else { return }
        let occurrence = ReminderOccurrenceEntity(scheduleID: current.scheduleID, state: .completed, scheduledAt: current.scheduledAt, content: current.content)
        occurrence.alarmFiredAt = current.scheduledAt
        occurrence.completedAt = Date()
        occurrence.score = CompletionScoring.score(delaySeconds: Date().timeIntervalSince(current.scheduledAt))
        context.insert(occurrence)
        let exposure = ContentExposureEntity(content: current.content, shownAt: current.scheduledAt)
        exposure.completedAt = Date(); context.insert(exposure)
        try? context.save()
        activeReminder = nil
    }

    func skip() {
        guard let current = activeReminder, let context = modelContext else { return }
        let occurrence = ReminderOccurrenceEntity(scheduleID: current.scheduleID, state: .skipped, scheduledAt: current.scheduledAt, content: current.content)
        occurrence.skippedAt = Date(); context.insert(occurrence)
        let exposure = ContentExposureEntity(content: current.content, shownAt: current.scheduledAt)
        exposure.skippedAt = Date(); context.insert(exposure)
        try? context.save()
        activeReminder = nil
    }

    func feedback(_ value: Int) {
        guard let current = activeReminder, let context = modelContext else { return }
        let exposure = ContentExposureEntity(content: current.content)
        exposure.feedback = value
        context.insert(exposure); try? context.save()
    }

    func summary() -> BehaviorSummary {
        guard let context = modelContext else { return BehaviorAnalytics.summarize([]) }
        let rows = (try? context.fetch(FetchDescriptor<ReminderOccurrenceEntity>())) ?? []
        let events = rows.map { row in
            BehaviorEvent(scheduledAt: row.scheduledAt, completedAt: row.completedAt, skippedAt: row.skippedAt, contentID: row.contentID, strategy: Strategy(rawValue: row.strategyRaw) ?? .minimal, mascot: MascotID(rawValue: row.mascotRaw) ?? .momo)
        }
        return BehaviorAnalytics.summarize(events)
    }

    func strategyStats() -> [(Strategy, StrategyPerformance)] {
        guard let context = modelContext else { return [] }
        let rows = (try? context.fetch(FetchDescriptor<ContentExposureEntity>())) ?? []
        var map: [Strategy: StrategyPerformance] = [:]
        for row in rows {
            guard let strategy = Strategy(rawValue: row.strategyRaw) else { continue }
            var p = map[strategy] ?? .init(); p.exposures += 1
            if let completed = row.completedAt { p.completions += 1; p.totalCompletionLatency += completed.timeIntervalSince(row.shownAt) }
            map[strategy] = p
        }
        return map.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    private func handleSharedEvent(_ event: SharedAlarmEvent) {
        guard let context = modelContext else { return }
        var descriptor = FetchDescriptor<HydrationScheduleEntity>(predicate: #Predicate { $0.alarmID == event.alarmID })
        descriptor.fetchLimit = 1
        let schedule = try? context.fetch(descriptor).first
        presentReminder(scheduleID: schedule?.id, scheduledAt: event.timestamp, initialState: event.kind == .acknowledged ? .acknowledged : .overdue)
    }

    private func presentReminder(scheduleID: UUID?, scheduledAt: Date, initialState: ReminderState, forcedStrategy: Strategy? = nil) {
        let delay = max(0, Int(Date().timeIntervalSince(scheduledAt) / 60))
        let urgency = UrgencyPolicy.stage(delayMinutes: delay)
        let context = selectionContext(urgency: urgency, delay: delay)
        var candidates = contentRepository.items
        if let forcedStrategy { candidates = candidates.filter { $0.strategy == forcedStrategy } }
        guard let item = engine.select(items: candidates, context: context) ?? contentRepository.items.first(where: { $0.stage == urgency }) else { return }
        activeReminder = ActiveReminder(id: UUID(), scheduleID: scheduleID, scheduledAt: scheduledAt, state: initialState, content: item)
    }

    private func selectionContext(urgency: UrgencyStage, delay: Int) -> ContentSelectionContext {
        guard let context = modelContext else { return .init(urgency: urgency, now: Date(), delayMinutes: delay) }
        let exposures = (try? context.fetch(FetchDescriptor<ContentExposureEntity>(sortBy: [SortDescriptor(\.shownAt, order: .reverse)]))) ?? []
        let recentIDs = Set(exposures.prefix(20).map(\.contentID))
        var lastSeen: [String: Date] = [:], strategyPerf: [Strategy: StrategyPerformance] = [:], mascotPerf: [MascotID: StrategyPerformance] = [:]
        for row in exposures {
            if lastSeen[row.contentID] == nil { lastSeen[row.contentID] = row.shownAt }
            if let s = Strategy(rawValue: row.strategyRaw) {
                var p = strategyPerf[s] ?? .init(); p.exposures += 1
                if let c = row.completedAt { p.completions += 1; p.totalCompletionLatency += c.timeIntervalSince(row.shownAt) }
                strategyPerf[s] = p
            }
            if let m = MascotID(rawValue: row.mascotRaw) {
                var p = mascotPerf[m] ?? .init(); p.exposures += 1
                if let c = row.completedAt { p.completions += 1; p.totalCompletionLatency += c.timeIntervalSince(row.shownAt) }
                mascotPerf[m] = p
            }
        }
        let disabledStrategies = Set((UserDefaults.standard.string(forKey: "disabledStrategies") ?? "").split(separator: ",").compactMap { Strategy(rawValue: String($0)) })
        let disabledMascots = Set((UserDefaults.standard.string(forKey: "disabledMascots") ?? "").split(separator: ",").compactMap { MascotID(rawValue: String($0)) })
        return .init(urgency: urgency, now: Date(), delayMinutes: delay, recentContentIDs: recentIDs, lastSeen: lastSeen, strategyPerformance: strategyPerf, mascotPerformance: mascotPerf, disabledStrategies: disabledStrategies, disabledMascots: disabledMascots)
    }
}
