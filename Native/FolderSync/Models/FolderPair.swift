import Foundation

struct FolderReference: Codable, Hashable {
    let bookmarkData: Data
    let displayPath: String

    init(bookmarkData: Data, displayPath: String) {
        self.bookmarkData = bookmarkData
        self.displayPath = displayPath
    }

    init(url: URL) throws {
        bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        displayPath = url.path
    }
}

enum SyncMode: String, Codable, CaseIterable, Hashable {
    case aToB
    case bToA
    case twoWay

    var isTwoWay: Bool { self == .twoWay }

    var next: SyncMode {
        switch self {
        case .aToB: .bToA
        case .bToA: .twoWay
        case .twoWay: .aToB
        }
    }
}

enum MaxFileSize: String, Codable, CaseIterable, Hashable {
    case unlimited
    case megabytes100
    case gigabyte
    case gigabytes5

    var rsyncValue: String? {
        switch self {
        case .unlimited: nil
        case .megabytes100: "100m"
        case .gigabyte: "1g"
        case .gigabytes5: "5g"
        }
    }
}

enum RealtimeAction: String, Codable, CaseIterable, Hashable {
    case sync
    case transfer
}

enum AutomaticSyncTrigger: String, Codable, CaseIterable, Hashable {
    case fileChanges
    case interval
}

struct SyncOptions: Codable, Hashable {
    var includeHiddenFiles: Bool
    var deleteExtraFiles: Bool
    var maxFileSize: MaxFileSize
    var realtimeAction: RealtimeAction
    var automaticTrigger: AutomaticSyncTrigger
    var intervalMinutes: Int
    var excludeNestedDestination: Bool

    init(
        includeHiddenFiles: Bool = true,
        deleteExtraFiles: Bool = false,
        maxFileSize: MaxFileSize = .unlimited,
        realtimeAction: RealtimeAction = .sync,
        automaticTrigger: AutomaticSyncTrigger = .fileChanges,
        intervalMinutes: Int = 5,
        excludeNestedDestination: Bool = false
    ) {
        self.includeHiddenFiles = includeHiddenFiles
        self.deleteExtraFiles = deleteExtraFiles
        self.maxFileSize = maxFileSize
        self.realtimeAction = realtimeAction
        self.automaticTrigger = automaticTrigger
        self.intervalMinutes = intervalMinutes
        self.excludeNestedDestination = excludeNestedDestination
    }

    private enum CodingKeys: String, CodingKey {
        case includeHiddenFiles, deleteExtraFiles, maxFileSize, realtimeAction
        case automaticTrigger, intervalMinutes, excludeNestedDestination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .includeHiddenFiles) ?? true
        deleteExtraFiles = try container.decodeIfPresent(Bool.self, forKey: .deleteExtraFiles) ?? false
        maxFileSize = try container.decodeIfPresent(MaxFileSize.self, forKey: .maxFileSize) ?? .unlimited
        realtimeAction = try container.decodeIfPresent(RealtimeAction.self, forKey: .realtimeAction) ?? .sync
        automaticTrigger = try container.decodeIfPresent(AutomaticSyncTrigger.self, forKey: .automaticTrigger) ?? .fileChanges
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 5
        excludeNestedDestination = try container.decodeIfPresent(Bool.self, forKey: .excludeNestedDestination) ?? false
    }
}

struct GitHubSyncConfiguration: Codable, Hashable {
    static let remotePollIntervalOptions = [0, 1, 5, 15, 30, 60]
    static let defaultRemotePollIntervalMinutes = 5

    var repositoryURL: String
    var commitMessage: String
    var isAutomaticSyncEnabled: Bool
    var includeHiddenFiles: Bool
    var endpointSide: GitHubEndpointSide
    var remotePollIntervalMinutes: Int

    init(
        repositoryURL: String,
        commitMessage: String = "Sync changes from FolderSync",
        isAutomaticSyncEnabled: Bool = false,
        includeHiddenFiles: Bool = false,
        endpointSide: GitHubEndpointSide = .b,
        remotePollIntervalMinutes: Int = GitHubSyncConfiguration.defaultRemotePollIntervalMinutes
    ) {
        self.repositoryURL = repositoryURL
        self.commitMessage = commitMessage
        self.isAutomaticSyncEnabled = isAutomaticSyncEnabled
        self.includeHiddenFiles = includeHiddenFiles
        self.endpointSide = endpointSide
        self.remotePollIntervalMinutes = Self.normalizedRemotePollInterval(remotePollIntervalMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case repositoryURL, commitMessage, isAutomaticSyncEnabled, includeHiddenFiles, endpointSide
        case remotePollIntervalMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryURL = try container.decodeIfPresent(String.self, forKey: .repositoryURL) ?? ""
        commitMessage = try container.decodeIfPresent(String.self, forKey: .commitMessage) ?? "Sync changes from FolderSync"
        isAutomaticSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutomaticSyncEnabled) ?? false
        includeHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .includeHiddenFiles) ?? false
        endpointSide = try container.decodeIfPresent(GitHubEndpointSide.self, forKey: .endpointSide) ?? .b
        remotePollIntervalMinutes = Self.normalizedRemotePollInterval(
            try container.decodeIfPresent(Int.self, forKey: .remotePollIntervalMinutes)
                ?? Self.defaultRemotePollIntervalMinutes
        )
    }

    private static func normalizedRemotePollInterval(_ minutes: Int) -> Int {
        remotePollIntervalOptions.contains(minutes) ? minutes : defaultRemotePollIntervalMinutes
    }
}

enum GitHubEndpointSide: String, Codable, CaseIterable, Hashable {
    case a
    case b
}

enum GitHubFreshness: Equatable {
    case local
    case github
}

struct FolderPair: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var folderA: FolderReference?
    var folderB: FolderReference?
    var syncMode: SyncMode
    var options: SyncOptions
    var isEnabled: Bool
    var isRealtimeEnabled: Bool
    var syncOnLaunch: Bool
    var lastSyncedAt: Date?
    var githubSync: GitHubSyncConfiguration?

    init(
        name: String,
        folderA: FolderReference?,
        folderB: FolderReference? = nil,
        syncMode: SyncMode = .aToB,
        options: SyncOptions = SyncOptions(),
        isRealtimeEnabled: Bool = false,
        syncOnLaunch: Bool = true,
        githubSync: GitHubSyncConfiguration? = nil
    ) {
        id = UUID()
        self.name = name
        self.folderA = folderA
        self.folderB = folderB
        self.syncMode = syncMode
        self.options = options
        isEnabled = true
        self.isRealtimeEnabled = isRealtimeEnabled
        self.syncOnLaunch = syncOnLaunch
        self.githubSync = githubSync
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, folderA, folderB, source, destination, syncMode, options, isEnabled, isRealtimeEnabled, syncOnLaunch, lastSyncedAt, githubSync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        folderA = try container.decodeIfPresent(FolderReference.self, forKey: .folderA)
            ?? container.decodeIfPresent(FolderReference.self, forKey: .source)
        folderB = try container.decodeIfPresent(FolderReference.self, forKey: .folderB)
            ?? container.decodeIfPresent(FolderReference.self, forKey: .destination)
        syncMode = try container.decodeIfPresent(SyncMode.self, forKey: .syncMode) ?? .aToB
        options = try container.decodeIfPresent(SyncOptions.self, forKey: .options) ?? SyncOptions()
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        let savedGitHubSync = try container.decodeIfPresent(GitHubSyncConfiguration.self, forKey: .githubSync)
        let savedRealtimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRealtimeEnabled) ?? false
        isRealtimeEnabled = savedRealtimeEnabled || (savedGitHubSync?.isAutomaticSyncEnabled ?? false)
        syncOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .syncOnLaunch) ?? true
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        githubSync = savedGitHubSync
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(folderA, forKey: .folderA)
        try container.encode(folderB, forKey: .folderB)
        try container.encode(syncMode, forKey: .syncMode)
        try container.encode(options, forKey: .options)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isRealtimeEnabled, forKey: .isRealtimeEnabled)
        try container.encode(syncOnLaunch, forKey: .syncOnLaunch)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        if var githubSync {
            githubSync.isAutomaticSyncEnabled = isRealtimeEnabled
            try container.encode(githubSync, forKey: .githubSync)
        }
    }
}

enum SyncState: Equatable {
    case idle
    case syncing
    case waitingForFolder
    case succeeded(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle: AppText.idle
        case .syncing: AppText.syncing
        case .waitingForFolder: AppText.waitingForFolder
        case .succeeded: AppText.completed
        case .failed: AppText.error
        }
    }
}
