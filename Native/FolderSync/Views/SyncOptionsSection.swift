import SwiftUI

struct SyncOptionsSection: View {
    @Binding var options: SyncOptions
    @Binding var isRealtimeEnabled: Bool
    @Binding var syncOnLaunch: Bool
    @Binding var githubRemotePollIntervalMinutes: Int
    let syncMode: SyncMode
    let folderAPath: String?
    let folderBPath: String?
    let showsGitHubRemotePolling: Bool
    let onGitHubRemotePollIntervalChange: () -> Void
    @State private var isExpanded = false

    init(
        options: Binding<SyncOptions>,
        isRealtimeEnabled: Binding<Bool>,
        syncOnLaunch: Binding<Bool>,
        syncMode: SyncMode,
        folderAPath: String? = nil,
        folderBPath: String? = nil,
        githubRemotePollIntervalMinutes: Binding<Int>,
        showsGitHubRemotePolling: Bool = false,
        onGitHubRemotePollIntervalChange: @escaping () -> Void = {}
    ) {
        _options = options
        _isRealtimeEnabled = isRealtimeEnabled
        _syncOnLaunch = syncOnLaunch
        _githubRemotePollIntervalMinutes = githubRemotePollIntervalMinutes
        self.syncMode = syncMode
        self.folderAPath = folderAPath
        self.folderBPath = folderBPath
        self.showsGitHubRemotePolling = showsGitHubRemotePolling
        self.onGitHubRemotePollIntervalChange = onGitHubRemotePollIntervalChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(AppText.advancedOptions, systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)

            if isExpanded {
                AdvancedSyncOptionsView(
                    options: $options,
                    isRealtimeEnabled: $isRealtimeEnabled,
                    syncOnLaunch: $syncOnLaunch,
                    githubRemotePollIntervalMinutes: $githubRemotePollIntervalMinutes,
                    syncMode: syncMode,
                    folderAPath: folderAPath,
                    folderBPath: folderBPath,
                    showsGitHubRemotePolling: showsGitHubRemotePolling,
                    onGitHubRemotePollIntervalChange: onGitHubRemotePollIntervalChange
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AdvancedSyncOptionsView: View {
    @Binding var options: SyncOptions
    @Binding var isRealtimeEnabled: Bool
    @Binding var syncOnLaunch: Bool
    @Binding var githubRemotePollIntervalMinutes: Int
    let syncMode: SyncMode
    let folderAPath: String?
    let folderBPath: String?
    let showsGitHubRemotePolling: Bool
    let onGitHubRemotePollIntervalChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section(AppText.launchSyncSettings) {
                    Toggle(AppText.syncOnLaunch, isOn: $syncOnLaunch)
                    explanatoryText(AppText.syncOnLaunchDescription)
                }

                Section(AppText.automaticSyncSettings) {
                    if syncMode.isTwoWay {
                        Text(AppText.automaticSyncTwoWayUnavailable)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $isRealtimeEnabled) {
                                HStack(spacing: 6) {
                                    Text(AppText.enableAutomaticSync)
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.secondary)
                                        .help(AppText.waitForFilesToFinish)
                                    .accessibilityLabel(AppText.waitForFilesToFinish)
                                }
                            }
                            explanatoryText(showsGitHubRemotePolling
                                ? AppText.githubAutomaticPullDescription
                                : automaticSyncDescription)
                        }
                    }
                    if isRealtimeEnabled && !syncMode.isTwoWay {
                        VStack(alignment: .leading, spacing: 6) {
                            if showsGitHubRemotePolling {
                                Picker(AppText.githubRemotePollInterval, selection: $githubRemotePollIntervalMinutes) {
                                    ForEach(GitHubSyncConfiguration.remotePollIntervalOptions, id: \.self) { minutes in
                                        Text(AppText.githubRemotePollIntervalLabel(minutes)).tag(minutes)
                                    }
                                }
                                    .help(AppText.githubRemotePollInterval)
                                    .onChange(of: githubRemotePollIntervalMinutes) { _, _ in
                                        onGitHubRemotePollIntervalChange()
                                    }
                            } else {
                                Picker(AppText.automaticTrigger, selection: $options.automaticTrigger) {
                                    ForEach(AutomaticSyncTrigger.allCases, id: \.self) { trigger in
                                        Text(trigger.title).tag(trigger)
                                    }
                                }
                                if options.automaticTrigger == .interval {
                                    Picker(AppText.syncInterval, selection: $options.intervalMinutes) {
                                        ForEach([1, 5, 10, 15, 30, 60], id: \.self) { minutes in
                                            Text(AppText.everyMinutes(minutes)).tag(minutes)
                                        }
                                    }
                                    explanatoryText(AppText.intervalSyncDescription)
                                }
                                Picker(AppText.automaticAction, selection: $options.realtimeAction) {
                                    ForEach(RealtimeAction.allCases, id: \.self) { action in
                                        Text(action.title).tag(action)
                                    }
                                }
                                explanatoryText(automaticActionDescription)
                            }
                        }
                        .padding(.leading, 24)
                    }
                }

                Section(AppText.fileHandlingSettings) {
                    if nestedDestinationPath != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(AppText.excludeNestedDestination, isOn: $options.excludeNestedDestination)
                            explanatoryText(AppText.excludeNestedDestinationDescription)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(AppText.includeHiddenFiles, isOn: $options.includeHiddenFiles)
                        explanatoryText(AppText.includeHiddenFilesDescription)
                    }

                    if syncMode.isTwoWay {
                        Text(AppText.deleteFilesTwoWayUnavailable)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(deleteFilesTitle, isOn: $options.deleteExtraFiles)
                                .disabled(automaticTransferSelected)
                            explanatoryText(automaticTransferSelected
                                ? AppText.transferCannotDeleteExtraFiles
                                : AppText.deleteFilesDescription(sourceFolderTitle, deleteTargetTitle))
                            if options.deleteExtraFiles && !automaticTransferSelected {
                                Text(AppText.deleteFilesWarning(deleteTargetTitle, sourceFolderTitle))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Picker(AppText.maximumFileSize, selection: $options.maxFileSize) {
                            ForEach(MaxFileSize.allCases, id: \.self) { limit in
                                Text(limit.title).tag(limit)
                            }
                        }
                        explanatoryText(AppText.maximumFileSizeDescription)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { clearUnsafeTransferOption() }
        .onChange(of: isRealtimeEnabled) { _, _ in clearUnsafeTransferOption() }
        .onChange(of: options.realtimeAction) { _, _ in clearUnsafeTransferOption() }
    }

    private var automaticActionDescription: String {
        switch options.realtimeAction {
        case .sync:
            AppText.syncChangesDescription(sourceFolderTitle, destinationFolderTitle)
        case .transfer:
            AppText.transferActionDescription(sourceFolderTitle, destinationFolderTitle)
        }
    }

    private var automaticSyncDescription: String {
        switch options.automaticTrigger {
        case .fileChanges:
            syncMode == .aToB
                ? AppText.syncWhenFolderAChangesDescription
                : AppText.syncWhenFolderBChangesDescription
        case .interval:
            AppText.intervalSyncToggleDescription
        }
    }

    private func explanatoryText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nestedDestinationPath: String? {
        guard !syncMode.isTwoWay,
              let folderAPath,
              let folderBPath else { return nil }
        let sourcePath = syncMode == .aToB ? folderAPath : folderBPath
        let destinationPath = syncMode == .aToB ? folderBPath : folderAPath
        return FolderPathRelationship.relativePath(of: destinationPath, inside: sourcePath)
    }

    private var deleteFilesTitle: String {
        syncMode == .aToB ? AppText.deleteFilesOnlyInFolderB : AppText.deleteFilesOnlyInFolderA
    }

    private var deleteTargetTitle: String {
        syncMode == .aToB ? AppText.folderB : AppText.folderA
    }

    private var sourceFolderTitle: String {
        syncMode == .aToB ? AppText.folderA : AppText.folderB
    }

    private var destinationFolderTitle: String {
        syncMode == .aToB ? AppText.folderB : AppText.folderA
    }

    private var automaticTransferSelected: Bool {
        isRealtimeEnabled && options.realtimeAction == .transfer
    }

    private func clearUnsafeTransferOption() {
        if automaticTransferSelected {
            options.deleteExtraFiles = false
        }
    }
}
