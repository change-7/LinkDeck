import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FolderSyncWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    let store: FolderPairStore
    let showSettings: () -> Void
    @State private var isAddingPair = false
    @State private var selection: FolderPair.ID?

    init(store: FolderPairStore, showSettings: @escaping () -> Void = {}) {
        self.store = store
        self.showSettings = showSettings
    }

    var body: some View {
        Group {
            pairList
        }
        .onAppear {
            store.startRealtimeSync()
            store.syncAllOnLaunch()
            if selection == nil || !store.pairs.contains(where: { $0.id == selection }) {
                let persistedSelection = store.selectedPairID.flatMap { selectedID in
                    store.pairs.contains(where: { $0.id == selectedID }) ? selectedID : nil
                }
                selection = persistedSelection ?? store.pairs.first?.id
            }
            store.setSelectedPair(selection)
            Task { await store.refreshGitHubFreshnesses() }
        }
        .onChange(of: selection) { _, newSelection in
            store.setSelectedPair(newSelection)
            Task { await store.refreshGitHubFreshnesses() }
        }
        .tint(theme.accent)
        .controlSize(.small)
        .sheet(isPresented: $isAddingPair) {
            FolderPairEditor(store: store) { pair in
                store.add(pair)
                selection = pair.id
            }
        }
    }

    private var pairList: some View {
        HStack(spacing: 12) {
            detailContent
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            syncList
                .frame(width: 250)
                .frame(maxHeight: .infinity)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
            if let pair = selectedPair {
                NavigationStack {
                    PairDetailView(
                        pair: pair,
                        state: store.state(for: pair),
                        freshness: store.latestSide(for: pair),
                        store: store
                    )
                }
                .background(theme.panel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(AppPalette.accent)
                    Text(AppText.noFoldersYet).font(.title2.weight(.semibold))
                    Text(AppText.emptyStateDescription)
                        .foregroundStyle(.secondary)
                    Button(AppText.addFolderPair, systemImage: "plus") { isAddingPair = true }
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }

    private var syncList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppText.syncList)
                    .font(.headline)
                Spacer()
                Button(action: showSettings) {
                    Image(systemName: "gearshape")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(AppText.settings)
                .accessibilityLabel(AppText.settings)
                Button(AppText.add, systemImage: "plus") { isAddingPair = true }
                    .keyboardShortcut("n", modifiers: .command)
            }

            List {
                ForEach(store.pairs) { pair in
                    PairRow(
                        pair: pair,
                        state: store.state(for: pair),
                        isSelected: selection == pair.id,
                        onSelect: { selection = pair.id }
                    ) {
                        delete(pair)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: delete)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityIdentifier("folder-sync-list")
    }

    private var selectedPair: FolderPair? {
        store.pairs.first { $0.id == selection }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { delete(store.pairs[index]) }
    }

    private func delete(_ pair: FolderPair) {
        store.remove(pair)
        if selection == pair.id { selection = store.pairs.first?.id }
    }
}

private struct PairRow: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    let pair: FolderPair
    let state: SyncState
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text("\(pair.syncMode.title) · \(state.label)")
                        .font(.caption)
                        .foregroundStyle(isError ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? theme.accent.opacity(0.28) : theme.control,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border.opacity(0.65))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contextMenu {
            Button(AppText.delete, role: .destructive, action: onDelete)
        }
    }

    private var isError: Bool {
        if case .failed = state { return true }
        return false
    }
}

private struct GitHubEndpointRow: View {
    let title: String
    let folderPath: String?
    let isLatest: Bool
    @Binding var repositoryURL: String
    let allowsGitHubRepository: Bool
    let githubAuthState: GitHubAuthState
    let githubRepositories: [GitHubRepository]
    let githubRepositoryState: GitHubRepositoryState
    let loadGitHubRepositories: () -> Void
    let chooseFolder: () -> Void
    let saveConfiguration: () -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if allowsGitHubRepository && !repositoryURL.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                    latestLabel
                    repositorySelector
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                    latestLabel
                    if let folderPath, repositoryURL.isEmpty {
                        Text(folderPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if repositoryURL.isEmpty {
                        Button(action: chooseFolder) {
                            Image(systemName: "folder")
                                .foregroundStyle(AppPalette.accent)
                        }
                        .buttonStyle(.plain)
                        .help(AppText.folderRowHint)
                    }
                }
                if allowsGitHubRepository {
                    repositorySelector
                }
            }
        }
    }

    private var repositorySelector: some View {
        GitHubRepositorySelector(
            placeholder: title,
            repositoryURL: $repositoryURL,
            authState: githubAuthState,
            repositories: githubRepositories,
            repositoryState: githubRepositoryState,
            loadRepositories: loadGitHubRepositories,
            onSubmit: { _ = saveConfiguration() }
        )
    }

    @ViewBuilder
    private var latestLabel: some View {
        if isLatest {
            Text(AppText.latest)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppPalette.accent, in: Capsule())
        }
    }

}

private struct EndpointSummary {
    let title: String
    let name: String
    let detail: String
    let isGitHub: Bool
    let isLatest: Bool
}

private struct EndpointSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    let summary: EndpointSummary
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if summary.isGitHub {
                    GitHubMark()
                } else {
                    Image(systemName: "folder.fill")
                    .foregroundStyle(theme.accent)
                }
                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(action: onEdit) {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(AppText.changeEndpoint)
                .accessibilityLabel(AppText.changeEndpoint)
            }

            Text(summary.name)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(summary.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(theme.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(summary.isLatest ? theme.accent : theme.border, lineWidth: summary.isLatest ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GitHubMark: View {
    var body: some View {
        Group {
            if let image = NSImage(contentsOf: Bundle.module.url(forResource: "github-mark", withExtension: "png")!) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "cat.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("GitHub")
        .accessibilityHidden(true)
    }
}

private struct PairDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    let pair: FolderPair
    let state: SyncState
    let freshness: GitHubFreshness?
    let store: FolderPairStore
    @State private var folderChangeError: String?
    @State private var githubRepositoryURLForA = ""
    @State private var githubRepositoryURLForB = ""
    @State private var githubRemotePollIntervalMinutes = GitHubSyncConfiguration.defaultRemotePollIntervalMinutes
    @State private var editingEndpoint: GitHubEndpointSide?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                EndpointSummaryCard(summary: endpointSummary(for: .a)) {
                    editingEndpoint = .a
                }

                Button {
                    store.setSyncMode(pair.syncMode.next, for: pair)
                } label: {
                    Image(systemName: directionSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 48, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.accent)
                .help(AppText.syncDirection)
                .accessibilityLabel("\(AppText.syncDirection): \(pair.syncMode.title)")
                .accessibilityIdentifier("sync-direction-arrow")

                EndpointSummaryCard(summary: endpointSummary(for: .b)) {
                    editingEndpoint = .b
                }
            }

            statusRow

            if pair.githubSync == nil && pair.syncMode.isTwoWay {
                Text(AppText.twoWaySafetyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .failed(let message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let folderChangeError {
                Text(folderChangeError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if pair.folderB != nil || pair.githubSync != nil {
                SyncOptionsSection(
                    options: Binding(
                        get: { pair.options },
                        set: { store.setOptions($0, for: pair) }
                    ),
                    isRealtimeEnabled: Binding(
                        get: { pair.isRealtimeEnabled },
                        set: { store.setRealtimeEnabled($0, for: pair) }
                    ),
                    syncOnLaunch: Binding(
                        get: { pair.syncOnLaunch },
                        set: { store.setSyncOnLaunch($0, for: pair) }
                    ),
                    syncMode: pair.syncMode,
                    folderAPath: pair.folderA?.displayPath,
                    folderBPath: pair.folderB?.displayPath,
                    githubRemotePollIntervalMinutes: $githubRemotePollIntervalMinutes,
                    showsGitHubRemotePolling: isGitHubRemotePullDirection,
                    onGitHubRemotePollIntervalChange: { _ = saveGitHubConfiguration() }
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.panel)
        .navigationTitle("")
        .onAppear { loadGitHubConfiguration() }
        .onChange(of: pair.githubSync) { _, _ in loadGitHubConfiguration() }
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
        .popover(
            isPresented: Binding(
                get: { editingEndpoint != nil },
                set: { if !$0 { editingEndpoint = nil } }
            ),
            arrowEdge: .top
        ) {
            if let editingEndpoint {
                endpointEditor(for: editingEndpoint)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 18) {
            syncButton

            Divider()
                .frame(height: 30)

            HStack(spacing: 8) {
                Image(systemName: stateSymbol)
                    .foregroundStyle(isError ? .red : AppPalette.accent)
                Text(state.label)
                    .foregroundStyle(isError ? .red : .primary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text(AppText.enabled)
                Toggle(AppText.enabled, isOn: Binding(
                    get: { pair.isEnabled },
                    set: { store.setEnabled($0, for: pair) }
                ))
                .labelsHidden()
            }

            if let lastSyncedAt = pair.lastSyncedAt {
                Divider()
                    .frame(height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppText.lastSynced)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastSyncedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.callout)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var syncButton: some View {
        if pair.githubSync != nil {
            Button(AppText.githubSyncNow, systemImage: "arrow.triangle.2.circlepath") {
                guard saveGitHubConfiguration() else { return }
                guard let currentPair = store.pairs.first(where: { $0.id == pair.id }) else { return }
                Task { await store.syncToGitHub(currentPair) }
            }
            .help(AppText.githubDirectSyncDescription)
            .disabled(state == .syncing || !pair.isEnabled || githubLocalFolder == nil)
            .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            .controlSize(.large)
        } else {
            Button(AppText.syncNow, systemImage: "arrow.triangle.2.circlepath") {
                Task { await store.sync(pair) }
            }
            .disabled(state == .syncing || !pair.isEnabled || pair.syncMode.isTwoWay || pair.folderA == nil || pair.folderB == nil)
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.accent)
            .controlSize(.large)
        }
    }

    private var directionSymbol: String {
        switch pair.syncMode {
        case .aToB: "arrow.right"
        case .bToA: "arrow.left"
        case .twoWay: "arrow.left.arrow.right"
        }
    }

    private var stateSymbol: String {
        switch state {
        case .idle: "circle"
        case .syncing: "arrow.triangle.2.circlepath"
        case .waitingForFolder: "clock"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private func endpointSummary(for endpoint: GitHubEndpointSide) -> EndpointSummary {
        let title = endpoint == .a ? AppText.folderA : AppText.folderB
        if let configuration = pair.githubSync, configuration.endpointSide == endpoint {
            return EndpointSummary(
                title: title,
                name: repositoryName(configuration.repositoryURL),
                detail: configuration.repositoryURL,
                isGitHub: true,
                isLatest: isLatest(endpoint: endpoint)
            )
        }

        let folder = endpoint == .a ? pair.folderA : pair.folderB
        let path = folder?.displayPath ?? AppText.waitingForFolder
        let folderName = folder.map { URL(fileURLWithPath: $0.displayPath).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? AppText.waitingForFolder
        return EndpointSummary(
            title: title,
            name: folderName,
            detail: path,
            isGitHub: false,
            isLatest: isLatest(endpoint: endpoint)
        )
    }

    private func repositoryName(_ repositoryURL: String) -> String {
        let trimmed = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastComponent = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return lastComponent.hasSuffix(".git") ? String(lastComponent.dropLast(4)) : lastComponent
    }

    @ViewBuilder
    private func endpointEditor(for endpoint: GitHubEndpointSide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(endpoint == .a ? AppText.folderA : AppText.folderB)
                .font(.headline)

            Button(endpoint == .a ? AppText.chooseFolderA : AppText.chooseFolderB) {
                if endpoint == .a { chooseFolderA() } else { chooseFolderB() }
                editingEndpoint = nil
            }

            if allowsGitHubRepository(for: endpoint) {
                repositoryEditor(for: endpoint)
            } else {
                Text(AppText.localFolderOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func allowsGitHubRepository(for endpoint: GitHubEndpointSide) -> Bool {
        if endpoint == .a {
            return githubRepositoryURLForB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return githubRepositoryURLForA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func repositoryEditor(for endpoint: GitHubEndpointSide) -> some View {
        if endpoint == .a {
            GitHubRepositorySelector(
                placeholder: AppText.folderA,
                repositoryURL: $githubRepositoryURLForA,
                authState: store.githubAuthState,
                repositories: store.githubRepositories,
                repositoryState: store.githubRepositoryState,
                loadRepositories: { Task { await store.refreshGitHubRepositories() } },
                onSubmit: finishEndpointEditing
            )
        } else {
            GitHubRepositorySelector(
                placeholder: AppText.folderB,
                repositoryURL: $githubRepositoryURLForB,
                authState: store.githubAuthState,
                repositories: store.githubRepositories,
                repositoryState: store.githubRepositoryState,
                loadRepositories: { Task { await store.refreshGitHubRepositories() } },
                onSubmit: finishEndpointEditing
            )
        }
    }

    private func finishEndpointEditing() {
        if saveGitHubConfiguration() {
            editingEndpoint = nil
        }
    }

    private func isLatest(endpoint: GitHubEndpointSide) -> Bool {
        guard let freshness, let configuration = pair.githubSync else { return false }
        switch freshness {
        case .github:
            return configuration.endpointSide == endpoint
        case .local:
            return configuration.endpointSide != endpoint
        }
    }

    private func folderSelectionRow(
        title: String,
        path: String,
        action: @escaping () -> Void,
        dropFolder: @escaping (URL) -> String?
    ) -> some View {
        FolderSelectionRow(
            title: title,
            path: path,
            action: action,
            dropFolder: dropFolder,
            reportError: { folderChangeError = $0 }
        )
    }

    private struct FolderSelectionRow: View {
        let title: String
        let path: String
        let action: () -> Void
        let dropFolder: (URL) -> String?
        let reportError: (String?) -> Void
        @State private var isDropTargeted = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Text(title)
                    Spacer(minLength: 16)
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "folder")
                        .foregroundStyle(AppPalette.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(AppText.folderRowHint)
            .accessibilityLabel("\(title), \(AppText.changeFolder)")
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $isDropTargeted,
                perform: handleDrop
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppPalette.accent, lineWidth: 2)
                    .opacity(isDropTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }

        private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                Task { @MainActor in
                    guard let url else {
                        reportError(AppText.invalidFolderDrop)
                        return
                    }
                    var isDirectory = ObjCBool(false)
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        reportError(AppText.inputFolderIsNotDirectory(url.path))
                        return
                    }
                    reportError(dropFolder(url))
                }
            }
            return true
        }
    }

    private func chooseFolderA() {
        chooseFolder {
            githubRepositoryURLForA = ""
            let result = store.setFolderA($0, for: pair)
            if result == nil, pair.githubSync?.endpointSide == .a { store.setGitHubSync(nil, for: pair) }
            return result
        }
    }

    private func chooseFolderB() {
        chooseFolder {
            githubRepositoryURLForB = ""
            let result = store.setFolderB($0, for: pair)
            if result == nil, pair.githubSync?.endpointSide == .b { store.setGitHubSync(nil, for: pair) }
            return result
        }
    }

    private func setFolderA(_ url: URL) -> String? {
        folderChangeError = nil
        return store.setFolderA(url, for: pair)
    }

    private func setFolderB(_ url: URL) -> String? {
        folderChangeError = nil
        let result = store.setFolderB(url, for: pair)
        if result == nil { store.setGitHubSync(nil, for: pair) }
        return result
    }

    private func loadGitHubConfiguration() {
        githubRepositoryURLForA = pair.githubSync?.endpointSide == .a ? pair.githubSync?.repositoryURL ?? "" : ""
        githubRepositoryURLForB = pair.githubSync?.endpointSide == .b ? pair.githubSync?.repositoryURL ?? "" : ""
        githubRemotePollIntervalMinutes = pair.githubSync?.remotePollIntervalMinutes
            ?? GitHubSyncConfiguration.defaultRemotePollIntervalMinutes
    }

    @discardableResult
    private func saveGitHubConfiguration() -> Bool {
        let repositoryURLForA = githubRepositoryURLForA.trimmingCharacters(in: .whitespacesAndNewlines)
        let repositoryURLForB = githubRepositoryURLForB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repositoryURLForA.isEmpty || repositoryURLForB.isEmpty else {
            folderChangeError = AppText.githubBothEndpointsInvalid
            return false
        }
        guard !repositoryURLForA.isEmpty || !repositoryURLForB.isEmpty else {
            store.setGitHubSync(nil, for: pair)
            return true
        }
        let endpointSide: GitHubEndpointSide = repositoryURLForA.isEmpty ? .b : .a
        let repositoryURL = repositoryURLForA.isEmpty ? repositoryURLForB : repositoryURLForA
        do {
            try GitHubSyncService.validateRepositoryURL(repositoryURL)
        } catch {
            folderChangeError = error.localizedDescription
            return false
        }
        let hasLocalFolder = endpointSide == .a ? pair.folderB != nil : pair.folderA != nil
        guard hasLocalFolder else {
            folderChangeError = AppText.githubLocalFolderRequired
            return false
        }
        if endpointSide == .a {
            store.clearFolderA(for: pair)
        } else {
            store.clearFolderB(for: pair)
        }
        store.setGitHubSync(
            GitHubSyncConfiguration(
                repositoryURL: repositoryURL,
                isAutomaticSyncEnabled: pair.isRealtimeEnabled,
                includeHiddenFiles: pair.githubSync?.includeHiddenFiles ?? false,
                endpointSide: endpointSide,
                remotePollIntervalMinutes: githubRemotePollIntervalMinutes
            ),
            for: pair
        )
        return true
    }

    private func chooseFolder(_ update: @escaping (URL) -> String?) {
        folderChangeError = nil
        FolderPicker.chooseFolder { url in
            folderChangeError = update(url)
        }
    }

    private var isError: Bool {
        if case .failed = state { return true }
        return false
    }

    private var githubLocalFolder: FolderReference? {
        guard let configuration = pair.githubSync else { return nil }
        return configuration.endpointSide == .a ? pair.folderB : pair.folderA
    }

    private var isGitHubRemotePullDirection: Bool {
        guard let configuration = pair.githubSync else { return false }
        return configuration.endpointSide == .a ? pair.syncMode == .aToB : pair.syncMode == .bToA
    }

}
