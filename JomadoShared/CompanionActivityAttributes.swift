import ActivityKit
import Foundation

struct CompanionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let message: String
        let taskTypeRaw: String
        let mascotRaw: String
        let expressionRaw: String
        let scheduledAt: Date
        let completionLabel: String
        let urgencyLevel: Int
    }

    let occurrenceID: UUID
    let routineID: UUID?
}
