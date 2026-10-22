import Foundation

enum GitSyncLinkPosition: String, Codable, CaseIterable, Hashable {
    case before, after
}

struct GitSyncLink: Codable, Hashable {
    var syncID: UUID
    var position: GitSyncLinkPosition
    var direction: GitSyncDirection?
}
