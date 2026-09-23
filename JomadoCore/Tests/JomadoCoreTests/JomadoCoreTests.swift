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
}
