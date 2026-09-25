import Foundation

public enum ReminderEvent: Sendable {
    case alarmFired(Date)
    case acknowledge(Date)
    case markOverdue(Date)
    case startAction(Date)
    case complete(Date)
    case skip(Date)
    case expire(Date)
}

public enum ReminderTransitionError: Error, Equatable { case invalid(ReminderState, String) }

public enum ReminderStateMachine {
    public static func apply(_ event: ReminderEvent, to snapshot: ReminderSnapshot) throws -> ReminderSnapshot {
        var next = snapshot
        switch (snapshot.state, event) {
        case (.scheduled, .alarmFired(let date)):
            next.state = .alarming; next.alarmFiredAt = date
        case (.alarming, .acknowledge(let date)):
            next.state = .acknowledged; next.acknowledgedAt = date
        case (.acknowledged, .markOverdue), (.alarming, .markOverdue):
            next.state = .overdue
        case (.alarming, .startAction(let date)), (.acknowledged, .startAction(let date)), (.overdue, .startAction(let date)):
            next.state = .actionStarted; next.actionStartedAt = date
        case (.actionStarted, .complete(let date)), (.alarming, .complete(let date)), (.acknowledged, .complete(let date)), (.overdue, .complete(let date)):
            next.state = .completed; next.completedAt = date
        case (.alarming, .skip(let date)), (.acknowledged, .skip(let date)), (.overdue, .skip(let date)):
            next.state = .skipped; next.skippedAt = date
        case (.scheduled, .expire(let date)), (.alarming, .expire(let date)), (.acknowledged, .expire(let date)), (.overdue, .expire(let date)), (.actionStarted, .expire(let date)):
            next.state = .expired; next.expiredAt = date
        default:
            throw ReminderTransitionError.invalid(snapshot.state, String(describing: event))
        }
        return next
    }
}

public enum UrgencyPolicy {
    public static func stage(delayMinutes: Int) -> UrgencyStage {
        switch delayMinutes {
        case ..<3: .normal
        case 3..<8: .lightOverdue
        case 8..<15: .mediumOverdue
        default: .redZone
        }
    }
}

public enum CompletionScoring {
    public static func score(delaySeconds: TimeInterval) -> Int {
        let minutes = delaySeconds / 60
        switch minutes {
        case ...2: return 100
        case ...5: return 95
        case ...10: return 85
        case ...20: return 70
        case ...30: return 50
        case ...60: return 25
        default: return 10
        }
    }
}
