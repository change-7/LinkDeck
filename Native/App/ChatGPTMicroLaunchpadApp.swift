import AppKit
import Observation
import SwiftUI

@main
struct ChatGPTMicroLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = LaunchpadStore()
    @State private var folderSyncStore = FolderPairStore()
    @AppStorage("macDarkModeEnabled") private var macDarkModeEnabled = true
    private let runner = MacActionRunner()

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                folderSyncStore: folderSyncStore,
                runner: runner,
                codex: appDelegate.codex,
                codexActivity: appDelegate.codexActivityController,
                chatGPTTunnel: appDelegate.chatGPTTunnel
            )
                .preferredColorScheme(macDarkModeEnabled ? .dark : .light)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("LinkDeck") {
                Button("설정 창 열기") { appDelegate.showMainWindow() }
                    .keyboardShortcut(",", modifiers: [.command])
                Button("단축키 권한 요청") { runner.requestAccessibilityPermission() }
            }

            CommandGroup(replacing: .appTermination) {
                Button("창 닫기") { appDelegate.hideMainWindow() }
                    .keyboardShortcut("q", modifiers: [.command])
            }
        }

    }
}

@MainActor
protocol CodexAppServerConnectionStarting: AnyObject {
    func connect()
    func startTask(prompt: String, workingDirectory: String)
}

extension CodexAppServerClient: CodexAppServerConnectionStarting {}

@MainActor
@Observable
final class CodexActivityController {
    typealias MakeMonitor = (@escaping ([DesktopCodexTaskLifecycleEvent]) -> Void) -> CodexDesktopTaskMonitor

    private(set) var activity: CodexActivity = .idle
    private(set) var activeSessionCount = 0
    @ObservationIgnored var onActivityChange: ((CodexActivity) -> Void)?
    @ObservationIgnored var onTaskCompletion: ((DesktopCodexTaskID) -> Void)?
    @ObservationIgnored var onActiveSessionCountChange: ((Int) -> Void)?
    @ObservationIgnored private let makeMonitor: MakeMonitor
    @ObservationIgnored private var coordinator = CodexActivityCoordinator()
    @ObservationIgnored private var appServerActivity: CodexActivity = .idle
    @ObservationIgnored private var desktopMonitor: CodexDesktopTaskMonitor?
    @ObservationIgnored private var desktopCompletionGraceWorkItem: DispatchWorkItem?
    private static let desktopCompletionGracePeriod: TimeInterval = 3

    convenience init() {
        let sessionsRootURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        self.init(makeMonitor: { onEvents in
            CodexDesktopTaskMonitor(sessionsRootURL: sessionsRootURL, onEvents: onEvents)
        })
    }

    init(makeMonitor: @escaping MakeMonitor) {
        self.makeMonitor = makeMonitor
    }

    func startDesktopMonitoring() {
        guard desktopMonitor == nil else { return }
        let monitor = makeMonitor { [weak self] events in
            self?.consumeDesktopEvents(events)
        }
        desktopMonitor = monitor
        monitor.start()
    }

    func stopDesktopMonitoring() {
        desktopCompletionGraceWorkItem?.cancel()
        desktopCompletionGraceWorkItem = nil
        desktopMonitor?.stop()
        desktopMonitor = nil
        activeDesktopSessionIDs.removeAll()
        coordinator = CodexActivityCoordinator()
        updateActiveSessionCount()
        publish(coordinator.updateAppServerActivity(appServerActivity))
    }

    func updateAppServerActivity(_ activity: CodexActivity) {
        appServerActivity = activity
        if activity == .completed || activity == .failed {
            desktopMonitor?.scanActiveTranscripts()
            scheduleDesktopCompletionFallback()
        }
        // Do not cancel the fallback when the App Server repeats a stale
        // running/approval update. Only a real Desktop `started` event can
        // prove that a new task superseded the pending completion.
        updateActiveSessionCount()
        publish(coordinator.updateAppServerActivity(activity))
    }

    private func consumeDesktopEvents(_ events: [DesktopCodexTaskLifecycleEvent]) {
        if events.contains(where: { if case .started = $0 { return true }; return false }) {
            desktopCompletionGraceWorkItem?.cancel()
            desktopCompletionGraceWorkItem = nil
        }
        let nextActivity = coordinator.consume(events)
        updateDesktopSessionSet(with: events)
        publish(nextActivity)
        updateActiveSessionCount()
        for event in events {
            if case let .completed(taskID) = event {
                onTaskCompletion?(taskID)
            }
        }
    }

    private func scheduleDesktopCompletionFallback() {
        guard !activeDesktopSessionIDs.isEmpty else { return }
        desktopCompletionGraceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.activeDesktopSessionIDs.isEmpty else { return }
            let orphaned = self.activeDesktopSessionIDs
            self.activeDesktopSessionIDs.removeAll()
            let terminalEvents = orphaned.map(DesktopCodexTaskLifecycleEvent.completed)
            let nextActivity = self.coordinator.consume(terminalEvents)
            self.publish(nextActivity)
            self.updateActiveSessionCount()
            for taskID in orphaned { self.onTaskCompletion?(taskID) }
            self.desktopCompletionGraceWorkItem = nil
        }
        desktopCompletionGraceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.desktopCompletionGracePeriod, execute: workItem)
    }

    @ObservationIgnored private var activeDesktopSessionIDs: Set<DesktopCodexTaskID> = []

    private func updateDesktopSessionSet(with events: [DesktopCodexTaskLifecycleEvent]) {
        for event in events {
            switch event {
            case let .started(taskID): activeDesktopSessionIDs.insert(taskID)
            case let .completed(taskID): activeDesktopSessionIDs.remove(taskID)
            }
        }
    }

    private func updateActiveSessionCount() {
        let nextCount: Int
        if !activeDesktopSessionIDs.isEmpty {
            // The launchpad represents the user's current Codex task, not
            // every orphaned transcript left in the global sessions folder.
            // A missing terminal record in an older session must not make the
            // phone report multiple simultaneous tasks.
            nextCount = 1
        } else {
            nextCount = switch coordinator.activity {
            case .completed, .failed: 0
            case .connecting, .running, .waitingForApproval:
                switch appServerActivity {
                case .connecting, .running, .waitingForApproval: 1
                case .idle, .completed, .failed: 0
                }
            case .idle:
                0
            }
        }
        guard activeSessionCount != nextCount else { return }
        activeSessionCount = nextCount
        onActiveSessionCountChange?(nextCount)
    }

    static func sessionCount(for taskIDs: Set<DesktopCodexTaskID>) -> Int {
        Set(taskIDs.map(\.transcriptID)).count
    }

    private func publish(_ nextActivity: CodexActivity) {
        guard activity != nextActivity else { return }
        activity = nextActivity
        onActivityChange?(nextActivity)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private static let mainWindowPositionKey = "linkdeck.main-window-top-left"

    var isBridgeOnly: Bool { CommandLine.arguments.contains("--bridge-only") }
    let codex: CodexAppServerClient
    let codexActivityController: CodexActivityController
    let chatGPTTunnel = ChatGPTTunnelController()
    private let remoteActionRunner = MacActionRunner()
    private let connectionStarter: any CodexAppServerConnectionStarting
    private weak var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var hasStartedCodexConnection = false

    override init() {
        let codex = CodexAppServerClient()
        self.codex = codex
        connectionStarter = codex
        codexActivityController = CodexActivityController()
        super.init()
        configureRemoteCommandHandling()
    }

    init(
        codexActivityController: CodexActivityController,
        connectionStarter: (any CodexAppServerConnectionStarting)? = nil
    ) {
        let codex = CodexAppServerClient()
        self.codex = codex
        self.codexActivityController = codexActivityController
        self.connectionStarter = connectionStarter ?? codex
        super.init()
        configureRemoteCommandHandling()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !terminateDuplicateInstanceIfNeeded() else { return }
        if isBridgeOnly {
            NSApp.setActivationPolicy(.prohibited)
        } else {
            installMenuBarItem()
        }
        codexActivityController.onActivityChange = { [weak codex] activity in
            codex?.publishRemoteActivity(activity)
        }
        codexActivityController.onTaskCompletion = { [weak codex] taskID in
            codex?.publishRemoteCompletion(taskID: taskID)
        }
        codexActivityController.onActiveSessionCountChange = { [weak codex] count in
            codex?.publishRemoteSessionCount(count)
        }
        codexActivityController.startDesktopMonitoring()
        codex.publishRemoteSessionCount(codexActivityController.activeSessionCount)
        codex.publishRemoteActivity(codexActivityController.activity)
        codex.startRemoteBridge()
        guard !hasStartedCodexConnection else { return }
        hasStartedCodexConnection = true
        connectionStarter.connect()
    }

    private func terminateDuplicateInstanceIfNeeded() -> Bool {
        guard !isBridgeOnly,
              let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else { return false }

        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isBridgeOnly {
            DispatchQueue.main.async {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let window = Self.mainApplicationWindow(in: NSApp.windows) else { return }

            self.mainWindow = window
            if let screen = NSScreen.main {
                let position = UserDefaults.standard.string(forKey: Self.mainWindowPositionKey).map(NSPointFromString)
                let frame = Self.restoredMainWindowFrame(
                    size: window.frame.size,
                    topLeft: position,
                    defaultScreen: screen.visibleFrame,
                    screens: NSScreen.screens.map(\.visibleFrame)
                )
                window.setFrame(frame, display: true)
            }
            window.delegate = self
            self.saveMainWindowPosition(window)
            window.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        chatGPTTunnel.disconnect()
        codexActivityController.stopDesktopMonitoring()
        codex.stopRemoteBridge()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        saveMainWindowPosition(window)
    }

    private func saveMainWindowPosition(_ window: NSWindow) {
        guard !window.isMiniaturized, !window.styleMask.contains(.fullScreen) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.mainWindowPositionKey)
    }

    static func restoredMainWindowFrame(
        size: NSSize, topLeft: NSPoint?, defaultScreen: NSRect, screens: [NSRect]
    ) -> NSRect {
        if let topLeft {
            let proposed = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
            let overlap: (NSRect) -> CGFloat = { screen in
                let intersection = proposed.intersection(screen)
                return intersection.isEmpty ? 0 : intersection.width * intersection.height
            }
            if let screen = screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0 {
                let width = min(size.width, screen.width)
                let height = min(size.height, screen.height)
                return NSRect(
                    x: min(max(proposed.minX, screen.minX), screen.maxX - width),
                    y: min(max(topLeft.y - height, screen.minY), screen.maxY - height),
                    width: width,
                    height: height
                )
            }
        }
        let screen = defaultScreen.insetBy(dx: 18, dy: 18)
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        return NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
    }

    func showMainWindow() {
        let window = mainWindow ?? Self.mainApplicationWindow(in: NSApp.windows)
        guard let window else { return }
        mainWindow = window
        if window.level == MainWindowModeSize.apiAppsBackLevel {
            window.level = .normal
        }
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    static func mainApplicationWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { !($0 is NSPanel) && $0.styleMask.contains(.titled) }
    }

    func quitCompletely() {
        NSApp.terminate(nil)
    }

    private func configureRemoteCommandHandling() {
        codex.setRemoteCommandHandler { [weak self] command in
            guard let self else {
                return CodexRemoteCommandResult(id: command.id, success: false, message: "Mac 명령 처리기를 사용할 수 없습니다.")
            }
            return await self.handleRemoteCommand(command)
        }
    }

    private func handleRemoteCommand(_ command: CodexRemoteCommand) async -> CodexRemoteCommandResult {
        do {
            let message: String
            switch command.command {
            case "microphoneStart":
                if let error = codex.startPhoneMicrophone() {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: error)
                }
                message = "휴대폰 마이크를 BlackHole 2ch로 연결했습니다."
            case "microphoneStop":
                codex.stopPhoneMicrophone()
                message = "휴대폰 마이크 연결을 종료했습니다."
            case "notificationSoundOnPhone", "notificationSoundOnMac", "completionSoundOnPhone", "completionSoundOnMac":
                let target: CodexCompletionSoundOutputTarget = command.command.hasSuffix("OnPhone") ? .phone : .mac
                codex.setRemoteSoundOutputTarget(target)
                message = "완료·승인 사운드 재생 기기를 \(target.title)(으)로 변경했습니다."
            case "smartphoneButton", "smartphoneButtonLongPress":
                let longPress = command.command == "smartphoneButtonLongPress"
                guard let buttonID = command.buttonID else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: "스마트폰 버튼 설정을 찾을 수 없습니다.")
                }
                var pages = SmartphoneDefaults.persistedPages()
                let action: PadAction?
                if longPress {
                    action = SmartphoneDefaults.action(id: buttonID, in: pages, longPress: true)
                } else {
                    let previousPages = pages
                    action = SmartphoneDefaults.toggleAction(id: buttonID, in: &pages)
                    if pages != previousPages {
                        SmartphoneDefaults.persist(pages)
                        codex.remoteSmartphonePagesDidChange(pages)
                        codex.publishRemoteState()
                    }
                }
                guard let action else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: "스마트폰 버튼 설정을 찾을 수 없습니다.")
                }
                let commandFileID = longPress ? buttonID + "_long_press" : buttonID
                message = try remoteActionRunner.execute(action, commandFileID: commandFileID)
            case "codexApproval":
                guard let decision = command.decision else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: "Codex 승인 응답이 없습니다.")
                }
                let response = await codex.respondToRemoteApproval(
                    decision: decision,
                    requestKey: command.approvalRequestKey
                )
                guard response.success else {
                    return CodexRemoteCommandResult(id: command.id, success: false, message: response.message)
                }
                message = response.message
            case "run":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+r"))
            case "pause":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "space"))
            case "stop":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "escape"))
            case "terminal":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.Terminal"))
            case "browser":
                guard let url = URL(string: "https://www.apple.com") else { throw MacActionError.invalidAddress }
                NSWorkspace.shared.open(url)
                message = "기본 브라우저를 열었습니다."
            case "files":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.finder"))
            case "search":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+space"))
            case "capture":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+shift+4"))
            case "clipboard":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "cmd+v"))
            case "music":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.Music"))
            case "volume":
                message = try remoteActionRunner.execute(PadAction(kind: .shortcut, value: "volumeup"))
            case "focus":
                guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus") else { throw MacActionError.invalidAddress }
                NSWorkspace.shared.open(url)
                message = "집중 모드 설정을 열었습니다."
            case "settings":
                message = try remoteActionRunner.execute(PadAction(kind: .app, value: "com.apple.systempreferences"))
            case "more":
                message = "추가 동작은 Mac 앱에서 매핑하세요."
            default:
                return CodexRemoteCommandResult(id: command.id, success: false, message: "지원하지 않는 버튼입니다.")
            }
            return CodexRemoteCommandResult(id: command.id, success: true, message: message)
        } catch {
            return CodexRemoteCommandResult(id: command.id, success: false, message: error.localizedDescription)
        }
    }

    private func installMenuBarItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.3x3.fill",
            accessibilityDescription: "LinkDeck"
        )
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "설정 창 열기", action: #selector(openMainWindowFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "API 앱 위치 고정", action: #selector(toggleAPIAppsPositionLock), keyEquivalent: "")
        menu.addItem(withTitle: "API 앱을 맨 뒤로 보내기", action: #selector(sendAPIAppsToBack), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "재시작", action: #selector(restartFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "완전히 종료", action: #selector(quitFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private var isAPIAppsSelected: Bool {
        UserDefaults.standard.string(forKey: MainScreen.storageKey) == MainScreen.apiApps.rawValue
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let positionLock = menu.items.first { $0.action == #selector(toggleAPIAppsPositionLock) }
        positionLock?.isHidden = !isAPIAppsSelected
        positionLock?.state = UserDefaults.standard.bool(forKey: MainScreen.apiAppsPositionLockedKey) ? .on : .off
        let sendToBack = menu.items.first { $0.action == #selector(sendAPIAppsToBack) }
        sendToBack?.isHidden = !isAPIAppsSelected
    }

    @objc private func toggleAPIAppsPositionLock() {
        guard isAPIAppsSelected else { return }
        let defaults = UserDefaults.standard
        let key = MainScreen.apiAppsPositionLockedKey
        defaults.set(!defaults.bool(forKey: key), forKey: key)
    }

    @objc private func sendAPIAppsToBack() {
        guard isAPIAppsSelected, let mainWindow, mainWindow.isVisible else { return }
        mainWindow.level = MainWindowModeSize.apiAppsBackLevel
        mainWindow.orderBack(nil)
    }

    @objc private func openMainWindowFromMenu() {
        showMainWindow()
    }

    @objc private func quitFromMenu() {
        quitCompletely()
    }

    @objc private func restartFromMenu() {
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for the original process so the duplicate-instance check allows the relaunch.
        relaunch.arguments = [
            "-c",
            """
            while kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
            exec /usr/bin/open -a "$2"
            """,
            "linkdeck-restart",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundlePath
        ]
        do {
            try relaunch.run()
            quitCompletely()
        } catch {
            NSApp.presentError(error)
        }
    }

}
