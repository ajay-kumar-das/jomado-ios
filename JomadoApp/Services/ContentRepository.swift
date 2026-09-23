import Foundation
import JomadoCore

final class ContentRepository {
    private(set) var items: [ContentItem] = []

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "hydration", withExtension: "json", subdirectory: "Content") ?? bundle.url(forResource: "hydration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ContentItem].self, from: data) else {
            assertionFailure("Missing or invalid hydration.json")
            return
        }
        items = decoded
    }
}
