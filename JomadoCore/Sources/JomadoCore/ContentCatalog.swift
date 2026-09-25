import Foundation

public enum ContentCatalogValidationError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case duplicateID(String)
    case blankMessage(String)
    case inconsistentStage(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The hydration content catalog is empty."
        case .duplicateID(let id):
            return "The hydration content catalog contains duplicate ID \(id)."
        case .blankMessage(let id):
            return "Hydration content \(id) has an empty title or message."
        case .inconsistentStage(let id):
            return "Hydration content \(id) does not include its own urgency stage in its context."
        }
    }
}

public enum ContentCatalogValidator {
    public static func validate(_ items: [ContentItem]) throws {
        guard !items.isEmpty else { throw ContentCatalogValidationError.empty }
        var ids = Set<String>()
        for item in items {
            guard ids.insert(item.id).inserted else {
                throw ContentCatalogValidationError.duplicateID(item.id)
            }
            guard !item.message.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.message.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentCatalogValidationError.blankMessage(item.id)
            }
            guard item.context.urgencies.contains(item.stage) else {
                throw ContentCatalogValidationError.inconsistentStage(item.id)
            }
        }
    }
}
