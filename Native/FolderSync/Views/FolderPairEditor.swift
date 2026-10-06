import SwiftUI

struct FolderPairEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: FolderPairStore?
    let showsCancel: Bool
    let onSave: (FolderPair) -> Void

    @State private var name = ""
    @State private var folderAURL: URL?
    @State private var folderBURL: URL?
    @State private var syncMode: SyncMode = .aToB
    @State private var options = SyncOptions()
    @State private var isRealtimeEnabled = false
    @State private var syncOnLaunch = true
    @State private var githubRemotePollIntervalMinutes = GitHubSyncConfiguration.defaultRemotePollIntervalMinutes
    @State private var githubRepositoryURLForA = ""
    @State private var githubRepositoryURLForB = ""
    @State private var errorMessage: String?

    init(store: FolderPairStore? = nil, showsCancel: Bool = true, onSave: @escaping (FolderPair) -> Void) {
        self.store = store
        self.showsCancel = showsCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppText.newFolderPair).font(.title2)
            Form {
                TextField(AppText.name, text: $name, prompt: Text(AppText.namePrompt))
                SyncDirectionPicker(selection: $syncMode)
                FolderSelectionStrip(
                    mode: syncMode,
                    folderAURL: folderAURL,
                    folderBURL: folderBURL,
                    githubRepositoryURLForA: $githubRepositoryURLForA,
                    githubRepositoryURLForB: $githubRepositoryURLForB,
                    githubAuthState: store?.githubAuthState ?? .unknown,
                    githubRepositories: store?.githubRepositories ?? [],
                    githubRepositoryState: store?.githubRepositoryState ?? .idle,
                    loadGitHubRepositories: {
                        guard let store else { return }
                        Task { await store.refreshGitHubRepositories() }
                    },
                    chooseFolderA: chooseFolderA,
                    chooseFolderB: chooseFolderB,
                    clearFolderA: { folderAURL = nil },
                    clearFolderB: { folderBURL = nil }
                )
                SyncOptionsSection(
                    options: $options,
                    isRealtimeEnabled: $isRealtimeEnabled,
                    syncOnLaunch: $syncOnLaunch,
                    syncMode: syncMode,
                    folderAPath: folderAURL?.path,
                    folderBPath: folderBURL?.path,
                    githubRemotePollIntervalMinutes: $githubRemotePollIntervalMinutes
                )
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                if showsCancel {
                    Button(AppText.cancel) { dismiss() }
                }
                Button(AppText.add) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 500)
        .onChange(of: githubRepositoryURLForA) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                githubRepositoryURLForB = ""
            }
        }
        .onChange(of: githubRepositoryURLForB) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                githubRepositoryURLForA = ""
            }
        }
    }

    private func chooseFolderA() {
        errorMessage = nil
        FolderPicker.chooseFolder { url in
            folderAURL = url
            githubRepositoryURLForA = ""
        }
    }

    private func chooseFolderB() {
        errorMessage = nil
        FolderPicker.chooseFolder { url in
            folderBURL = url
            githubRepositoryURLForB = ""
        }
    }

    private func save() {
        let repositoryURLForA = githubRepositoryURLForA.trimmingCharacters(in: .whitespacesAndNewlines)
        let repositoryURLForB = githubRepositoryURLForB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(repositoryURLForA.isEmpty && repositoryURLForB.isEmpty && (folderAURL == nil || folderBURL == nil)) else { return }
        guard repositoryURLForA.isEmpty || repositoryURLForB.isEmpty else {
            errorMessage = AppText.githubBothEndpointsInvalid
            return
        }
        do {
            let folderA: FolderReference?
            let folderB: FolderReference?
            let savedSyncMode: SyncMode
            let githubSync: GitHubSyncConfiguration?

            if !repositoryURLForA.isEmpty {
                try GitHubSyncService.validateRepositoryURL(repositoryURLForA)
                guard let folderBURL else {
                    errorMessage = AppText.githubLocalFolderRequired
                    return
                }
                folderA = nil
                folderB = try FolderReference(url: folderBURL)
                savedSyncMode = syncMode == .twoWay ? .aToB : syncMode
                githubSync = GitHubSyncConfiguration(
                    repositoryURL: repositoryURLForA,
                    isAutomaticSyncEnabled: isRealtimeEnabled,
                    endpointSide: .a,
                    remotePollIntervalMinutes: githubRemotePollIntervalMinutes
                )
            } else if !repositoryURLForB.isEmpty {
                try GitHubSyncService.validateRepositoryURL(repositoryURLForB)
                guard let folderAURL else {
                    errorMessage = AppText.githubLocalFolderRequired
                    return
                }
                folderA = try FolderReference(url: folderAURL)
                folderB = nil
                savedSyncMode = syncMode == .twoWay ? .aToB : syncMode
                githubSync = GitHubSyncConfiguration(
                    repositoryURL: repositoryURLForB,
                    isAutomaticSyncEnabled: isRealtimeEnabled,
                    endpointSide: .b,
                    remotePollIntervalMinutes: githubRemotePollIntervalMinutes
                )
            } else {
                folderA = try folderAURL.map(FolderReference.init(url:))
                folderB = try folderBURL.map(FolderReference.init(url:))
                savedSyncMode = syncMode
                githubSync = nil
            }

            let pair = FolderPair(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                folderA: folderA,
                folderB: folderB,
                syncMode: savedSyncMode,
                options: options,
                isRealtimeEnabled: isRealtimeEnabled,
                syncOnLaunch: syncOnLaunch,
                githubSync: githubSync
            )
            onSave(pair)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRepositoryForA = !githubRepositoryURLForA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRepositoryForB = !githubRepositoryURLForB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCompleteLocalPair = folderAURL != nil && folderBURL != nil
        let hasGitHubPair = (hasRepositoryForA && folderBURL != nil) || (hasRepositoryForB && folderAURL != nil)
        return hasName && !(hasRepositoryForA && hasRepositoryForB) && (hasCompleteLocalPair || hasGitHubPair)
    }

}
