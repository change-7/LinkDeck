import SwiftUI

struct GitHubRepositorySelector: View {
    let placeholder: String
    @Binding var repositoryURL: String
    let authState: GitHubAuthState
    let repositories: [GitHubRepository]
    let repositoryState: GitHubRepositoryState
    let loadRepositories: () -> Void
    let onSubmit: () -> Void

    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $repositoryURL, prompt: Text(AppText.githubRepositoryURLPrompt))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(placeholder)
                .onSubmit(onSubmit)

            Button {
                isPickerPresented = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(AppPalette.accent)
            }
            .buttonStyle(.plain)
            .help(AppText.githubChooseRepository)
            .accessibilityLabel(AppText.githubChooseRepository)
            .disabled(authState == .checking || authState == .loggingIn)
        }
        .popover(isPresented: $isPickerPresented, arrowEdge: .top) {
            GitHubRepositoryPicker(
                repositories: repositories,
                repositoryState: repositoryState,
                loadRepositories: loadRepositories,
                selectRepository: { repository in
                    repositoryURL = repository.cloneURL
                    isPickerPresented = false
                    onSubmit()
                }
            )
            .frame(width: 390, height: 440)
        }
        .onChange(of: isPickerPresented) { _, isPresented in
            if isPresented {
                loadRepositories()
            }
        }
    }
}

private struct GitHubRepositoryPicker: View {
    let repositories: [GitHubRepository]
    let repositoryState: GitHubRepositoryState
    let loadRepositories: () -> Void
    let selectRepository: (GitHubRepository) -> Void

    @State private var searchText = ""
    @State private var isCreatePresented = false

    private var filteredRepositories: [GitHubRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return repositories }
        return repositories.filter { repository in
            repository.fullName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppText.githubChooseRepository)
                    .font(.headline)
                Spacer()
                Button {
                    isCreatePresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help(AppText.githubCreateRepository)
                .accessibilityLabel(AppText.githubCreateRepository)
                Button(action: loadRepositories) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(AppText.githubRefreshRepositories)
                .accessibilityLabel(AppText.githubRefreshRepositories)
            }

            TextField(AppText.githubSearchRepositories, text: $searchText)
                .textFieldStyle(.roundedBorder)

            Group {
                switch repositoryState {
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
                        Button(AppText.githubRefreshRepositories, action: loadRepositories)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    if filteredRepositories.isEmpty {
                        Text(searchText.isEmpty ? AppText.githubNoRepositories : AppText.githubNoMatchingRepositories)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredRepositories) { repository in
                            Button {
                                selectRepository(repository)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: repository.isPrivate ? "lock.fill" : "folder")
                                        .foregroundStyle(repository.isPrivate ? .orange : AppPalette.accent)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(repository.fullName)
                                            .lineLimit(1)
                                        if repository.isArchived {
                                            Text(AppText.githubArchivedRepository)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if repository.isFork {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.inset)
                    }
                }
            }
        }
        .padding(14)
        .sheet(isPresented: $isCreatePresented) {
            GitHubRepositoryCreateView { repository in
                selectRepository(repository)
                loadRepositories()
            }
        }
    }
}

struct GitHubRepositoryCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: (GitHubRepository) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var owner = ""
    @State private var organizations: [GitHubOrganization] = []
    @State private var organizationState: GitHubOrganizationState = .idle
    @State private var visibility: GitHubRepositoryVisibility = .privateRepository
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppText.githubNewRepository)
                .font(.title2.weight(.semibold))

            HStack {
                Text(AppText.githubRepositoryOwner)
                Spacer()
                Menu {
                    Button(AppText.githubPersonalAccount) {
                        owner = ""
                    }
                    ForEach(organizations) { organization in
                        Button(organization.login) {
                            owner = organization.login
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(owner.isEmpty ? AppText.githubPersonalAccount : owner)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)
            }

            if organizationState == .loading {
                Text(AppText.githubOrganizationsLoading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .failed = organizationState {
                Text(AppText.githubOrganizationsUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField(AppText.githubRepositoryName, text: $name, prompt: Text(AppText.githubRepositoryNamePrompt))
                TextField(AppText.githubRepositoryDescription, text: $description, prompt: Text(AppText.githubRepositoryDescriptionPrompt))
                Picker(AppText.githubVisibility, selection: $visibility) {
                    Text(AppText.githubPrivate).tag(GitHubRepositoryVisibility.privateRepository)
                    Text(AppText.githubPublic).tag(GitHubRepositoryVisibility.publicRepository)
                }
                .pickerStyle(.segmented)
                Text(AppText.githubCreateRepositoryHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(AppText.cancel) {
                    dismiss()
                }
                .disabled(isCreating)
                Button(isCreating ? AppText.githubCreatingRepository : AppText.githubCreateRepository) {
                    createRepository()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(18)
        .frame(width: 480)
        .task { await loadOrganizations() }
    }

    private func createRepository() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        errorMessage = nil
        isCreating = true

        Task {
            do {
                let repository = try await GitHubAuthService().createRepository(
                    name: trimmedName,
                    description: trimmedDescription,
                    visibility: visibility,
                    owner: owner.isEmpty ? nil : owner
                )
                onCreated(repository)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func loadOrganizations() async {
        guard organizationState == .idle else { return }
        organizationState = .loading
        do {
            organizations = try await GitHubAuthService().listOrganizations()
            organizationState = .loaded
        } catch {
            organizationState = .failed(error.localizedDescription)
        }
    }
}
