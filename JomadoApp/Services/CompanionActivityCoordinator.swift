import ActivityKit
import Foundation
import JomadoCore

@MainActor
struct CompanionActivityDiagnostics: Equatable {
    var activitiesEnabled = false
    var pushToStartTokenAvailable = false
    var activeActivityCount = 0
    var tokenUpdatedAt: Date?
    var remoteRegistration = CompanionPushRegistrationDiagnostics()

    var detail: String {
        if !activitiesEnabled {
            return "Live Activities are disabled in iOS. Companion notifications still work, but Jomado cannot remain visible on the Lock Screen."
        }
        if !pushToStartTokenAvailable {
            return "Live Activities are allowed. Waiting for iOS to provide the push-to-start token required for starting a new companion while Jomado is terminated."
        }
        return "Live Activities are allowed and this device has a push-to-start token. A privacy-minimal APNs provider is still required before Jomado can start a new companion while the app is terminated."
    }
}

@MainActor
final class CompanionActivityCoordinator {
    static let shared = CompanionActivityCoordinator()

    private var observingPushToStartToken = false
    private(set) var tokenUpdatedAt: Date? {
        get { UserDefaults.standard.object(forKey: "companionPushToStartTokenUpdatedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "companionPushToStartTokenUpdatedAt") }
    }

    var diagnostics: CompanionActivityDiagnostics {
        CompanionActivityDiagnostics(
            activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled,
            pushToStartTokenAvailable: !(UserDefaults.standard.string(forKey: "companionPushToStartToken") ?? "").isEmpty,
            activeActivityCount: Activity<CompanionActivityAttributes>.activities.count,
            tokenUpdatedAt: tokenUpdatedAt
        )
    }

    private init() {}

    func beginPushTokenObservation() {
        guard !observingPushToStartToken else { return }
        observingPushToStartToken = true

        Task {
            for await token in Activity<CompanionActivityAttributes>.pushToStartTokenUpdates {
                let value = token.map { String(format: "%02x", $0) }.joined()
                // This token is device-scoped routing metadata, not hydration history.
                // Keep it local until a production APNs registration endpoint exists.
                UserDefaults.standard.set(value, forKey: "companionPushToStartToken")
                self.tokenUpdatedAt = Date()
                await CompanionPushRegistrationService.shared.register(pushToStartToken: value)
            }
        }
    }


    func remoteRegistrationDiagnostics() async -> CompanionPushRegistrationDiagnostics {
        let tokenAvailable = !(UserDefaults.standard.string(forKey: "companionPushToStartToken") ?? "").isEmpty
        return await CompanionPushRegistrationService.shared.diagnostics(tokenAvailable: tokenAvailable)
    }

    func present(_ reminder: ActiveReminder) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = Self.state(for: reminder)
        let content = ActivityContent(
            state: state,
            staleDate: reminder.scheduledAt.addingTimeInterval(30 * 60)
        )

        if let matchedActivity = Activity<CompanionActivityAttributes>.activities.first(where: {
            $0.attributes.occurrenceID == reminder.id
        }) {
            // Xcode 26.4+ imports Activity.update/end as @concurrent while Activity
            // itself is not Sendable. A MainActor-local Activity therefore triggers
            // a false-positive "sending ... risks causing data races" diagnostic.
            // Keep the escape hatch local: Jomado does not retain or touch this
            // Activity concurrently; it is used for this one awaited system call.
            nonisolated(unsafe) let existing = matchedActivity
            await existing.update(content)
            return
        }

        do {
            _ = try Activity.request(
                attributes: CompanionActivityAttributes(
                    occurrenceID: reminder.id,
                    routineID: reminder.scheduleID
                ),
                content: content,
                pushType: .token
            )
        } catch {
            // The notification remains the reliable fallback. ActivityKit failures
            // must never suppress delivery of the reminder itself.
        }
    }

    func end(_ reminder: ActiveReminder, completed: Bool) async {
        guard let matchedActivity = Activity<CompanionActivityAttributes>.activities.first(where: {
            $0.attributes.occurrenceID == reminder.id
        }) else { return }

        // Same Xcode 26.4+ ActivityKit concurrency import issue as update(_:) above.
        // This binding is intentionally scoped to the single awaited end operation.
        nonisolated(unsafe) let activity = matchedActivity

        let finalState = CompanionActivityAttributes.ContentState(
            title: completed ? "Nice work" : "Reminder closed",
            message: completed ? "Momo is proud of you 💧" : "You explicitly skipped this one.",
            taskTypeRaw: "hydration",
            mascotRaw: reminder.content.mascot.id.rawValue,
            expressionRaw: completed ? MascotExpression.celebrating.rawValue : MascotExpression.waiting.rawValue,
            scheduledAt: reminder.scheduledAt,
            completionLabel: "I drank water",
            urgencyLevel: 0
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .after(Date().addingTimeInterval(60))
        )
    }

    private static func state(for reminder: ActiveReminder) -> CompanionActivityAttributes.ContentState {
        .init(
            title: reminder.content.message.title,
            message: reminder.content.message.body,
            taskTypeRaw: "hydration",
            mascotRaw: reminder.content.mascot.id.rawValue,
            expressionRaw: reminder.content.mascot.expression.rawValue,
            scheduledAt: reminder.scheduledAt,
            completionLabel: "I drank water",
            urgencyLevel: urgencyLevel(reminder.urgency)
        )
    }

    private static func urgencyLevel(_ stage: UrgencyStage) -> Int {
        switch stage {
        case .normal: return 0
        case .lightOverdue: return 1
        case .mediumOverdue: return 2
        case .redZone: return 3
        }
    }
}
