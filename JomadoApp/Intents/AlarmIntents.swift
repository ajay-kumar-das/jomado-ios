import AppIntents
import Foundation

struct AcknowledgeHydrationAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Acknowledge hydration alarm"

    static let description = IntentDescription(
        "Records that the alarm was stopped without marking the hydration task complete."
    )

    static let openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            SharedAlarmEventQueue.append(
                alarmID: id,
                kind: .acknowledged
            )
        }

        return .result()
    }
}

struct OpenHydrationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open Jomado"

    static let description = IntentDescription(
        "Opens Jomado to complete the hydration action."
    )

    static let openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            SharedAlarmEventQueue.append(
                alarmID: id,
                kind: .open
            )
        }

        return .result()
    }
}
