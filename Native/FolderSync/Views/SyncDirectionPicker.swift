import SwiftUI

struct SyncDirectionPicker: View {
    @Binding var selection: SyncMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(AppText.syncDirection)
                    .fixedSize()
                Button(selection.title) {
                    selection = selection.next
                }
                .buttonStyle(.bordered)
                .help(AppText.syncDirection)
            }
            .accessibilityIdentifier("sync-direction-picker")
            if selection.isTwoWay {
                Text(AppText.twoWayUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(AppText.changeToOneWay) {
                    selection = .aToB
                }
                .buttonStyle(.link)
            }
        }
    }
}

struct FolderSelectionStrip: View {
    let mode: SyncMode
    let folderAURL: URL?
    let folderBURL: URL?
    @Binding var githubRepositoryURLForA: String
    @Binding var githubRepositoryURLForB: String
    let githubAuthState: GitHubAuthState
    let githubRepositories: [GitHubRepository]
    let githubRepositoryState: GitHubRepositoryState
    let loadGitHubRepositories: () -> Void
    let chooseFolderA: () -> Void
    let chooseFolderB: () -> Void
    let clearFolderA: () -> Void
    let clearFolderB: () -> Void

    var body: some View {
        HStack(spacing: FolderSelectionMetrics.stripSpacing) {
            endpointView(
                title: AppText.folderA,
                url: folderAURL,
                repositoryURL: $githubRepositoryURLForA,
                allowsGitHubRepository: githubRepositoryURLForB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityID: "folder-a",
                action: chooseFolderA,
                clearFolder: clearFolderA,
                alignment: .leading
            )
            Image(systemName: arrowSymbol)
                .font(.system(size: FolderSelectionMetrics.arrowFontSize, weight: .medium))
                .foregroundStyle(AppPalette.accent)
                .frame(width: FolderSelectionMetrics.arrowFrameWidth, height: FolderSelectionMetrics.arrowFrameHeight)
                .accessibilityHidden(true)
            endpointView(
                title: AppText.folderB,
                url: folderBURL,
                repositoryURL: $githubRepositoryURLForB,
                allowsGitHubRepository: githubRepositoryURLForA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityID: "folder-b",
                action: chooseFolderB,
                clearFolder: clearFolderB,
                alignment: .trailing
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FolderSelectionMetrics.stripHorizontalPadding)
        .padding(.vertical, FolderSelectionMetrics.stripVerticalPadding)
        .background(AppPalette.folderSurface, in: RoundedRectangle(cornerRadius: FolderSelectionMetrics.stripCornerRadius))
    }

    private func endpointView(
        title: String,
        url: URL?,
        repositoryURL: Binding<String>,
        allowsGitHubRepository: Bool,
        accessibilityID: String,
        action: @escaping () -> Void,
        clearFolder: @escaping () -> Void,
        alignment: Alignment
    ) -> some View {
        let isLeading = alignment == .leading
        return VStack(alignment: isLeading ? .leading : .trailing, spacing: FolderSelectionMetrics.endpointSpacing) {
            if let url {
                HStack(spacing: FolderSelectionMetrics.controlSpacing) {
                    VStack(alignment: isLeading ? .leading : .trailing, spacing: 1) {
                        Text(url.lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(url.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)

                    Button(action: clearFolder) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(AppText.cancelFolderSelection)
                    .accessibilityIdentifier("\(accessibilityID)-cancel")
                    .accessibilityLabel(AppText.cancelFolderSelection)

                    Button(action: action) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(AppPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(accessibilityID)-button")
                    .accessibilityLabel(isLeading ? AppText.chooseFolderA : AppText.chooseFolderB)
                }
            } else {
                HStack(spacing: FolderSelectionMetrics.controlSpacing) {
                    if allowsGitHubRepository {
                        GitHubRepositorySelector(
                            placeholder: title,
                            repositoryURL: repositoryURL,
                            authState: githubAuthState,
                            repositories: githubRepositories,
                            repositoryState: githubRepositoryState,
                            loadRepositories: loadGitHubRepositories,
                            onSubmit: {}
                        )
                    } else {
                        Text(AppText.localFolderOnly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
                    }
                    if repositoryURL.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: action) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(AppPalette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(accessibilityID)-button")
                        .accessibilityLabel(isLeading ? AppText.chooseFolderA : AppText.chooseFolderB)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .help(url?.path ?? title)
    }

    private var arrowSymbol: String {
        switch mode {
        case .aToB: "arrow.right"
        case .bToA: "arrow.left"
        case .twoWay: "arrow.left.arrow.right"
        }
    }
}

private enum FolderSelectionMetrics {
    static let stripSpacing: CGFloat = 0
    static let arrowFontSize: CGFloat = 18
    static let arrowFrameWidth: CGFloat = 40
    static let arrowFrameHeight: CGFloat = 42
    static let stripHorizontalPadding: CGFloat = 10
    static let stripVerticalPadding: CGFloat = 6
    static let stripCornerRadius: CGFloat = 8
    static let endpointSpacing: CGFloat = 3
    static let controlSpacing: CGFloat = 5
}
