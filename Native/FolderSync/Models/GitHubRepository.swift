import Foundation

struct GitHubRepository: Codable, Hashable, Identifiable {
    let id: Int64
    let name: String
    let fullName: String
    let htmlURL: String
    let cloneURL: String
    let description: String?
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let defaultBranch: String

    private enum CodingKeys: String, CodingKey {
        case id, name
        case fullName = "full_name"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case description
        case isPrivate = "private"
        case isFork = "fork"
        case isArchived = "archived"
        case defaultBranch = "default_branch"
    }

    var shortName: String {
        fullName.split(separator: "/", maxSplits: 1).last.map(String.init) ?? name
    }
}

struct GitHubOrganization: Codable, Hashable, Identifiable {
    let id: Int64
    let login: String

    private enum CodingKeys: String, CodingKey {
        case id, login
    }
}

enum GitHubRepositoryVisibility: String, CaseIterable, Identifiable, Equatable {
    case privateRepository = "private"
    case publicRepository = "public"

    var id: String { rawValue }
}

enum GitHubRepositoryState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum GitHubOrganizationState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
