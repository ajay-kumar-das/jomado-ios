import Foundation
import JomadoCore

final class ContentRepository {
    private(set) var items: [ContentItem] = []
    private(set) var usesFallbackContent = false
    private(set) var diagnostic = "Content has not been loaded."

    init(bundle: Bundle = .main) {
        do {
            guard let url = bundle.url(
                forResource: "hydration",
                withExtension: "json",
                subdirectory: "Content"
            ) ?? bundle.url(forResource: "hydration", withExtension: "json") else {
                throw ContentRepositoryError.missingResource
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ContentItem].self, from: data)
            try ContentCatalogValidator.validate(
                decoded,
                expectedTaskType: .hydration,
                requiredUrgencyStages: Set(UrgencyStage.allCases)
            )
            items = decoded
            diagnostic = "Loaded \(decoded.count) bundled hydration messages."
        } catch {
            items = Self.fallbackItems
            usesFallbackContent = true
            diagnostic = "Bundled content could not be loaded (\(error.localizedDescription)). Using \(items.count) safe fallback messages."
        }
    }

    private static let fallbackItems: [ContentItem] = [
        fallback(
            id: "fallback-normal",
            stage: .normal,
            title: "Water time",
            body: "Take a comfortable drink, then mark it done here.",
            expression: .hello,
            minDelay: 0,
            maxDelay: 2
        ),
        fallback(
            id: "fallback-light",
            stage: .lightOverdue,
            title: "Still waiting",
            body: "The alarm is quiet, but your hydration task is still open.",
            expression: .waiting,
            minDelay: 3,
            maxDelay: 7
        ),
        fallback(
            id: "fallback-medium",
            stage: .mediumOverdue,
            title: "Quick water break",
            body: "A few sips now are enough to keep the promise moving.",
            expression: .concerned,
            minDelay: 8,
            maxDelay: 14
        ),
        fallback(
            id: "fallback-red",
            stage: .redZone,
            title: "Hydration check",
            body: "Drink water or explicitly skip this reminder. Silencing alone never completes it.",
            expression: .urgent,
            minDelay: 15,
            maxDelay: nil
        )
    ]

    private static func fallback(
        id: String,
        stage: UrgencyStage,
        title: String,
        body: String,
        expression: MascotExpression,
        minDelay: Int,
        maxDelay: Int?
    ) -> ContentItem {
        ContentItem(
            id: id,
            version: 1,
            locale: "en",
            taskType: .hydration,
            stage: stage,
            strategy: .supportive,
            message: .init(title: title, body: body),
            mascot: .init(id: .momo, expression: expression, animation: "gentleBounce"),
            attributes: .init(energy: 2, humor: 0, pressure: 1, warmth: 5, playfulness: 2),
            context: .init(
                dayParts: [],
                urgencies: [stage],
                minDelayMinutes: minDelay,
                maxDelayMinutes: maxDelay
            ),
            selection: .init(baseWeight: 1, cooldownDays: 0),
            tags: ["fallback", "local"]
        )
    }
}

private enum ContentRepositoryError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        "hydration.json is missing from the app bundle"
    }
}
