import AppKit
import Observation

struct LinkDeckTunnelLaunch {
    let arguments: [String]
    let environment: [String: String]

    init(tunnelID: String, apiKey: String, serverURL: URL, localToken: String, healthFile: String) {
        arguments = ["run", "--control-plane.tunnel-id", tunnelID,
                     "--control-plane.api-key", "env:LINKDECK_TUNNEL_API_KEY",
                     "--mcp.server-url", serverURL.absoluteString,
                     "--mcp.extra-headers", "Authorization: env:LINKDECK_MCP_AUTHORIZATION",
                     "--mcp.discovery-extra-headers", "Authorization: env:LINKDECK_MCP_AUTHORIZATION",
                     "--health.listen-addr", "127.0.0.1:0", "--health.url-file", healthFile]
        environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                       "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                       "TMPDIR": FileManager.default.temporaryDirectory.path,
                       "LINKDECK_TUNNEL_API_KEY": apiKey,
                       "LINKDECK_MCP_AUTHORIZATION": "Bearer " + localToken]
    }
}

@MainActor
@Observable
final class ChatGPTTunnelController {
    var tunnelID: String
    var apiKey = ""
    private(set) var isActive = false
    private(set) var isReady = false
    private(set) var message = "연결 안 됨"
    private(set) var lastAction = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var server: LinkDeckMCPServer?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private let preferences: UserDefaults

    init(preferences: UserDefaults = UserDefaults(suiteName: "com.pdg.chatgpt-micro-launchpad.native") ?? .standard) {
        self.preferences = preferences
        tunnelID = preferences.string(forKey: "linkdeck.chatgpt-tunnel-id") ?? ""
    }

    static var executable: URL? {
        ["/opt/homebrew/bin/tunnel-client", "/usr/local/bin/tunnel-client"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    func connect(store: LaunchpadStore, folderSyncStore: FolderPairStore, runner: MacActionRunner) {
        guard !isActive else { return }
        let id = tunnelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.hasPrefix("tunnel_"), id.count <= 128,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }), !key.isEmpty else {
            message = "터널 ID와 런타임 API 키를 입력하세요."
            return
        }
        guard let executable = Self.executable else {
            message = "tunnel-client가 없습니다. 안내의 설치 명령을 먼저 실행하세요."
            return
        }
        tunnelID = id
        preferences.set(id, forKey: "linkdeck.chatgpt-tunnel-id")
        isActive = true
        isReady = false
        message = "터널 연결 중…"
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                executable: executable,
                tunnelID: id,
                apiKey: key,
                store: store,
                folderSyncStore: folderSyncStore,
                runner: runner
            )
        }
    }

    func disconnect() {
        guard isActive else { return }
        message = "연결 종료 중…"
        isReady = false
        task?.cancel()
        server?.stop()
        if let process, process.isRunning { process.terminate() }
    }

    private func run(
        executable: URL,
        tunnelID: String,
        apiKey: String,
        store: LaunchpadStore,
        folderSyncStore: FolderPairStore,
        runner: MacActionRunner
    ) async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("linkdeck-tunnel-\(UUID())")
        let healthFile = directory.appendingPathComponent("health.url")
        let server = LinkDeckMCPServer()
        self.server = server
        server.handle = { [weak self] data in
            let catalog = LinkDeckMCPHandler.buttons(macPages: store.pages, phonePages: store.smartphonePages)
            return LinkDeckMCPHandler.response(to: data, buttons: catalog, folderSyncStore: folderSyncStore) { button in
                let result = try runner.execute(button.action, commandFileID: button.commandFileID)
                self?.lastAction = button.title + ": " + result
                return result
            }
        }
        server.onFailure = { [weak self] in self?.disconnect() }
        server.onRequestRejected = { [weak self] reason in self?.lastAction = "연결 요청 거부: " + reason }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = try await server.start()
            try Task.checkCancellation()
            let launch = LinkDeckTunnelLaunch(tunnelID: tunnelID, apiKey: apiKey, serverURL: url,
                                              localToken: server.token, healthFile: healthFile.path)
            let process = Process()
            process.executableURL = executable
            process.arguments = launch.arguments
            process.environment = launch.environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            self.process = process
            var misses = 0
            while !Task.isCancelled && process.isRunning {
                let pid = process.processIdentifier
                let ready = await Task.detached(priority: .utility) {
                    let probe = Process()
                    probe.executableURL = executable
                    probe.arguments = ["health", "--url-file", healthFile.path, "--pid", String(pid), "--require-control-plane-poll"]
                    probe.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
                    probe.standardOutput = FileHandle.nullDevice
                    probe.standardError = FileHandle.nullDevice
                    do {
                        try probe.run()
                        probe.waitUntilExit()
                        return probe.terminationStatus == 0
                    } catch { return false }
                }.value
                try Task.checkCancellation()
                isReady = ready
                if ready { misses = 0; message = "터널 연결됨 · ChatGPT에서 사용할 준비가 됐습니다." }
                else {
                    misses += 1
                    message = misses < 10 ? "터널 연결 확인 중…" : "터널 응답 없음 · 키와 터널 권한, 네트워크를 확인하세요."
                }
                try await Task.sleep(for: .seconds(3))
            }
            if !Task.isCancelled { message = "터널 실행이 종료됐습니다. 키와 터널 ID·권한을 확인하세요." }
        } catch {
            message = Task.isCancelled ? "연결 안 됨" : "터널을 시작하지 못했습니다. 설치 상태와 연결 정보를 확인하세요."
        }
        server.stop()
        if let process = self.process {
            if process.isRunning { process.terminate() }
            await Task.detached {
                if process.isRunning {
                    for _ in 0..<20 {
                        if !process.isRunning { break }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                process.waitUntilExit()
            }.value
        }
        self.process = nil
        self.server = nil
        try? FileManager.default.removeItem(at: directory)
        isActive = false
        isReady = false
        if Task.isCancelled { message = "연결 안 됨" }
        task = nil
    }
}
