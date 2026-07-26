import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers
import ReclaimKit

/// Exposes tasks to Spotlight (and Siri semantic search) as an `IndexedEntity`.
/// The query reads the App Group snapshot so it never needs the token or network.
struct ReclaimTaskEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Reclaim Task"

    let id: Int
    let title: String
    let priorityLabel: String?
    let notes: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    /// Enrich the Spotlight record so semantic search has real content to match.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = notes
        if let priorityLabel { attributes.keywords = [priorityLabel] }
        return attributes
    }

    static let defaultQuery = ReclaimTaskEntityQuery()
}

extension ReclaimTaskEntity {
    init(snapshot: SharedStore.TaskSnapshot) {
        self.init(id: snapshot.id, title: snapshot.title, priorityLabel: snapshot.priority, notes: nil)
    }
}

struct ReclaimTaskEntityQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [ReclaimTaskEntity] {
        let wanted = Set(identifiers)
        return SharedStore.loadSnapshot()
            .filter { wanted.contains($0.id) }
            .map(ReclaimTaskEntity.init(snapshot:))
    }

    func suggestedEntities() async throws -> [ReclaimTaskEntity] {
        SharedStore.loadSnapshot().map(ReclaimTaskEntity.init(snapshot:))
    }
}

/// Pushes current tasks into the on-device Spotlight index. Deduped by entity id,
/// so calling it after every refresh is cheap.
enum TaskSpotlight {
    static func index(_ tasks: [ReclaimTask]) {
        guard #available(iOS 18, *) else { return }
        let entities = tasks
            .filter { !$0.isFinished }
            .map { ReclaimTaskEntity(id: $0.id, title: $0.displayTitle,
                                     priorityLabel: $0.priorityEnum?.short, notes: $0.notes) }
        Task {
            try? await CSSearchableIndex.default().indexAppEntities(entities)
        }
    }
}
