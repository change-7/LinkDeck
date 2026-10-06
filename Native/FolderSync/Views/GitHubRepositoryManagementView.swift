import SwiftUI

struct GitHubRepositoryManagementView: View {
    let store: FolderPairStore
    @State private var isCreatePresented = false
    @State private var editingRepository: GitHubRepository?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppText.githubRepositoryManagement)
                        .font(.title3.weight(.semibold))
                    Text(AppText.githubRepositoryManagementDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.githubAuthState == .loggedIn {
                    Button(AppText.githubCreateRepository, systemImage: "plus") {
                        isCreatePresented = true
                    }
                    Button(AppText.githubRefreshRepositories, systemImage: "arrow.clockwise") {
                        Task { await store.refreshGitHubRepositories() }
                    }
                    .help(AppText.githubRefreshRepositories)
                }
            }

            if store.githubAuthState == .loggedIn {
                repositoryContent
            } else {
                loginContent
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.settingsSurface)
        .task {
            await store.refreshGitHubAuthStatus()
            if store.githubAuthState == .loggedIn {
                await store.refreshGitHubRepositories()
            }
        }
        .sheet(isPresented: $isCreatePresented) {
            GitHubRepositoryCreateView { repository in
                store.addGitHubRepository(repository)
            }
        }
        .sheet(item: $editingRepository) { repository in
            GitHubRepositoryEditView(repository: repository) { updatedRepository in
                Task { await store.updateGitHubRepository(repository, with: updatedRepository) }
            }
        }
    }

    @ViewBuilder
    private var loginContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(authStateDescription, systemImage: "person.crop.circle")
                .foregroundStyle(.secondary)
            Button(AppText.githubLogIn, systemImage: "person.crop.circle.badge.key") {
                Task { await store.loginToGitHub() }
            }
            .disabled(store.githubAuthState == .checking || store.githubAuthState == .loggingIn)
            Text(AppText.githubLoginHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var repositoryContent: some View {
        switch store.githubRepositoryState {
        case .idle, .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text(AppText.githubRepositoriesLoading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(AppText.githubRefreshRepositories) {
                    Task { await store.refreshGitHubRepositories() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if store.githubRepositories.isEmpty {
                Text(AppText.githubNoRepositories)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.githubRepositories) { repository in
                    GitHubRepositoryManagementRow(repository: repository) {
                        editingRepository = repository
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var authStateDescription: String {
        switch store.githubAuthState {
        case .unknown, .loggedOut:
            AppText.githubNotLoggedIn
        case .checking:
            AppText.githubCheckingLogin
        case .loggingIn:
            AppText.githubLoggingIn
        case .loggedIn:
            AppText.githubConnected
        case .failed(let message):
            message
        }
    }
}

private struct GitHubRepositoryManagementRow: View {
    let repository: GitHubRepository
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repository.isPrivate ? "lock.fill" : "folder")
                .foregroundStyle(repository.isPrivate ? .orange : AppPalette.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.fullName)
                    .lineLimit(1)
                Text(repository.isPrivate ? AppText.githubPrivate : AppText.githubPublic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(AppText.githubRepositoryEdit, systemImage: "pencil", action: edit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(AppText.githubRepositoryEdit)
        }
        .padding(.vertical, 3)
    }
}

private struct GitHubRepositoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: GitHubRepository
    let onSaved: (GitHubRepository) -> Void
    @State private var name: String
    @State private var description: String
    @State private var visibility: GitHubRepositoryVisibility
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(repository: GitHubRepository, onSaved: @escaping (GitHubRepository) -> Void) {
        self.repository = repository
        self.onSaved = onSaved
        _name = State(initialValue: repository.name)
        _description = State(initialValue: repository.description ?? "")
        _visibility = State(initialValue: repository.isPrivate ? .privateRepository : .publicRepository)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppText.githubRepositoryEdit)
                .font(.title2.weight(.semibold))

            Form {
                TextField(AppText.githubRepositoryName, text: $name)
                TextField(AppText.githubRepositoryDescription, text: $description)
                Picker(AppText.githubVisibility, selection: $visibility) {
                    Text(AppText.githubPrivate).tag(GitHubRepositoryVisibility.privateRepository)
                    Text(AppText.githubPublic).tag(GitHubRepositoryVisibility.publicRepository)
                }
                .pickerStyle(.segmented)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(AppText.cancel) { dismiss() }
                    .disabled(isSaving)
                Button(isSaving ? AppText.githubRepositoryUpdating : AppText.githubRepositorySaveChanges) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let updatedRepository = try await GitHubAuthService().updateRepository(
                    repository,
                    name: trimmedName,
                    description: trimmedDescription,
                    visibility: visibility
                )
                onSaved(updatedRepository)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
