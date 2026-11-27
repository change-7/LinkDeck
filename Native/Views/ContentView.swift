import SwiftUI
import Combine

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: LaunchpadStore
    let folderSyncStore: FolderPairStore
    let runner: MacActionRunner
    let codex: CodexAppServerClient
    let codexActivity: CodexActivityController
    let chatGPTTunnel: ChatGPTTunnelController
    @State private var showingPermissionAlert = false
    @State private var showingCodexConnection = false
    @State private var showingBackupRestore = false
    @State private var showingFolderSyncSettings = false
    @AppStorage(MainScreen.storageKey) private var selectedMainScreen: MainScreen = .smartphoneButtons
    @AppStorage(MainScreen.apiAppsPositionLockedKey) private var apiAppsPositionLocked = false
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("linkdeck.folder-sync-compact") private var folderSyncCompact = false
    private var compact: Bool {
        selectedMainScreen == .apiApps || (selectedMainScreen == .folderSync && folderSyncCompact)
    }

    var body: some View {
        ZStack {
            if selectedMainScreen == .apiApps {
                APIAppsBackdrop(material: .hudWindow)
                    .overlay(MacAppearance(scheme: colorScheme).canvas.opacity(0.48))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                MacAppearance(scheme: colorScheme).canvas.ignoresSafeArea()
            }
            mainContent
        }
        .frame(minWidth: compact ? 360 : 1100,
               maxWidth: compact ? 360 : .infinity,
               minHeight: compact ? 300 : 640,
               maxHeight: compact ? 300 : .infinity)
        .toolbar {
            if selectedMainScreen != .smartphoneButtons {
                ToolbarItem(placement: .primaryAction) {
                    CompactModeToolbar(selection: $selectedMainScreen, onOpenSettings: {
                        if selectedMainScreen == .folderSync { showingFolderSyncSettings = true }
                        else { showingCodexConnection = true }
                    })
                }
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(MainWindowModeSize(
            compact: compact,
            translucent: selectedMainScreen == .apiApps,
            positionLocked: selectedMainScreen == .apiApps && apiAppsPositionLocked
        ))
        .preferredColorScheme(AppAppearanceMode(rawValue: appearanceMode)?.colorScheme)
        .onAppear {
            chatGPTTunnel.connectOnStartup(store: store, folderSyncStore: folderSyncStore, runner: runner)
            codex.setRemoteSmartphonePagesProvider { SmartphoneDefaults.persistedPages() }
            codex.setRemoteSmartphonePagesDidChangeHandler { store.applyRemoteSmartphonePages($0) }
            codex.setRemoteCodexPhoneThemeProvider { store.codexPhoneTheme }
            codex.setRemoteCompletionSoundProvider { store.codexCompletionSounds.remoteSelection }
            codex.setRemoteApprovalSoundProvider { store.codexCompletionSounds.remoteApprovalSelection }
            codex.onRemoteSoundOutputTarget = { target in
                store.codexCompletionSounds.setNotificationSoundOutputTarget(target)
                codex.publishRemoteState()
            }
            codex.setLocalCompletionSoundHandler { store.codexCompletionSounds.playSelectedSoundOnMac() }
            codex.setLocalApprovalSoundHandler { store.codexCompletionSounds.playSelectedApprovalSoundOnMac() }
            codex.refreshWeeklyUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacActionRunner.workflowFinishedNotification)) { notification in
            if let message = notification.object as? String { store.statusMessage = message }
        }
        .onChange(of: selectedMainScreen) { previous, current in
            if current == .folderSync { folderSyncCompact = previous == .apiApps }
        }
        .onChange(of: store.smartphonePages) { _, _ in
            codex.publishRemoteState()
        }
        .onChange(of: store.codexPhoneTheme) { _, _ in
            codex.publishRemoteState()
        }
        .onChange(of: codex.activity, initial: true) { _, activity in
            codexActivity.updateAppServerActivity(activity)
        }
        .safeAreaInset(edge: .bottom) {
            if selectedMainScreen == .smartphoneButtons { footer }
        }
        .alert("손쉬운 사용 권한", isPresented: $showingPermissionAlert) {
            Button("설정 열기") { runner.requestAccessibilityPermission() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("macOS 단축키를 실행하려면 이 앱을 손쉬운 사용에 허용하세요.")
        }
        .sheet(isPresented: $showingCodexConnection) {
            CodexConnectionView(
                store: store,
                folderSyncStore: folderSyncStore,
                codex: codex,
                chatGPTTunnel: chatGPTTunnel
            )
        }
        .sheet(isPresented: $showingBackupRestore) {
            BackupRestoreView(store: store)
        }
        .sheet(isPresented: $showingFolderSyncSettings) {
            AppSettingsView(store: folderSyncStore)
        }
    }

    private var mainContent: some View {
        Group {
            switch selectedMainScreen {
            case .folderSync:
                FolderSyncWorkspaceView(store: folderSyncStore, compact: compact,
                                        showSettings: { showingFolderSyncSettings = true })
            case .apiApps:
                APIAppsView(store: store, selection: $selectedMainScreen,
                            onOpenSettings: { showingCodexConnection = true })
            case .smartphoneButtons:
                SmartphoneSettingsView(
                    store: store,
                    runner: runner,
                    folderSyncStore: folderSyncStore,
                    selectedMainScreen: $selectedMainScreen,
                    codexIsConnected: codex.isConnected,
                    onOpenBackupRestore: { showingBackupRestore = true },
                    onOpenCodexSettings: { showingCodexConnection = true },
                    onOpenFolderSyncSettings: { showingFolderSyncSettings = true }
                )
                    .frame(minWidth: 900, minHeight: 520)
            }
        }
        .padding(.horizontal, compact ? 0 : 12)
        .padding(.bottom, compact ? 0 : 6)
    }

    private var footer: some View {
        HStack {
            Text(store.statusMessage)
            Spacer()
            Button("단축키 권한") { showingPermissionAlert = true }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 26)
        .frame(height: 34)
        .background(MacAppearance(scheme: colorScheme).canvas)
    }

}
