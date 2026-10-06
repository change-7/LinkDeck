import SwiftUI

struct AppSettingsView: View {
    let store: FolderPairStore
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceMode = AppAppearanceMode.system.rawValue
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            settingsTabBar
            selectedContent
        }
        .frame(width: 640, height: 700)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .task { await store.refreshGitHubAuthStatus() }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 2) {
            tabButton(.general, title: AppText.generalSettings, systemImage: "gearshape")
            tabButton(.githubRepositories, title: AppText.githubRepositoryManagement, systemImage: "folder.badge.gearshape")
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView(store: store)
        case .githubRepositories:
            GitHubRepositoryManagementView(store: store)
        }
    }

    private func tabButton(_ tab: SettingsTab, title: String, systemImage: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selectedTab == tab ? Color.primary.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .frame(maxWidth: .infinity)
        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private var selectedAppearance: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceMode) ?? .system
    }
}

private enum SettingsTab: Hashable {
    case general
    case githubRepositories
}

private struct GeneralSettingsView: View {
    let store: FolderPairStore
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceMode = AppAppearanceMode.system.rawValue

    var body: some View {
        Form {
            Section(AppText.appSettings) {
                Toggle(AppText.waitForFileOperations, isOn: waitsForFileOperationsBinding)
                Text(AppText.waitForFileOperationsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(AppText.appearance) {
                Picker(AppText.appearance, selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section(AppText.githubAccount) {
                HStack {
                    Label(AppText.githubAccount, systemImage: "person.crop.circle")
                    Spacer()
                    Text(authStateDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button(
                    store.githubAuthState == .loggedIn ? AppText.githubConnected : AppText.githubLogIn,
                    systemImage: store.githubAuthState == .loggedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.key"
                ) {
                    Task { await store.loginToGitHub() }
                }
                .disabled(store.githubAuthState == .loggedIn || store.githubAuthState == .checking || store.githubAuthState == .loggingIn)
                Text(AppText.githubLoginHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppPalette.settingsSurface)
        .padding()
    }

    private var waitsForFileOperationsBinding: Binding<Bool> {
        Binding(
            get: { store.appSettings.waitsForFileOperations },
            set: { store.setWaitsForFileOperations($0) }
        )
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
