import Foundation
import Observation
import AppKit

@MainActor @Observable
final class FolderPairStore {
    private enum Key {
        static let pairs = "folderPairs"
        static let logs = "syncLogs"
        static let appSettings = "appSettings"
        static let selectedPairID = "selectedFolderPairID"
    }

    private static let storage = UserDefaults(suiteName: "com.pdg.FolderSync") ?? .standard

    var pairs: [FolderPair] = []
    var selectedPairID: FolderPair.ID?
    var logs: [SyncLogEntry] = []
    var states: [UUID: SyncState] = [:]
    var appSettings = AppSettings()
    var githubAuthState: GitHubAuthState = .unknown
    var githubRepositories: [GitHubRepository] = []
    var githubRepositoryState: GitHubRepositoryState = .idle
    private var watchers: [UUID: FolderWatcher] = [:]
    private var githubWatchers: [UUID: FolderWatcher] = [:]
    private var githubRemotePollTasks: [UUID: Task<Void, Never>] = [:]
    private var intervalTasks: [UUID: Task<Void, Never>] = [:]
    private var didRunLaunchSync = false
    private var didStartRealtimeSync = false
    var githubStatuses: [UUID: GitHubRepositoryStatus] = [:]
    var githubFreshnesses: [UUID: GitHubFreshness] = [:]
    private let githubService = GitHubSyncService()
    private let githubAuthService = GitHubAuthService()
    @ObservationIgnored private var volumeMonitor: VolumeMonitor?

    init() {
        Self.migrateWorkspaceDefaultsIfNeeded()
        pairs = Self.load([FolderPair].self, key: Key.pairs) ?? []
        selectedPairID = Self.loadSelectedPairID()
        logs = Self.load([SyncLogEntry].self, key: Key.logs) ?? []
        appSettings = Self.load(AppSettings.self, key: Key.appSettings) ?? AppSettings()
        volumeMonitor = VolumeMonitor { [weak self] in self?.resumeWaitingPairs() }
    }

    func add(_ pair: FolderPair) {
        pairs.append(pair)
        if selectedPairID == nil {
            setSelectedPair(pair.id)
        }
        savePairs()
        configureWatcher(for: pair)
        configureGitHubWatcher(for: pair)
    }

    func remove(_ pair: FolderPair) {
        watchers[pair.id]?.stop()
        watchers[pair.id] = nil
        githubWatchers[pair.id]?.stop()
        githubWatchers[pair.id] = nil
        githubRemotePollTasks[pair.id]?.cancel()
        githubRemotePollTasks[pair.id] = nil
        intervalTasks[pair.id]?.cancel()
        intervalTasks[pair.id] = nil
        pairs.removeAll { $0.id == pair.id }
        states[pair.id] = nil
        githubStatuses[pair.id] = nil
        githubFreshnesses[pair.id] = nil
        if selectedPairID == pair.id {
            setSelectedPair(pairs.first?.id)
        }
        savePairs()
    }

    func setSelectedPair(_ pairID: FolderPair.ID?) {
        guard pairID == nil || pairs.contains(where: { $0.id == pairID }) else { return }
        selectedPairID = pairID
        saveSelectedPairID()
    }
    func refreshSelectedPair() {
        selectedPairID = Self.loadSelectedPairID()
    }

    func sync(_ pair: FolderPair) async {
        await sync(
            pair,
            waitsForStableInput: appSettings.waitsForFileOperations,
            appliesRealtimeAction: false
        )
    }

    private func sync(
        _ pair: FolderPair,
        waitsForStableInput: Bool,
        appliesRealtimeAction: Bool
    ) async {
        guard state(for: pair) != .syncing else { return }
        states[pair.id] = .syncing
        appendLog(level: .info, event: SyncLogMessage(kind: .syncStarted, pairName: pair.name))
        do {
            guard let folderAReference = pair.folderA,
                  let folderBReference = pair.folderB else {
                throw SyncError.outputFolderIsNotDirectory(AppText.folderB)
            }
            let folderA = try BookmarkManager.resolve(folderAReference)
            let folderB = try BookmarkManager.resolve(folderBReference)
            guard !pair.syncMode.isTwoWay else { throw SyncError.twoWayRequiresConflictHandling }
            let fromFolder = pair.syncMode == .aToB ? folderA : folderB
            let toFolder = pair.syncMode == .aToB ? folderB : folderA
            let fromReference = pair.syncMode == .aToB ? folderAReference : folderBReference
            let toReference = pair.syncMode == .aToB ? folderBReference : folderAReference
            let hasFromAccess = fromFolder.startAccessingSecurityScopedResource()
            guard hasFromAccess else { throw BookmarkError.accessDenied(fromReference.displayPath) }
            defer { if hasFromAccess { fromFolder.stopAccessingSecurityScopedResource() } }
            if waitsForStableInput {
                try await FolderStabilityMonitor.waitUntilStable(at: fromFolder)
            }
            let hasToAccess = toFolder.startAccessingSecurityScopedResource()
            guard hasToAccess else { throw BookmarkError.accessDenied(toReference.displayPath) }
            defer { if hasToAccess { toFolder.stopAccessingSecurityScopedResource() } }
            if appliesRealtimeAction && pair.options.realtimeAction == .transfer {
                try await RsyncRunner().transfer(from: fromFolder, to: toFolder, options: pair.options)
            } else {
                try await RsyncRunner().copy(from: fromFolder, to: toFolder, options: pair.options)
            }
            let completedAt = Date.now
            states[pair.id] = .succeeded(completedAt)
            if let index = pairs.firstIndex(where: { $0.id == pair.id }) {
                pairs[index].lastSyncedAt = completedAt
                savePairs()
            }
            appendLog(level: .info, event: SyncLogMessage(kind: .syncCompleted, pairName: pair.name))
        } catch {
            if case BookmarkError.inaccessibleFolder = error, isRequiredFolderUnavailable(pair) {
                states[pair.id] = .waitingForFolder
                appendLog(level: .info, event: SyncLogMessage(kind: .waitingForFolder, pairName: pair.name))
            } else {
                states[pair.id] = .failed(error.localizedDescription)
                appendLog(level: .error, event: SyncLogMessage(kind: .syncFailed, pairName: pair.name))
            }
        }
    }

    func state(for pair: FolderPair) -> SyncState {
        states[pair.id] ?? .idle
    }

    func setRealtimeEnabled(_ isEnabled: Bool, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].isRealtimeEnabled = isEnabled
        pairs[index].githubSync?.isAutomaticSyncEnabled = isEnabled
        savePairs()
        configureWatcher(for: pairs[index])
        configureGitHubWatcher(for: pairs[index])
    }

    func setEnabled(_ isEnabled: Bool, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].isEnabled = isEnabled
        savePairs()
        configureWatcher(for: pairs[index])
        configureGitHubWatcher(for: pairs[index])
    }

    func setSyncOnLaunch(_ isEnabled: Bool, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].syncOnLaunch = isEnabled
        savePairs()
    }

    func setSyncMode(_ syncMode: SyncMode, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].syncMode = syncMode
        if syncMode.isTwoWay {
            pairs[index].isRealtimeEnabled = false
        }
        savePairs()
        configureWatcher(for: pairs[index])
        configureGitHubWatcher(for: pairs[index])
    }

    @discardableResult
    func setFolderA(_ url: URL, for pair: FolderPair) -> String? {
        setFolder(
            makeReference: { try FolderReference(url: url) },
            keyPath: \FolderPair.folderA,
            for: pair
        )
    }

    @discardableResult
    func setFolderB(_ url: URL, for pair: FolderPair) -> String? {
        setFolder(
            makeReference: { try FolderReference(url: url) },
            keyPath: \FolderPair.folderB,
            for: pair
        )
    }

    func clearFolderB(for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].folderB = nil
        savePairs()
        configureWatcher(for: pairs[index])
        configureGitHubWatcher(for: pairs[index])
    }

    func clearFolderA(for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].folderA = nil
        savePairs()
        configureWatcher(for: pairs[index])
        configureGitHubWatcher(for: pairs[index])
    }

    func setIncludeHiddenFiles(_ isIncluded: Bool, for pair: FolderPair) {
        updateOptions(for: pair) { $0.includeHiddenFiles = isIncluded }
    }

    func setDeleteExtraFiles(_ isEnabled: Bool, for pair: FolderPair) {
        updateOptions(for: pair) { $0.deleteExtraFiles = isEnabled }
    }

    func setMaxFileSize(_ maxFileSize: MaxFileSize, for pair: FolderPair) {
        updateOptions(for: pair) { $0.maxFileSize = maxFileSize }
    }

    func setOptions(_ options: SyncOptions, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].options = options
        savePairs()
        configureWatcher(for: pairs[index])
        configureGitHubWatcher(for: pairs[index])
    }

    func setGitHubSync(_ configuration: GitHubSyncConfiguration?, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].githubSync = configuration
        savePairs()
        configureGitHubWatcher(for: pairs[index])
        if configuration != nil {
            Task {
                await refreshGitHubStatus(pairs[index])
                await refreshGitHubFreshness(pairs[index])
            }
        } else {
            githubStatuses[pair.id] = nil
            githubFreshnesses[pair.id] = nil
        }
    }

    func syncToGitHub(_ pair: FolderPair) async {
        guard let configuration = pair.githubSync else { return }
        guard state(for: pair) != .syncing else { return }
        states[pair.id] = .syncing
        appendLog(level: .info, event: SyncLogMessage(kind: .githubSyncStarted, pairName: pair.name))
        do {
            guard try await githubAuthService.isAuthenticated() else {
                throw GitHubSyncError.authenticationRequired
            }
            guard let localReference = githubLocalReference(for: pair, configuration: configuration) else {
                throw SyncError.outputFolderIsNotDirectory(configuration.endpointSide == .a ? AppText.folderB : AppText.folderA)
            }
            let folder = try BookmarkManager.resolve(localReference)
            let hasAccess = folder.startAccessingSecurityScopedResource()
            guard hasAccess else { throw BookmarkError.accessDenied(localReference.displayPath) }
            defer { folder.stopAccessingSecurityScopedResource() }
            if appSettings.waitsForFileOperations {
                try await FolderStabilityMonitor.waitUntilStable(at: folder)
            }
            let mirror = githubMirror(for: pair)
            let result: GitHubSyncResult
            if isGitHubPushDirection(for: pair, configuration: configuration) {
                result = try await githubService.sync(source: folder, configuration: configuration, mirror: mirror)
            } else {
                result = try await githubService.pull(target: folder, configuration: configuration, mirror: mirror)
            }
            githubStatuses[pair.id] = try await githubService.status(at: mirror)
            let completedAt = Date.now
            states[pair.id] = .succeeded(completedAt)
            updateLastSynced(at: completedAt, for: pair)
            if let currentPair = pairs.first(where: { $0.id == pair.id }) {
                await refreshGitHubFreshness(currentPair)
            }
            if result.didPush {
                appendLog(level: .info, event: SyncLogMessage(kind: .githubPushCompleted, pairName: pair.name))
            }
        } catch {
            states[pair.id] = .failed(error.localizedDescription)
            appendLog(level: .error, event: SyncLogMessage(kind: .githubSyncFailed, pairName: pair.name))
        }
    }

    func syncLocalWorkspaceToGitHubForMCP(_ pairID: UUID) async -> SyncState? {
        guard let pair = pairs.first(where: { $0.id == pairID }),
              let configuration = pair.githubSync,
              isGitHubPushDirection(for: pair, configuration: configuration) else {
            return nil
        }
        await syncToGitHub(pair)
        return state(for: pair)
    }

    func syncGitHubToLocalForMCP(_ pairID: UUID) async -> SyncState? {
        guard let pair = pairs.first(where: { $0.id == pairID }),
              let configuration = pair.githubSync,
              !isGitHubPushDirection(for: pair, configuration: configuration) else {
            return nil
        }
        await syncToGitHub(pair)
        return state(for: pair)
    }

    func refreshGitHubStatus(_ pair: FolderPair) async {
        guard pair.githubSync != nil else { return }
        do {
            githubStatuses[pair.id] = try await githubService.status(at: githubMirror(for: pair))
        } catch {
            githubStatuses[pair.id] = nil
        }
    }

    func latestSide(for pair: FolderPair) -> GitHubFreshness? {
        githubFreshnesses[pair.id]
    }

    func refreshGitHubFreshness(_ pair: FolderPair) async {
        guard let configuration = pair.githubSync,
              let localReference = githubLocalReference(for: pair, configuration: configuration) else {
            githubFreshnesses[pair.id] = nil
            return
        }

        do {
            let folder = try BookmarkManager.resolve(localReference)
            let hasAccess = folder.startAccessingSecurityScopedResource()
            guard hasAccess else {
                githubFreshnesses[pair.id] = nil
                return
            }
            defer { folder.stopAccessingSecurityScopedResource() }
            let currentPair = pairs.first(where: { $0.id == pair.id }) ?? pair
            githubFreshnesses[pair.id] = try await githubService.freshness(
                localFolder: folder,
                mirror: githubMirror(for: pair),
                since: currentPair.lastSyncedAt,
                includeHiddenFiles: configuration.includeHiddenFiles
            )
        } catch {
            githubFreshnesses[pair.id] = nil
        }
    }

    func refreshGitHubFreshnesses() async {
        for pair in pairs where pair.githubSync != nil {
            await refreshGitHubFreshness(pair)
        }
    }

    func refreshGitHubAuthStatus() async {
        githubAuthState = .checking
        do {
            let isAuthenticated = try await githubAuthService.isAuthenticated()
            githubAuthState = isAuthenticated ? .loggedIn : .loggedOut
            if !isAuthenticated {
                githubRepositories = []
                githubRepositoryState = .idle
            }
        } catch {
            githubAuthState = .failed(error.localizedDescription)
        }
    }

    func refreshGitHubRepositories() async {
        guard githubRepositoryState != .loading else { return }
        githubRepositoryState = .loading
        do {
            guard try await githubAuthService.isAuthenticated() else {
                githubAuthState = .loggedOut
                githubRepositories = []
                githubRepositoryState = .failed(AppText.githubRepositoryLoginRequired)
                return
            }
            githubAuthState = .loggedIn
            githubRepositories = try await githubAuthService.listRepositories()
            githubRepositoryState = .loaded
        } catch {
            githubRepositoryState = .failed(error.localizedDescription)
        }
    }

    func addGitHubRepository(_ repository: GitHubRepository) {
        githubRepositories = sortedGitHubRepositories(
            githubRepositories.filter { $0.id != repository.id } + [repository]
        )
        githubRepositoryState = .loaded
    }

    func updateGitHubRepository(_ previous: GitHubRepository, with updated: GitHubRepository) async {
        githubRepositories = sortedGitHubRepositories(
            githubRepositories.filter { $0.id != previous.id } + [updated]
        )

        let previousIdentity = GitHubSyncService.repositoryIdentity(previous.cloneURL)
        for index in pairs.indices {
            guard let configuration = pairs[index].githubSync,
                  GitHubSyncService.repositoryIdentity(configuration.repositoryURL) == previousIdentity else {
                continue
            }
            pairs[index].githubSync?.repositoryURL = updated.cloneURL
            try? await githubService.updateRemoteURL(
                repositoryURL: updated.cloneURL,
                at: githubMirror(for: pairs[index])
            )
            configureGitHubWatcher(for: pairs[index])
        }
        savePairs()
    }

    func loginToGitHub() async {
        githubAuthState = .loggingIn
        guard NSWorkspace.shared.open(GitHubAuthBrowser.deviceURL) else {
            githubAuthState = .failed(AppText.githubBrowserOpenFailed)
            return
        }
        do {
            try await githubAuthService.login()
            githubAuthState = try await githubAuthService.isAuthenticated() ? .loggedIn : .loggedOut
            githubRepositories = []
            githubRepositoryState = .idle
        } catch {
            githubAuthState = .failed(error.localizedDescription)
        }
    }

    func setWaitsForFileOperations(_ waits: Bool) {
        appSettings.waitsForFileOperations = waits
        saveAppSettings()
    }

    func startRealtimeSync() {
        guard !didStartRealtimeSync else { return }
        didStartRealtimeSync = true
        volumeMonitor?.start()
        pairs.forEach {
            configureWatcher(for: $0)
            configureGitHubWatcher(for: $0)
        }
        Task { await refreshGitHubFreshnesses() }
    }

    func syncAllOnLaunch() {
        guard !didRunLaunchSync else { return }
        didRunLaunchSync = true

        for pair in pairs where pair.isEnabled && pair.syncOnLaunch && !pair.syncMode.isTwoWay {
            if let configuration = pair.githubSync {
                guard githubLocalReference(for: pair, configuration: configuration) != nil else { continue }
            } else {
                guard pair.folderA != nil, pair.folderB != nil else { continue }
            }
            Task { @MainActor [weak self] in
                guard let self,
                      let currentPair = self.pairs.first(where: { $0.id == pair.id }) else { return }
                if currentPair.githubSync != nil {
                    await self.syncToGitHub(currentPair)
                } else {
                    await self.sync(currentPair)
                }
            }
        }
    }

    private func resumeWaitingPairs() {
        for pair in pairs where state(for: pair) == .waitingForFolder {
            Task {
                await sync(
                    pair,
                    waitsForStableInput: appSettings.waitsForFileOperations,
                    appliesRealtimeAction: pair.isRealtimeEnabled
                )
            }
        }
    }

    private func isRequiredFolderUnavailable(_ pair: FolderPair) -> Bool {
        do {
            guard let folderA = pair.folderA, let folderB = pair.folderB else { return false }
            _ = try BookmarkManager.resolve(pair.syncMode == .aToB ? folderA : folderB)
            return false
        } catch BookmarkError.inaccessibleFolder {
            return true
        } catch {
            return false
        }
    }

    private func configureWatcher(for pair: FolderPair) {
        watchers[pair.id]?.stop()
        watchers[pair.id] = nil
        intervalTasks[pair.id]?.cancel()
        intervalTasks[pair.id] = nil
        guard pair.isEnabled, pair.isRealtimeEnabled, !pair.syncMode.isTwoWay else { return }

        if pair.options.automaticTrigger == .interval {
            configureIntervalSync(for: pair)
            return
        }

        do {
            guard let folderA = pair.folderA, let folderB = pair.folderB else { return }
            let watchedFolder = try BookmarkManager.resolve(pair.syncMode == .aToB ? folderA : folderB)
            let pairID = pair.id
            let watcher = FolderWatcher(folder: watchedFolder) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let currentPair = self.pairs.first(where: { $0.id == pairID }) else { return }
                    await self.sync(
                        currentPair,
                        waitsForStableInput: self.appSettings.waitsForFileOperations,
                        appliesRealtimeAction: true
                    )
                }
            }
            guard watcher.start() else {
                appendLog(level: .error, event: SyncLogMessage(kind: .realtimeMonitoringFailed, pairName: pair.name))
                return
            }
            watchers[pair.id] = watcher
            appendLog(level: .info, event: SyncLogMessage(kind: .realtimeMonitoringStarted, pairName: pair.name))
        } catch {
            appendLog(level: .error, event: SyncLogMessage(kind: .realtimeMonitoringUnavailable, pairName: pair.name))
        }
    }

    private func configureGitHubWatcher(for pair: FolderPair) {
        githubWatchers[pair.id]?.stop()
        githubWatchers[pair.id] = nil
        githubRemotePollTasks[pair.id]?.cancel()
        githubRemotePollTasks[pair.id] = nil
        guard pair.isEnabled, pair.isRealtimeEnabled else { return }

        guard let configuration = pair.githubSync, !pair.syncMode.isTwoWay else { return }

        if !isGitHubPushDirection(for: pair, configuration: configuration) {
            configureGitHubRemotePolling(for: pair, intervalMinutes: configuration.remotePollIntervalMinutes)
            return
        }

        if pair.options.automaticTrigger == .interval {
            configureGitHubIntervalSync(for: pair, intervalMinutes: pair.options.intervalMinutes)
            return
        }

        guard let localReference = githubLocalReference(for: pair, configuration: configuration) else { return }

        do {
            let folder = try BookmarkManager.resolve(localReference)
            let pairID = pair.id
            let watcher = FolderWatcher(folder: folder) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let currentPair = self.pairs.first(where: { $0.id == pairID }) else { return }
                    await self.syncToGitHub(currentPair)
                }
            }
            guard watcher.start() else {
                appendLog(level: .error, event: SyncLogMessage(kind: .githubMonitoringFailed, pairName: pair.name))
                return
            }
            githubWatchers[pair.id] = watcher
            appendLog(level: .info, event: SyncLogMessage(kind: .githubMonitoringStarted, pairName: pair.name))
        } catch {
            appendLog(level: .error, event: SyncLogMessage(kind: .githubMonitoringFailed, pairName: pair.name))
        }
    }

    private func configureGitHubRemotePolling(for pair: FolderPair, intervalMinutes: Int) {
        let pairID = pair.id
        guard intervalMinutes > 0 else { return }
        let intervalNanoseconds = UInt64(max(intervalMinutes, 1)) * 60 * 1_000_000_000
        githubRemotePollTasks[pairID] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled,
                      let currentPair = self.pairs.first(where: { $0.id == pairID }) else { return }
                await self.syncToGitHub(currentPair)
            }
        }
        appendLog(level: .info, event: SyncLogMessage(kind: .githubMonitoringStarted, pairName: pair.name))
    }

    private func configureGitHubIntervalSync(for pair: FolderPair, intervalMinutes: Int) {
        let pairID = pair.id
        let intervalNanoseconds = UInt64(max(intervalMinutes, 1)) * 60 * 1_000_000_000
        githubRemotePollTasks[pairID] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled,
                      let currentPair = self.pairs.first(where: { $0.id == pairID }) else { return }
                await self.syncToGitHub(currentPair)
            }
        }
        appendLog(level: .info, event: SyncLogMessage(kind: .githubMonitoringStarted, pairName: pair.name))
    }

    private func configureIntervalSync(for pair: FolderPair) {
        let pairID = pair.id
        let intervalNanoseconds = UInt64(max(pair.options.intervalMinutes, 1)) * 60 * 1_000_000_000
        intervalTasks[pairID] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled,
                      let currentPair = self.pairs.first(where: { $0.id == pairID }) else { return }
                await self.sync(
                    currentPair,
                    waitsForStableInput: self.appSettings.waitsForFileOperations,
                    appliesRealtimeAction: true
                )
            }
        }
        appendLog(level: .info, event: SyncLogMessage(kind: .realtimeMonitoringStarted, pairName: pair.name))
    }

    private func appendLog(level: SyncLogLevel, event: SyncLogMessage) {
        logs.insert(SyncLogEntry(level: level, event: event), at: 0)
        logs = Array(logs.prefix(1_000))
        saveLogs()
    }

    private func updateOptions(for pair: FolderPair, _ update: (inout SyncOptions) -> Void) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        update(&pairs[index].options)
        savePairs()
    }

    private func setFolder(
        makeReference: () throws -> FolderReference,
        keyPath: WritableKeyPath<FolderPair, FolderReference?>,
        for pair: FolderPair
    ) -> String? {
        do {
            let reference = try makeReference()
            guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return nil }
            pairs[index][keyPath: keyPath] = reference
            states[pair.id] = .idle
            savePairs()
            configureWatcher(for: pairs[index])
            configureGitHubWatcher(for: pairs[index])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func savePairs() { Self.save(pairs, key: Key.pairs) }
    private func saveLogs() { Self.save(logs, key: Key.logs) }
    private func saveAppSettings() { Self.save(appSettings, key: Key.appSettings) }

    private func saveSelectedPairID() {
        if let selectedPairID {
            Self.storage.set(selectedPairID.uuidString, forKey: Key.selectedPairID)
        } else {
            Self.storage.removeObject(forKey: Key.selectedPairID)
        }
    }

    private func sortedGitHubRepositories(_ repositories: [GitHubRepository]) -> [GitHubRepository] {
        repositories.sorted {
            $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
        }
    }

    private func updateLastSynced(at date: Date, for pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index].lastSyncedAt = date
        savePairs()
    }


    private func githubMirror(for pair: FolderPair) -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appending(path: "FolderSync/GitHubMirrors", directoryHint: .isDirectory)
            .appending(path: pair.id.uuidString, directoryHint: .isDirectory)
    }

    private func githubLocalReference(
        for pair: FolderPair,
        configuration: GitHubSyncConfiguration
    ) -> FolderReference? {
        configuration.endpointSide == .a ? pair.folderB : pair.folderA
    }

    private func isGitHubPushDirection(
        for pair: FolderPair,
        configuration: GitHubSyncConfiguration
    ) -> Bool {
        configuration.endpointSide == .b ? pair.syncMode == .aToB : pair.syncMode == .bToA
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = storage.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func loadSelectedPairID() -> FolderPair.ID? {
        guard let value = storage.string(forKey: Key.selectedPairID) else { return nil }
        return UUID(uuidString: value)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        storage.set(data, forKey: key)
    }

    private static func migrateWorkspaceDefaultsIfNeeded() {
        let legacyDefaults = UserDefaults.standard
        for key in [Key.pairs, Key.logs, Key.appSettings, Key.selectedPairID] {
            guard storage.object(forKey: key) == nil,
                  let value = legacyDefaults.object(forKey: key) else { continue }
            storage.set(value, forKey: key)
        }
    }
}
