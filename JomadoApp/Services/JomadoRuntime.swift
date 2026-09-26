import Foundation
import SwiftData
import SwiftUI
import JomadoCore

struct ActiveReminder: Identifiable {
    let id: UUID
    let exposureID: UUID
    let scheduleID: UUID?
    let alarmID: UUID?
    var scheduledAt: Date
    var state: ReminderState
    var content: ContentItem
    let isSimulation: Bool

    var delayMinutes: Int {
        max(0, Int(Date().timeIntervalSince(scheduledAt) / 60))
    }

    var urgency: UrgencyStage {
        UrgencyPolicy.stage(delayMinutes: delayMinutes)
    }
}

struct AlarmDiagnostics: Equatable {
    var authorization: AlarmAuthorizationStatus = .notDetermined
    var expectedAlarmCount = 0
    var registeredAlarmCount = 0
    var lastReconciledAt: Date?
    var detail = "Alarm status has not been checked yet."

    var needsAttention: Bool {
        guard expectedAlarmCount > 0 else { return false }
        return authorization != .authorized || expectedAlarmCount != registeredAlarmCount
    }
}

@MainActor
final class JomadoRuntime: ObservableObject {
    @Published var activeReminder: ActiveReminder?
    @Published private(set) var contentCount = 0
    @Published private(set) var contentDiagnostic = ""
    @Published private(set) var alarmDiagnostics = AlarmDiagnostics()
    @Published private(set) var companionDiagnostics = CompanionNotificationDiagnostics()
    @Published private(set) var companionActivityDiagnostics = CompanionActivityDiagnostics()
    @Published private(set) var companionPushRegistrationDiagnostics = CompanionPushRegistrationDiagnostics()
    @Published private(set) var isReconcilingAlarms = false
    @Published var lastError: String?

    let alarmScheduler = AlarmScheduler()
    let companionScheduler = CompanionNotificationScheduler()
    let companionActivityCoordinator = CompanionActivityCoordinator.shared

    private let contentRepository = ContentRepository()
    private let engine = ContentEngine(explorationRate: 0.12)
    private let staleReminderInterval: TimeInterval = 12 * 60 * 60
    private var modelContext: ModelContext?

    init() {
        contentCount = contentRepository.items.count
        contentDiagnostic = contentRepository.diagnostic
        alarmDiagnostics.authorization = alarmScheduler.authorizationStatus
        companionActivityCoordinator.beginPushTokenObservation()
        refreshCompanionActivityDiagnostics()
    }

    func attach(modelContext: ModelContext) async {
        self.modelContext = modelContext
        migrateLegacyRoutines()
        consumeSharedEvents()
        consumeCompanionEvents()
        restorePendingReminder()
        await reconcileAlarms()
        await reconcileCompanionNotifications()
    }

    func refreshCompanionActivityDiagnostics() {
        companionActivityDiagnostics = companionActivityCoordinator.diagnostics
        Task {
            companionPushRegistrationDiagnostics = await companionActivityCoordinator.remoteRegistrationDiagnostics()
        }
    }

    func refreshSystemState() async {
        refreshCompanionActivityDiagnostics()
        consumeSharedEvents()
        consumeCompanionEvents()
        restorePendingReminder()
        await reconcileAlarms()
        await reconcileCompanionNotifications()
        refreshCompanionActivityDiagnostics()
    }

    @discardableResult
    func requestAlarmAuthorization() async -> Bool {
        do {
            let status = try await alarmScheduler.requestAuthorization()
            alarmDiagnostics.authorization = status
            await reconcileAlarms()
            if status != .authorized {
                lastError = "Alarm access is off. Your routine is saved, but iOS will not present its alarms until access is allowed in Settings."
            }
            return status == .authorized
        } catch {
            alarmDiagnostics.authorization = alarmScheduler.authorizationStatus
            lastError = "Jomado could not request alarm access: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func requestCompanionAuthorization() async -> Bool {
        do {
            let status = try await companionScheduler.requestAuthorization()
            companionDiagnostics.authorization = status
            await reconcileCompanionNotifications()
            if status != .authorized {
                lastError = "Notification access is off. Companion reminders cannot appear while Jomado is closed until access is allowed in Settings."
            }
            return status == .authorized
        } catch {
            lastError = "Jomado could not request notification access: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveRoutine(
        _ routine: HydrationScheduleEntity?,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        intervalMinutes: Int,
        weekdays: [Int],
        deliveryMode: ReminderDeliveryMode
    ) async -> Bool {
        guard let context = modelContext else { return false }
        let configuration = HydrationRoutineConfiguration(
            startMinuteOfDay: startHour * 60 + startMinute,
            endMinuteOfDay: endHour * 60 + endMinute,
            intervalMinutes: intervalMinutes,
            weekdays: weekdays
        )

        do {
            try configuration.validate()
            if let routine {
                routine.update(
                    startHour: startHour,
                    startMinute: startMinute,
                    endHour: endHour,
                    endMinute: endMinute,
                    intervalMinutes: intervalMinutes,
                    weekdays: weekdays,
                    deliveryMode: deliveryMode
                )
            } else {
                context.insert(HydrationScheduleEntity(
                    startHour: startHour,
                    startMinute: startMinute,
                    endHour: endHour,
                    endMinute: endMinute,
                    intervalMinutes: intervalMinutes,
                    weekdays: weekdays,
                    deliveryMode: deliveryMode
                ))
            }
            try context.save()
            await reconcileAlarms()
            if deliveryMode.usesCompanionNotification,
               await companionScheduler.authorizationStatus() == .notDetermined {
                _ = await requestCompanionAuthorization()
            } else {
                await reconcileCompanionNotifications()
            }
            if deliveryMode.usesAlarmKit && alarmDiagnostics.needsAttention {
                lastError = alarmDiagnostics.detail
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func setRoutineEnabled(_ routine: HydrationScheduleEntity, enabled: Bool) async {
        routine.enabled = enabled
        routine.updatedAt = Date()
        do {
            try modelContext?.save()
            await reconcileAlarms()
            await reconcileCompanionNotifications()
        } catch {
            lastError = "The routine could not be updated: \(error.localizedDescription)"
        }
    }

    func deleteRoutine(_ routine: HydrationScheduleEntity) async {
        guard let context = modelContext else { return }
        context.delete(routine)
        do {
            try context.save()
            await reconcileAlarms()
            await reconcileCompanionNotifications()
        } catch {
            lastError = "The routine could not be deleted: \(error.localizedDescription)"
        }
    }

    func reconcileAlarms() async {
        guard let context = modelContext, !isReconcilingAlarms else { return }
        isReconcilingAlarms = true
        defer { isReconcilingAlarms = false }

        let authorization = alarmScheduler.authorizationStatus
        alarmDiagnostics.authorization = authorization

        let routines = (try? context.fetch(
            FetchDescriptor<HydrationScheduleEntity>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
        let alarmRows = (try? context.fetch(FetchDescriptor<HydrationAlarmEntity>())) ?? []

        var desired: [DesiredHydrationAlarm] = []
        var configurationErrors: [String] = []
        var routinesByID: [UUID: HydrationScheduleEntity] = [:]
        for routine in routines {
            routinesByID[routine.id] = routine
            guard routine.enabled, routine.deliveryMode.usesAlarmKit else { continue }
            do {
                try routine.configuration.validate()
                desired.append(contentsOf: routine.configuration.generatedMinutes.map {
                    DesiredHydrationAlarm(
                        routineID: routine.id,
                        minuteOfDay: $0,
                        configurationSignature: routine.configuration.configurationSignature(for: $0)
                    )
                })
            } catch {
                configurationErrors.append(error.localizedDescription)
            }
        }

        let systemAlarmIDs: Set<UUID>
        if authorization == .authorized {
            do {
                systemAlarmIDs = try alarmScheduler.registeredAlarmIDs()
            } catch {
                alarmDiagnostics = AlarmDiagnostics(
                    authorization: authorization,
                    expectedAlarmCount: desired.count,
                    registeredAlarmCount: 0,
                    lastReconciledAt: Date(),
                    detail: "Jomado could not read registered alarms: \(error.localizedDescription)"
                )
                return
            }
        } else {
            systemAlarmIDs = []
        }

        let snapshots = alarmRows.map {
            PersistedHydrationAlarm(
                id: $0.id,
                routineID: $0.routineID,
                minuteOfDay: $0.minuteOfDay,
                configurationSignature: $0.configurationSignature
            )
        }
        let plan = HydrationAlarmReconciler.plan(
            desired: desired,
            persisted: snapshots,
            systemAlarmIDs: systemAlarmIDs
        )
        var rowsByID = Dictionary(uniqueKeysWithValues: alarmRows.map { ($0.id, $0) })
        var usedIDs = Set(rowsByID.keys)
        var newRowsByDesiredKey: [String: HydrationAlarmEntity] = [:]

        for item in plan.create {
            guard let routine = routinesByID[item.routineID] else { continue }
            let preferredID = routine.configuration.generatedMinutes.first == item.minuteOfDay
                ? routine.alarmID
                : UUID()
            let id = usedIDs.contains(preferredID) ? UUID() : preferredID
            usedIDs.insert(id)
            let row = HydrationAlarmEntity(
                id: id,
                routineID: item.routineID,
                minuteOfDay: item.minuteOfDay,
                configurationSignature: item.configurationSignature
            )
            context.insert(row)
            rowsByID[id] = row
            newRowsByDesiredKey[Self.desiredKey(item)] = row
        }

        // Persist identifiers before touching AlarmKit so a process interruption never
        // leaves a newly scheduled alarm without a local record.
        do {
            try context.save()
        } catch {
            alarmDiagnostics = AlarmDiagnostics(
                authorization: authorization,
                expectedAlarmCount: desired.count,
                registeredAlarmCount: 0,
                lastReconciledAt: Date(),
                detail: "Jomado could not persist alarm identifiers: \(error.localizedDescription)"
            )
            return
        }

        var workingSystemIDs = systemAlarmIDs
        var cancellationFailures = Set<UUID>()
        var operationErrors: [String] = configurationErrors

        if authorization == .authorized {
            for id in plan.cancelIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                do {
                    try alarmScheduler.cancel(id: id)
                    workingSystemIDs.remove(id)
                } catch {
                    cancellationFailures.insert(id)
                    operationErrors.append("Could not remove alarm \(id.uuidString.prefix(8)): \(error.localizedDescription)")
                }
            }
        }

        var desiredRecordIDs = Set<UUID>()
        for assignment in plan.existing {
            guard let row = rowsByID[assignment.alarm.id],
                  let routine = routinesByID[assignment.desired.routineID] else { continue }
            desiredRecordIDs.insert(row.id)
            guard assignment.action != .keep else {
                row.lastScheduleError = nil
                continue
            }
            guard authorization == .authorized else {
                row.lastScheduleError = "Alarm access is not authorized."
                continue
            }
            guard !cancellationFailures.contains(row.id) else {
                row.lastScheduleError = "The previous alarm could not be removed."
                continue
            }
            do {
                try await alarmScheduler.schedule(row, for: routine)
                row.configurationSignature = assignment.desired.configurationSignature
                row.lastScheduledAt = Date()
                row.lastScheduleError = nil
                workingSystemIDs.insert(row.id)
            } catch {
                row.lastScheduleError = error.localizedDescription
                operationErrors.append("Could not schedule \(routine.startTimeText) routine alarm: \(error.localizedDescription)")
            }
        }

        for item in plan.create {
            guard let row = newRowsByDesiredKey[Self.desiredKey(item)],
                  let routine = routinesByID[item.routineID] else { continue }
            desiredRecordIDs.insert(row.id)
            guard authorization == .authorized else {
                row.lastScheduleError = "Alarm access is not authorized."
                continue
            }
            do {
                try await alarmScheduler.schedule(row, for: routine)
                row.lastScheduledAt = Date()
                row.lastScheduleError = nil
                workingSystemIDs.insert(row.id)
            } catch {
                row.lastScheduleError = error.localizedDescription
                operationErrors.append("Could not schedule \(routine.startTimeText) routine alarm: \(error.localizedDescription)")
            }
        }

        for id in plan.deleteIDs {
            guard let row = rowsByID[id] else { continue }
            if workingSystemIDs.contains(id) || cancellationFailures.contains(id) {
                row.lastScheduleError = "This stale alarm is waiting to be removed."
            } else {
                context.delete(row)
            }
        }

        let reconciledAt = Date()
        routines.forEach { $0.lastReconciledAt = reconciledAt }
        do {
            try context.save()
        } catch {
            operationErrors.append("Alarm state could not be saved: \(error.localizedDescription)")
        }

        let registeredDesiredCount = workingSystemIDs.intersection(desiredRecordIDs).count
        let detail: String
        if authorization == .denied {
            detail = "Alarm access is denied. The routine is saved locally, but its \(desired.count) alarms are not active."
        } else if authorization == .notDetermined {
            detail = "Alarm access has not been requested. The routine is saved locally, but its \(desired.count) alarms are not active."
        } else if !operationErrors.isEmpty {
            detail = operationErrors.joined(separator: " ")
        } else if desired.isEmpty {
            detail = "No enabled hydration routine needs alarms."
        } else {
            detail = "All \(registeredDesiredCount) generated alarms match your hydration routine."
        }
        alarmDiagnostics = AlarmDiagnostics(
            authorization: authorization,
            expectedAlarmCount: desired.count,
            registeredAlarmCount: registeredDesiredCount,
            lastReconciledAt: reconciledAt,
            detail: detail
        )
    }

    func consumeSharedEvents() {
        guard modelContext != nil else { return }
        for event in SharedAlarmEventQueue.drain().sorted(by: { $0.timestamp < $1.timestamp }) {
            handleSharedEvent(event)
        }
        try? modelContext?.save()
    }

    func reconcileCompanionNotifications() async {
        guard let context = modelContext else { return }
        let routines = (try? context.fetch(
            FetchDescriptor<HydrationScheduleEntity>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
        let now = Date()
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        var plans: [CompanionNotificationPlan] = []

        for routine in routines where routine.enabled && routine.deliveryMode.usesCompanionNotification {
            do { try routine.configuration.validate() } catch { continue }
            for offset in 0..<8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for scheduledAt in routine.configuration.occurrences(on: day, calendar: calendar) where scheduledAt > now {
                    guard let content = notificationContent(for: scheduledAt) else { continue }
                    let localDay = HydrationRoutineConfiguration.localDayIdentifier(for: scheduledAt, calendar: calendar)
                    plans.append(.init(
                        identifier: "\(routine.id.uuidString).\(localDay).\(Int(scheduledAt.timeIntervalSince1970))",
                        routineID: routine.id,
                        scheduledAt: scheduledAt,
                        taskType: .hydration,
                        title: content.message.title,
                        body: content.message.body,
                        contentID: content.id,
                        mascot: content.mascot.id,
                        weekdays: routine.configuration.weekdays
                    ))
                }
            }
        }

        do {
            companionDiagnostics = try await companionScheduler.reconcile(plans: plans)
        } catch {
            companionDiagnostics = CompanionNotificationDiagnostics(
                authorization: await companionScheduler.authorizationStatus(),
                scheduledCount: 0,
                lastReconciledAt: Date(),
                detail: "Jomado could not schedule companion reminders: \(error.localizedDescription)"
            )
            lastError = companionDiagnostics.detail
        }
    }

    func consumeCompanionEvents() {
        guard let context = modelContext else { return }
        let events = SharedCompanionEventQueue.peek().sorted(by: { $0.timestamp < $1.timestamp })
        guard !events.isEmpty else { return }

        let routines = (try? context.fetch(FetchDescriptor<HydrationScheduleEntity>())) ?? []
        let existingOccurrences = (try? context.fetch(FetchDescriptor<ReminderOccurrenceEntity>())) ?? []
        var processed = Set<UUID>()

        for event in events {
            guard let routine = routines.first(where: { $0.id == event.routineID }) else { continue }
            var calendar = Calendar.autoupdatingCurrent
            calendar.timeZone = .autoupdatingCurrent
            let minute = calendar.component(.hour, from: event.scheduledAt) * 60 + calendar.component(.minute, from: event.scheduledAt)
            let key = "companion|\(routine.id.uuidString)|\(HydrationRoutineConfiguration.localDayIdentifier(for: event.scheduledAt, calendar: calendar))|\(minute)"

            if let existing = existingOccurrences.first(where: { $0.occurrenceKey == key }) {
                if event.kind == .completed, !Self.isTerminal(existing.state) {
                    existing.state = .completed
                    existing.actionStartedAt = existing.actionStartedAt ?? event.timestamp
                    existing.completedAt = event.timestamp
                    existing.score = CompletionScoring.score(
                        delaySeconds: max(0, event.timestamp.timeIntervalSince(existing.scheduledAt))
                    )
                    if let routineID = existing.scheduleID {
                        companionScheduler.cancelFollowUp(routineID: routineID, scheduledAt: existing.scheduledAt)
                    }
                } else if [.dismissed, .remindLater].contains(event.kind),
                          [.scheduled, .alarming].contains(existing.state) {
                    existing.state = .acknowledged
                    existing.acknowledgedAt = existing.acknowledgedAt ?? event.timestamp
                } else if event.kind == .open, !Self.isTerminal(existing.state) {
                    existing.state = .actionStarted
                    existing.actionStartedAt = existing.actionStartedAt ?? event.timestamp
                    present(existing)
                }
                processed.insert(event.id)
                continue
            }

            let content = event.contentID.flatMap { id in contentRepository.items.first(where: { $0.id == id }) }
                ?? notificationContent(for: event.scheduledAt)
            guard let content else { continue }
            let initialState: ReminderState = event.kind == .completed
                ? .completed
                : ([.dismissed, .remindLater].contains(event.kind) ? .acknowledged : .actionStarted)
            let occurrence = ReminderOccurrenceEntity(
                scheduleID: routine.id,
                alarmID: nil,
                occurrenceKey: key,
                timeZoneIdentifier: calendar.timeZone.identifier,
                state: initialState,
                scheduledAt: event.scheduledAt,
                content: content
            )
            if event.kind == .completed {
                occurrence.actionStartedAt = event.timestamp
                occurrence.completedAt = event.timestamp
                occurrence.score = CompletionScoring.score(
                    delaySeconds: max(0, event.timestamp.timeIntervalSince(event.scheduledAt))
                )
                companionScheduler.cancelFollowUp(routineID: routine.id, scheduledAt: event.scheduledAt)
            } else if [.dismissed, .remindLater].contains(event.kind) {
                occurrence.acknowledgedAt = event.timestamp
                // Intentionally remain pending. Dismissal is not task completion.
            } else {
                occurrence.actionStartedAt = event.timestamp
                present(occurrence)
            }
            context.insert(occurrence)
            processed.insert(event.id)
        }

        do {
            try context.save()
            SharedCompanionEventQueue.remove(ids: processed)
        } catch {
            lastError = "Jomado could not restore a companion reminder: \(error.localizedDescription)"
        }
    }

    private func notificationContent(for scheduledAt: Date) -> ContentItem? {
        let candidates = contentRepository.items.filter {
            $0.taskType == .hydration && $0.stage == .normal
        }
        guard !candidates.isEmpty else { return nil }
        let slot = abs(Int(scheduledAt.timeIntervalSince1970 / 60)) % candidates.count
        return candidates[slot]
    }

    func triggerDeveloperReminder(minutesLate: Int = 0, forcedStrategy: Strategy? = nil) {
        let scheduledAt = Date().addingTimeInterval(TimeInterval(-minutesLate * 60))
        createAndPresentOccurrence(
            scheduleID: nil,
            alarmID: nil,
            occurrenceKey: "simulation|\(UUID().uuidString)",
            scheduledAt: scheduledAt,
            initialState: minutesLate > 0 ? .overdue : .alarming,
            forcedStrategy: forcedStrategy,
            isSimulation: true
        )
    }

    func refreshContentForCurrentUrgency() {
        guard let current = activeReminder,
              let context = modelContext,
              let occurrence = occurrence(withID: current.id) else { return }
        let content = selectContent(
            scheduledAt: current.scheduledAt,
            forcedStrategy: nil
        ) ?? current.content
        occurrence.contentID = content.id
        occurrence.strategyRaw = content.strategy.rawValue
        occurrence.mascotRaw = content.mascot.id.rawValue
        if current.delayMinutes >= 3 && [.alarming, .acknowledged].contains(occurrence.state) {
            occurrence.state = .overdue
        }
        let exposure = ContentExposureEntity(
            content: content,
            occurrenceID: occurrence.id,
            isSimulation: occurrence.isSimulation
        )
        context.insert(exposure)
        try? context.save()
        activeReminder = ActiveReminder(
            id: occurrence.id,
            exposureID: exposure.id,
            scheduleID: occurrence.scheduleID,
            alarmID: occurrence.alarmID,
            scheduledAt: occurrence.scheduledAt,
            state: occurrence.state,
            content: content,
            isSimulation: occurrence.isSimulation
        )
        if !occurrence.isSimulation {
            let reminder = activeReminder
            Task { if let reminder { await companionActivityCoordinator.present(reminder) } }
        }
    }

    func acknowledge() {
        guard var current = activeReminder,
              let occurrence = occurrence(withID: current.id) else { return }
        if [.alarming, .scheduled].contains(occurrence.state) {
            occurrence.state = .acknowledged
            occurrence.acknowledgedAt = Date()
        }
        current.state = occurrence.state
        activeReminder = current
        try? modelContext?.save()
    }

    func startAction() {
        guard var current = activeReminder,
              let occurrence = occurrence(withID: current.id),
              !Self.isTerminal(occurrence.state) else { return }
        occurrence.state = .actionStarted
        occurrence.actionStartedAt = occurrence.actionStartedAt ?? Date()
        current.state = .actionStarted
        activeReminder = current
        try? modelContext?.save()
    }

    func remindLater() async {
        guard let current = activeReminder,
              let occurrence = occurrence(withID: current.id),
              !Self.isTerminal(occurrence.state) else { return }

        let now = Date()
        if [.scheduled, .alarming, .overdue, .actionStarted].contains(occurrence.state) {
            occurrence.state = .acknowledged
        }
        occurrence.acknowledgedAt = occurrence.acknowledgedAt ?? now
        try? modelContext?.save()

        if occurrence.scheduleID == nil && !occurrence.isSimulation {
            lastError = "This reminder is missing its hydration routine. Open Today and retry after the routine is restored."
            return
        }

        if let routineID = occurrence.scheduleID {
            do {
                try await companionScheduler.scheduleFollowUp(
                    routineID: routineID,
                    scheduledAt: occurrence.scheduledAt,
                    taskType: .hydration,
                    contentID: current.content.id,
                    mascot: current.content.mascot.id,
                    delayMinutes: 10
                )
            } catch {
                lastError = "Jomado could not schedule the 10-minute reminder: \(error.localizedDescription)"
                return
            }
        }

        await companionActivityCoordinator.end(current, completed: false)
        activeReminder = nil
        restorePendingReminder(excludingOccurrenceID: occurrence.id)
    }

    func complete() {
        guard let current = activeReminder,
              let occurrence = occurrence(withID: current.id) else { return }
        let now = Date()
        occurrence.state = .completed
        occurrence.actionStartedAt = occurrence.actionStartedAt ?? now
        occurrence.completedAt = now
        occurrence.score = CompletionScoring.score(
            delaySeconds: max(0, now.timeIntervalSince(occurrence.scheduledAt))
        )
        exposure(withID: current.exposureID)?.completedAt = now
        try? modelContext?.save()
        if let routineID = occurrence.scheduleID {
            companionScheduler.cancelFollowUp(routineID: routineID, scheduledAt: occurrence.scheduledAt)
        }
        Task { await companionActivityCoordinator.end(current, completed: true) }
        activeReminder = nil
        restorePendingReminder()
    }

    func skip() {
        guard let current = activeReminder,
              let occurrence = occurrence(withID: current.id) else { return }
        let now = Date()
        occurrence.state = .skipped
        occurrence.skippedAt = now
        exposure(withID: current.exposureID)?.skippedAt = now
        try? modelContext?.save()
        if let routineID = occurrence.scheduleID {
            companionScheduler.cancelFollowUp(routineID: routineID, scheduledAt: occurrence.scheduledAt)
        }
        Task { await companionActivityCoordinator.end(current, completed: false) }
        activeReminder = nil
        restorePendingReminder()
    }

    func feedback(_ value: Int) {
        guard let current = activeReminder,
              let exposure = exposure(withID: current.exposureID) else { return }
        exposure.feedback = value
        try? modelContext?.save()
    }

    func summary() -> BehaviorSummary {
        guard let context = modelContext else { return BehaviorAnalytics.summarize([]) }
        let rows = ((try? context.fetch(FetchDescriptor<ReminderOccurrenceEntity>())) ?? [])
            .filter { !$0.isSimulation }
        let events = rows.map { row in
            BehaviorEvent(
                scheduledAt: row.scheduledAt,
                completedAt: row.completedAt,
                skippedAt: row.skippedAt,
                expiredAt: row.expiredAt,
                contentID: row.contentID,
                strategy: Strategy(rawValue: row.strategyRaw) ?? .minimal,
                mascot: MascotID(rawValue: row.mascotRaw) ?? .momo
            )
        }
        return BehaviorAnalytics.summarize(events)
    }

    func strategyStats() -> [(Strategy, StrategyPerformance)] {
        guard let context = modelContext else { return [] }
        let rows = ((try? context.fetch(FetchDescriptor<ContentExposureEntity>())) ?? [])
            .filter { !$0.isSimulation }
        var map: [Strategy: StrategyPerformance] = [:]
        for row in rows {
            guard let strategy = Strategy(rawValue: row.strategyRaw) else { continue }
            var performance = map[strategy] ?? .init()
            performance.exposures += 1
            if let completed = row.completedAt {
                performance.completions += 1
                performance.totalCompletionLatency += max(0, completed.timeIntervalSince(row.shownAt))
            }
            map[strategy] = performance
        }
        return map.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    private func migrateLegacyRoutines() {
        guard let context = modelContext else { return }
        let routines = (try? context.fetch(FetchDescriptor<HydrationScheduleEntity>())) ?? []
        var changed = false
        for routine in routines {
            if routine.endHour == nil { routine.endHour = routine.hour; changed = true }
            if routine.endMinute == nil { routine.endMinute = routine.minute; changed = true }
            if routine.intervalMinutes == nil { routine.intervalMinutes = 60; changed = true }
            if routine.updatedAt == nil { routine.updatedAt = routine.createdAt; changed = true }
            if routine.deliveryModeRaw == nil { routine.deliveryModeRaw = ReminderDeliveryMode.alarm.rawValue; changed = true }
        }
        if changed { try? context.save() }
    }

    private func handleSharedEvent(_ event: SharedAlarmEvent) {
        guard let context = modelContext else { return }
        let receipts = (try? context.fetch(FetchDescriptor<AlarmEventReceiptEntity>())) ?? []
        guard !receipts.contains(where: { $0.id == event.id }) else { return }
        context.insert(AlarmEventReceiptEntity(event: event))

        let alarms = (try? context.fetch(FetchDescriptor<HydrationAlarmEntity>())) ?? []
        guard let alarm = alarms.first(where: { $0.id == event.alarmID }) else { return }
        let routines = (try? context.fetch(FetchDescriptor<HydrationScheduleEntity>())) ?? []
        guard let routine = routines.first(where: { $0.id == alarm.routineID }) else { return }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        let scheduledAt = routine.configuration.latestOccurrence(
            onOrBefore: event.timestamp,
            minuteOfDay: alarm.minuteOfDay,
            calendar: calendar
        ) ?? event.timestamp
        let occurrenceKey = "\(alarm.id.uuidString)|\(HydrationRoutineConfiguration.localDayIdentifier(for: scheduledAt, calendar: calendar))|\(alarm.minuteOfDay)"

        let allOccurrences = (try? context.fetch(FetchDescriptor<ReminderOccurrenceEntity>())) ?? []
        let existing = allOccurrences.first(where: { $0.occurrenceKey == occurrenceKey })
        if let existing, Self.isTerminal(existing.state) { return }

        let initialState: ReminderState = event.kind == .acknowledged ? .acknowledged : .actionStarted
        let occurrence: ReminderOccurrenceEntity
        if let existing {
            occurrence = existing
            if event.kind == .acknowledged {
                if [.scheduled, .alarming].contains(occurrence.state) {
                    occurrence.state = .acknowledged
                }
                occurrence.acknowledgedAt = occurrence.acknowledgedAt ?? event.timestamp
            } else {
                occurrence.state = .actionStarted
                occurrence.actionStartedAt = occurrence.actionStartedAt ?? event.timestamp
            }
        } else {
            guard let content = selectContent(scheduledAt: scheduledAt, forcedStrategy: nil) else { return }
            occurrence = ReminderOccurrenceEntity(
                scheduleID: routine.id,
                alarmID: alarm.id,
                occurrenceKey: occurrenceKey,
                timeZoneIdentifier: calendar.timeZone.identifier,
                state: initialState,
                scheduledAt: scheduledAt,
                content: content
            )
            occurrence.alarmFiredAt = scheduledAt
            if event.kind == .acknowledged {
                occurrence.acknowledgedAt = event.timestamp
            } else {
                occurrence.actionStartedAt = event.timestamp
            }
            context.insert(occurrence)
        }

        expireSupersededOccurrences(before: occurrence.scheduledAt, keeping: occurrence.id)
        if Date().timeIntervalSince(occurrence.scheduledAt) > staleReminderInterval {
            occurrence.state = .expired
            occurrence.expiredAt = Date()
            return
        }
        present(occurrence)
    }

    private func createAndPresentOccurrence(
        scheduleID: UUID?,
        alarmID: UUID?,
        occurrenceKey: String,
        scheduledAt: Date,
        initialState: ReminderState,
        forcedStrategy: Strategy?,
        isSimulation: Bool
    ) {
        guard let context = modelContext,
              let content = selectContent(scheduledAt: scheduledAt, forcedStrategy: forcedStrategy) else { return }
        let occurrence = ReminderOccurrenceEntity(
            scheduleID: scheduleID,
            alarmID: alarmID,
            occurrenceKey: occurrenceKey,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            state: initialState,
            scheduledAt: scheduledAt,
            content: content,
            isSimulation: isSimulation
        )
        occurrence.alarmFiredAt = scheduledAt
        context.insert(occurrence)
        let exposure = ContentExposureEntity(
            content: content,
            occurrenceID: occurrence.id,
            isSimulation: isSimulation
        )
        context.insert(exposure)
        try? context.save()
        activeReminder = ActiveReminder(
            id: occurrence.id,
            exposureID: exposure.id,
            scheduleID: scheduleID,
            alarmID: alarmID,
            scheduledAt: scheduledAt,
            state: initialState,
            content: content,
            isSimulation: isSimulation
        )
    }

    private func present(_ occurrence: ReminderOccurrenceEntity) {
        guard let context = modelContext else { return }
        let content = contentRepository.items.first(where: { $0.id == occurrence.contentID })
            ?? selectContent(scheduledAt: occurrence.scheduledAt, forcedStrategy: nil)
        guard let content else { return }
        occurrence.contentID = content.id
        occurrence.strategyRaw = content.strategy.rawValue
        occurrence.mascotRaw = content.mascot.id.rawValue

        let exposures = ((try? context.fetch(FetchDescriptor<ContentExposureEntity>())) ?? [])
            .filter { $0.occurrenceID == occurrence.id }
            .sorted { $0.shownAt > $1.shownAt }
        let exposure: ContentExposureEntity
        if let existing = exposures.first(where: { $0.contentID == content.id }) {
            exposure = existing
        } else {
            exposure = ContentExposureEntity(
                content: content,
                occurrenceID: occurrence.id,
                isSimulation: occurrence.isSimulation
            )
            context.insert(exposure)
        }
        try? context.save()
        activeReminder = ActiveReminder(
            id: occurrence.id,
            exposureID: exposure.id,
            scheduleID: occurrence.scheduleID,
            alarmID: occurrence.alarmID,
            scheduledAt: occurrence.scheduledAt,
            state: occurrence.state,
            content: content,
            isSimulation: occurrence.isSimulation
        )
        if !occurrence.isSimulation {
            let reminder = activeReminder
            Task { if let reminder { await companionActivityCoordinator.present(reminder) } }
        }
    }

    private func restorePendingReminder(excludingOccurrenceID: UUID? = nil) {
        guard activeReminder == nil, let context = modelContext else { return }
        let rows = ((try? context.fetch(
            FetchDescriptor<ReminderOccurrenceEntity>(sortBy: [SortDescriptor(\.scheduledAt, order: .reverse)])
        )) ?? []).filter { !$0.isSimulation && !Self.isTerminal($0.state) }
        let now = Date()
        for row in rows where now.timeIntervalSince(row.scheduledAt) > staleReminderInterval {
            row.state = .expired
            row.expiredAt = now
        }
        if let pending = rows.first(where: {
            !Self.isTerminal($0.state) && $0.id != excludingOccurrenceID
        }) {
            present(pending)
        }
        try? context.save()
    }

    private func expireSupersededOccurrences(before date: Date, keeping id: UUID) {
        guard let context = modelContext else { return }
        let rows = (try? context.fetch(FetchDescriptor<ReminderOccurrenceEntity>())) ?? []
        for row in rows where row.id != id && !row.isSimulation && !Self.isTerminal(row.state) && row.scheduledAt < date {
            row.state = .expired
            row.expiredAt = date
        }
    }

    private func selectContent(scheduledAt: Date, forcedStrategy: Strategy?) -> ContentItem? {
        let delay = max(0, Int(Date().timeIntervalSince(scheduledAt) / 60))
        let urgency = UrgencyPolicy.stage(delayMinutes: delay)
        let selection = selectionContext(urgency: urgency, delay: delay)
        var candidates = contentRepository.items
        if let forcedStrategy {
            candidates = candidates.filter { $0.strategy == forcedStrategy }
        }
        return engine.select(items: candidates, context: selection)
            ?? candidates.first(where: {
                $0.stage == urgency
                    && !selection.disabledStrategies.contains($0.strategy)
                    && !selection.disabledMascots.contains($0.mascot.id)
            })
            ?? contentRepository.items.first(where: { $0.stage == urgency })
    }

    private func selectionContext(urgency: UrgencyStage, delay: Int) -> ContentSelectionContext {
        guard let context = modelContext else {
            return .init(urgency: urgency, now: Date(), delayMinutes: delay)
        }
        let exposures = ((try? context.fetch(
            FetchDescriptor<ContentExposureEntity>(sortBy: [SortDescriptor(\.shownAt, order: .reverse)])
        )) ?? []).filter { !$0.isSimulation }
        let recentIDs = Set(exposures.prefix(20).map(\.contentID))
        var lastSeen: [String: Date] = [:]
        var strategyPerformance: [Strategy: StrategyPerformance] = [:]
        var mascotPerformance: [MascotID: StrategyPerformance] = [:]
        for row in exposures {
            if lastSeen[row.contentID] == nil { lastSeen[row.contentID] = row.shownAt }
            if let strategy = Strategy(rawValue: row.strategyRaw) {
                var performance = strategyPerformance[strategy] ?? .init()
                performance.exposures += 1
                if let completed = row.completedAt {
                    performance.completions += 1
                    performance.totalCompletionLatency += max(0, completed.timeIntervalSince(row.shownAt))
                }
                strategyPerformance[strategy] = performance
            }
            if let mascot = MascotID(rawValue: row.mascotRaw) {
                var performance = mascotPerformance[mascot] ?? .init()
                performance.exposures += 1
                if let completed = row.completedAt {
                    performance.completions += 1
                    performance.totalCompletionLatency += max(0, completed.timeIntervalSince(row.shownAt))
                }
                mascotPerformance[mascot] = performance
            }
        }
        let disabledStrategies = Set(
            (UserDefaults.standard.string(forKey: "disabledStrategies") ?? "")
                .split(separator: ",")
                .compactMap { Strategy(rawValue: String($0)) }
        )
        let disabledMascots = Set(
            (UserDefaults.standard.string(forKey: "disabledMascots") ?? "")
                .split(separator: ",")
                .compactMap { MascotID(rawValue: String($0)) }
        )
        return .init(
            urgency: urgency,
            now: Date(),
            delayMinutes: delay,
            recentContentIDs: recentIDs,
            lastSeen: lastSeen,
            strategyPerformance: strategyPerformance,
            mascotPerformance: mascotPerformance,
            disabledStrategies: disabledStrategies,
            disabledMascots: disabledMascots
        )
    }

    private func occurrence(withID id: UUID) -> ReminderOccurrenceEntity? {
        guard let context = modelContext else { return nil }
        return ((try? context.fetch(FetchDescriptor<ReminderOccurrenceEntity>())) ?? [])
            .first { $0.id == id }
    }

    private func exposure(withID id: UUID) -> ContentExposureEntity? {
        guard let context = modelContext else { return nil }
        return ((try? context.fetch(FetchDescriptor<ContentExposureEntity>())) ?? [])
            .first { $0.id == id }
    }

    private static func desiredKey(_ alarm: DesiredHydrationAlarm) -> String {
        "\(alarm.routineID.uuidString)|\(alarm.minuteOfDay)"
    }

    private static func isTerminal(_ state: ReminderState) -> Bool {
        [.completed, .skipped, .expired].contains(state)
    }
}
