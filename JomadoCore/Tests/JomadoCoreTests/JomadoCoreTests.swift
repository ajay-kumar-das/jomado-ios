import XCTest
@testable import JomadoCore

final class JomadoCoreTests: XCTestCase {
    func testReminderCannotJumpFromScheduledToCompleted() {
        let snap = ReminderSnapshot(scheduledAt: Date())
        XCTAssertThrowsError(try ReminderStateMachine.apply(.complete(Date()), to: snap))
    }

    func testNormalFlow() throws {
        let t0 = Date()
        var snap = ReminderSnapshot(scheduledAt: t0)
        snap = try ReminderStateMachine.apply(.alarmFired(t0), to: snap)
        XCTAssertEqual(snap.state, .alarming)
        snap = try ReminderStateMachine.apply(.acknowledge(t0.addingTimeInterval(5)), to: snap)
        XCTAssertEqual(snap.state, .acknowledged)
        snap = try ReminderStateMachine.apply(.markOverdue(t0.addingTimeInterval(180)), to: snap)
        XCTAssertEqual(snap.state, .overdue)
        snap = try ReminderStateMachine.apply(.startAction(t0.addingTimeInterval(240)), to: snap)
        XCTAssertEqual(snap.state, .actionStarted)
        snap = try ReminderStateMachine.apply(.complete(t0.addingTimeInterval(260)), to: snap)
        XCTAssertEqual(snap.state, .completed)
    }

    func testAcknowledgingAlarmDoesNotCompleteHydration() throws {
        let scheduledAt = Date()
        var snapshot = ReminderSnapshot(scheduledAt: scheduledAt)
        snapshot = try ReminderStateMachine.apply(.alarmFired(scheduledAt), to: snapshot)
        snapshot = try ReminderStateMachine.apply(
            .acknowledge(scheduledAt.addingTimeInterval(2)),
            to: snapshot
        )

        XCTAssertEqual(snapshot.state, .acknowledged)
        XCTAssertNotNil(snapshot.acknowledgedAt)
        XCTAssertNil(snapshot.completedAt)
    }

    func testUrgencyPolicy() {
        XCTAssertEqual(UrgencyPolicy.stage(delayMinutes: 0), .normal)
        XCTAssertEqual(UrgencyPolicy.stage(delayMinutes: 3), .lightOverdue)
        XCTAssertEqual(UrgencyPolicy.stage(delayMinutes: 8), .mediumOverdue)
        XCTAssertEqual(UrgencyPolicy.stage(delayMinutes: 15), .redZone)
    }

    func testCompletionScore() {
        XCTAssertEqual(CompletionScoring.score(delaySeconds: 90), 100)
        XCTAssertEqual(CompletionScoring.score(delaySeconds: 7 * 60), 85)
        XCTAssertEqual(CompletionScoring.score(delaySeconds: 65 * 60), 10)
    }

    func testContentCooldownFiltersItem() {
        let now = Date()
        let item = ContentItem(id: "x", stage: .normal, strategy: .cutePositive, message: .init(title: "Hi", body: "Water"), mascot: .init(id: .momo, expression: .hello, animation: "wave"), attributes: .init(energy: 1, humor: 1, pressure: 1, warmth: 5, playfulness: 4), context: .init(dayParts: [], urgencies: [.normal], minDelayMinutes: 0, maxDelayMinutes: 2), selection: .init(baseWeight: 1, cooldownDays: 21))
        let ctx = ContentSelectionContext(urgency: .normal, now: now, delayMinutes: 0, lastSeen: ["x": now.addingTimeInterval(-3600)])
        XCTAssertTrue(ContentEngine().rank(items: [item], context: ctx).isEmpty)
    }

    func testExploreCanPickNonTopCandidate() {
        let now = Date()
        let base = ContentContextRule(dayParts: [], urgencies: [.normal], minDelayMinutes: 0, maxDelayMinutes: 2)
        let a = ContentItem(id: "a", stage: .normal, strategy: .cutePositive, message: .init(title: "A", body: "A"), mascot: .init(id: .momo, expression: .hello, animation: "wave"), attributes: .init(energy: 1, humor: 1, pressure: 1, warmth: 5, playfulness: 4), context: base, selection: .init(baseWeight: 2, cooldownDays: 0))
        let b = ContentItem(id: "b", stage: .normal, strategy: .minimal, message: .init(title: "B", body: "B"), mascot: .init(id: .pip, expression: .hello, animation: "wave"), attributes: .init(energy: 1, humor: 1, pressure: 1, warmth: 1, playfulness: 1), context: base, selection: .init(baseWeight: 1, cooldownDays: 0))
        let ctx = ContentSelectionContext(urgency: .normal, now: now, delayMinutes: 0)
        let selected = ContentEngine(explorationRate: 1).select(items: [a,b], context: ctx, explorationRoll: 0, randomUnit: 0.99)
        XCTAssertEqual(selected?.id, "b")
    }

    func testHydrationRoutineGeneratesInclusiveLocalTimeSlots() throws {
        let routine = HydrationRoutineConfiguration(
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 11 * 60,
            intervalMinutes: 60,
            weekdays: [2, 3, 4, 5, 6]
        )

        try routine.validate()
        XCTAssertEqual(routine.generatedMinutes, [480, 540, 600, 660])
        XCTAssertEqual(routine.alarmCount, 4)
        XCTAssertEqual(routine.configurationSignature(for: 480), "v1|480|2,3,4,5,6")
    }

    func testHydrationRoutineRejectsAnOvernightWindowAndEmptyWeekdays() {
        let overnight = HydrationRoutineConfiguration(
            startMinuteOfDay: 20 * 60,
            endMinuteOfDay: 8 * 60,
            intervalMinutes: 60,
            weekdays: [2]
        )
        XCTAssertThrowsError(try overnight.validate()) { error in
            XCTAssertEqual(error as? HydrationRoutineValidationError, .endBeforeStart)
        }

        let noDays = HydrationRoutineConfiguration(
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 17 * 60,
            intervalMinutes: 60,
            weekdays: []
        )
        XCTAssertThrowsError(try noDays.validate()) { error in
            XCTAssertEqual(error as? HydrationRoutineValidationError, .noWeekdays)
        }
    }

    func testRoutineUsesNextValidWallClockTimeAcrossSpringDSTGap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let springForwardDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let routine = HydrationRoutineConfiguration(
            startMinuteOfDay: 2 * 60 + 30,
            endMinuteOfDay: 2 * 60 + 30,
            intervalMinutes: 60,
            weekdays: [1]
        )

        let occurrence = try XCTUnwrap(routine.occurrences(on: springForwardDay, calendar: calendar).first)
        let components = calendar.dateComponents([.hour, .minute], from: occurrence)
        XCTAssertEqual(components.hour, 3)
        XCTAssertEqual(components.minute, 30)
    }

    func testNextOccurrencePreservesLocalHourInDifferentTimeZones() throws {
        let routine = HydrationRoutineConfiguration(
            startMinuteOfDay: 9 * 60,
            endMinuteOfDay: 9 * 60,
            intervalMinutes: 60,
            weekdays: Array(1...7)
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let indiaOccurrence = try XCTUnwrap(routine.nextOccurrence(after: now, calendar: kolkata))
        let usOccurrence = try XCTUnwrap(routine.nextOccurrence(after: now, calendar: losAngeles))

        XCTAssertEqual(kolkata.component(.hour, from: indiaOccurrence), 9)
        XCTAssertEqual(losAngeles.component(.hour, from: usOccurrence), 9)
        XCTAssertNotEqual(indiaOccurrence, usOccurrence)
    }

    func testAlarmReconciliationKeepsStableIDsAndRepairsDrift() {
        let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let keeperID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let staleID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let unknownSystemID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let desired = [
            DesiredHydrationAlarm(routineID: routineID, minuteOfDay: 480, configurationSignature: "new"),
            DesiredHydrationAlarm(routineID: routineID, minuteOfDay: 540, configurationSignature: "new-540")
        ]
        let persisted = [
            PersistedHydrationAlarm(id: keeperID, routineID: routineID, minuteOfDay: 480, configurationSignature: "old"),
            PersistedHydrationAlarm(id: duplicateID, routineID: routineID, minuteOfDay: 480, configurationSignature: "old"),
            PersistedHydrationAlarm(id: staleID, routineID: routineID, minuteOfDay: 600, configurationSignature: "stale")
        ]

        let plan = HydrationAlarmReconciler.plan(
            desired: desired,
            persisted: persisted,
            systemAlarmIDs: [keeperID, duplicateID, staleID, unknownSystemID]
        )

        XCTAssertEqual(plan.existing.count, 1)
        XCTAssertEqual(plan.existing.first?.alarm.id, keeperID)
        XCTAssertEqual(plan.existing.first?.action, .reschedule)
        XCTAssertEqual(plan.create.map(\.minuteOfDay), [540])
        XCTAssertEqual(plan.deleteIDs, [duplicateID, staleID])
        XCTAssertEqual(plan.cancelIDs, [keeperID, duplicateID, staleID, unknownSystemID])
    }

    func testMissingSystemAlarmIsScheduledWithoutReplacingItsID() {
        let routineID = UUID()
        let alarmID = UUID()
        let desired = DesiredHydrationAlarm(
            routineID: routineID,
            minuteOfDay: 600,
            configurationSignature: "same"
        )
        let persisted = PersistedHydrationAlarm(
            id: alarmID,
            routineID: routineID,
            minuteOfDay: 600,
            configurationSignature: "same"
        )

        let plan = HydrationAlarmReconciler.plan(
            desired: [desired],
            persisted: [persisted],
            systemAlarmIDs: []
        )

        XCTAssertEqual(plan.existing.first?.action, .schedule)
        XCTAssertTrue(plan.create.isEmpty)
        XCTAssertTrue(plan.cancelIDs.isEmpty)
        XCTAssertTrue(plan.deleteIDs.isEmpty)
    }

    func testContentCatalogRejectsDuplicateIDs() {
        let context = ContentContextRule(
            dayParts: [],
            urgencies: [.normal],
            minDelayMinutes: 0,
            maxDelayMinutes: 2
        )
        let item = ContentItem(
            id: "duplicate",
            stage: .normal,
            strategy: .minimal,
            message: .init(title: "Water", body: "Take a sip."),
            mascot: .init(id: .momo, expression: .hello, animation: "wave"),
            attributes: .init(energy: 1, humor: 1, pressure: 1, warmth: 1, playfulness: 1),
            context: context
        )

        XCTAssertThrowsError(try ContentCatalogValidator.validate([item, item])) { error in
            XCTAssertEqual(error as? ContentCatalogValidationError, .duplicateID("duplicate"))
        }
    }

    func testAnalyticsClampsClockSkewInsteadOfReportingNegativeLatency() {
        let scheduled = Date(timeIntervalSince1970: 100)
        let event = BehaviorEvent(
            scheduledAt: scheduled,
            completedAt: scheduled.addingTimeInterval(-10),
            skippedAt: nil,
            contentID: "x",
            strategy: .minimal,
            mascot: .momo
        )

        let summary = BehaviorAnalytics.summarize([event])
        XCTAssertEqual(summary.medianLatency, 0)
        XCTAssertEqual(summary.within2Minutes, 1)
    }
}
