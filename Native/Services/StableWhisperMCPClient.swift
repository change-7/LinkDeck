import AppKit
import Darwin

actor StableWhisperMCPClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private let jobsDirectory: URL
    private let idleTimeout: Duration
    private var idleTask: Task<Void, Never>?
    private var pendingJobs: [String: String] = [:]
    private var unknownJob = false
    private var settledJobs: Set<String> = []
    private let chatView: Bool
    private var chatViewTasks: Set<String> = []
    private var chatViewAnswerPending = false
    private var chatViewPendingPanels: Set<Int> = []
    private let terminateChatView: @Sendable () async -> Bool
    private let launchChatView: @Sendable (URL) async throws -> Void

    init(jobsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Stable Whisper/linkdeck-mcp-jobs"), idleTimeout: Duration = .seconds(300), chatView: Bool = false, terminateChatView: @escaping @Sendable () async -> Bool = StableWhisperMCPClient.quitChatView, launchChatView: @escaping @Sendable (URL) async throws -> Void = StableWhisperMCPClient.launchChatView) {
        self.jobsDirectory = jobsDirectory
        self.idleTimeout = idleTimeout
        self.chatView = chatView
        self.terminateChatView = terminateChatView
        self.launchChatView = launchChatView
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        pendingJobs.removeAll()
        unknownJob = false
        settledJobs.removeAll()
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        try? output?.close()
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
    }

    func isRunning() -> Bool { process?.isRunning == true }

    func request(_ data: Data, executable: URL, arguments: [String] = ["--mcp"]) async throws -> Data {
        idleTask?.cancel()
        defer { scheduleIdleStop() }
        if process?.isRunning != true {
            stop()
            let child = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            child.executableURL = executable
            child.arguments = arguments
            child.standardInput = stdin
            child.standardOutput = stdout
            child.standardError = FileHandle.nullDevice
            // Keep LinkDeck's API keys out of the child process.
            child.environment = ["HOME": NSHomeDirectory(), "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                                 "STABLE_WHISPER_MCP_JOBS": jobsDirectory.path]
            try child.run()
            process = child
            input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading
            do {
                let initialized = try exchange(["method": "initialize", "params": ["protocolVersion": "2025-06-18",
                    "capabilities": [:], "clientInfo": ["name": "LinkDeck", "version": "1.0.0"]]])
                let reply = try JSONSerialization.jsonObject(with: initialized) as? [String: Any]
                guard reply?["result"] != nil else { throw failure("위스퍼 MCP 초기화에 실패했습니다.") }
                try write(["jsonrpc": "2.0", "method": "notifications/initialized"])
            } catch { stop(); throw error }
        }
        guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw failure("잘못된 위스퍼 요청입니다.")
        }
        do {
            if chatView, request["method"] as? String == "tools/call" {
                try await launchChatView(executable)
                let deadline = Date().addingTimeInterval(8)
                while true {
                    // Probe readiness before sending a task; retrying the task could duplicate work.
                    let state = try exchange(["method": "tools/call", "params": ["name": "chatgpt_state", "arguments": [:]]])
                    if toolObject(state) != nil {
                        break
                    }
                    guard Date() < deadline else { throw failure("챗뷰를 실행했지만 API가 준비되지 않았습니다. 챗뷰의 연결 설정을 확인하세요.") }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
            let reply = try exchange(request)
            if request["method"] as? String == "tools/call",
               let params = request["params"] as? [String: Any], let name = params["name"] as? String {
                observeJob(reply, tool: name)
                if chatView { observeChatView(reply, tool: name, arguments: params["arguments"] as? [String: Any] ?? [:]) }
            }
            return reply
        }
        catch { stop(); throw error }
    }

    private func scheduleIdleStop() {
        guard process?.isRunning == true else { return }
        idleTask = Task { [weak self, idleTimeout] in
            do { try await Task.sleep(for: idleTimeout) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() async {
        guard !Task.isCancelled else { return }
        if chatView {
            guard let reply = try? exchange(["method": "tools/call", "params": ["name": "chatgpt_state", "arguments": [:]]]),
                  let state = toolObject(reply) else {
                scheduleIdleStop()
                return
            }
            guard chatViewTasks.isEmpty, !chatViewAnswerPending, chatViewPendingPanels.isEmpty,
                  Self.chatViewCanQuit(state) else {
                scheduleIdleStop()
                return
            }
            let terminated = await terminateChatView()
            guard !Task.isCancelled else { return }
            if !terminated { scheduleIdleStop(); return }
        }
        for (id, tool) in pendingJobs {
            if let reply = try? exchange(["method": "tools/call", "params": ["name": tool, "arguments": ["job_id": id]]]) {
                observeJob(reply, tool: tool)
            }
        }
        if pendingJobs.isEmpty && !unknownJob { stop() }
        else { scheduleIdleStop() }
    }

    private func observeJob(_ data: Data, tool: String) {
        if let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           reply["error"] != nil || (reply["result"] as? [String: Any])?["isError"] as? Bool == true { return }
        let job = toolObject(data)
        let statusTool: String?
        switch tool {
        case "start_transcription": statusTool = "get_transcription_status"
        case "start_download": statusTool = "get_download_status"
        case "burn_subtitles": statusTool = "get_subtitle_status"
        default: statusTool = nil
        }
        guard let job, let id = (job["job_id"] ?? job["id"]) as? String else {
            if statusTool != nil { unknownJob = true }
            return
        }
        let state = (job["state"] ?? job["phase"] ?? job["status"]) as? String
        if ["completed", "failed", "cancelled", "canceled", "interrupted"].contains(state ?? "") {
            pendingJobs.removeValue(forKey: id)
            settledJobs.insert(id)
        } else if let statusTool { pendingJobs[id] = statusTool }
    }

    func hasActiveJobs() -> Bool {
        guard process?.isRunning == true else { return false }
        for (id, tool) in pendingJobs {
            if let reply = try? exchange(["method": "tools/call", "params": ["name": tool, "arguments": ["job_id": id]]]) {
                observeJob(reply, tool: tool)
            }
        }
        return unknownJob || !pendingJobs.isEmpty
    }

    func rotateSettledConnection(limit: Int) {
        if settledJobs.count >= limit && !hasActiveJobs() { stop() }
    }

    private func toolObject(_ data: Data) -> [String: Any]? {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = reply["result"] as? [String: Any], result["isError"] as? Bool != true else { return nil }
        var job = result["structuredContent"] as? [String: Any]
        if job == nil, let content = result["content"] as? [[String: Any]] {
            job = content.compactMap { item -> [String: Any]? in
                guard let text = item["text"] as? String else { return nil }
                return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
            }.first
        }
        return job
    }

    private func observeChatView(_ data: Data, tool: String, arguments: [String: Any]) {
        guard let result = toolObject(data) else {
            if ["chat_view_start_task", "chat_view_start_image_task", "chatgpt_send_text"].contains(tool) { chatViewAnswerPending = true }
            return
        }
        if ["chat_view_start_task", "chat_view_start_image_task"].contains(tool) {
            if let id = result["taskId"] as? String { chatViewTasks.insert(id) }
            else { chatViewAnswerPending = true }
        }
        if ["chat_view_task_status", "chat_view_image_task_status", "chatgpt_cancel_task"].contains(tool),
           let id = result["taskId"] as? String,
           let status = result["status"] as? String,
           ["completed", "partial", "failed", "cancelled", "interrupted"].contains(status),
           (result["integration"] as? [String: Any])?["lateAnswerPossible"] as? Bool != true,
           (result["integration"] as? [String: Any])?["activeGeneration"] as? Bool != true,
           (result["failure"] as? [String: Any])?["lateAnswerPossible"] as? Bool != true {
            chatViewTasks.remove(id)
        }
        if tool == "chatgpt_send_text" {
            if let panels = result["panels"] as? [[String: Any]] {
                chatViewPendingPanels.formUnion(panels.compactMap { $0["ok"] as? Bool == true ? $0["panelIndex"] as? Int : nil })
            } else { chatViewAnswerPending = true }
        }
        if ["chatgpt_copy_latest_answer", "chatgpt_collect_latest_answer"].contains(tool),
           let index = arguments["panel_index"] as? Int, let answer = result["answer"] as? String, !answer.isEmpty {
            chatViewPendingPanels.remove(index)
        }
    }

    nonisolated static func chatViewCanQuit(_ state: [String: Any]) -> Bool {
        guard let presentation = state["presentation"] as? [String: Any],
              presentation["mode"] as? String == "codex",
              presentation["windowHidden"] as? Bool == true,
              presentation["humanInterventionRequired"] as? Bool == false,
              state["activeTaskCount"] as? Int == 0,
              let busy = state["busyPanelIndices"] as? [Int], busy.isEmpty,
              let panels = state["panels"] as? [[String: Any]] else { return false }
        return panels.allSatisfy {
            $0["taskBusy"] as? Bool == false && $0["promptBusy"] as? Bool == false
                && $0["isLoading"] as? Bool == false && $0["queuedTaskCount"] as? Int == 0
                && ["idle", "completed"].contains($0["state"] as? String ?? "")
        }
    }

    static func quitChatView() async -> Bool {
        await MainActor.run {
            guard !Task.isCancelled else { return false }
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.pdg.ChatGPTSplitView")
            guard apps.allSatisfy({ !$0.isActive }) else { return false }
            return apps.allSatisfy { $0.terminate() }
        }
    }

    @MainActor
    static func launchChatView(_ executable: URL) async throws {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.pdg.ChatGPTSplitView").contains(where: { !$0.isTerminated }) { return }
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--automation-launch"]
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    private func failure(_ text: String) -> NSError {
        NSError(domain: "LinkDeck.WhisperMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func write(_ object: [String: Any]) throws {
        guard let input else { throw failure("위스퍼 MCP 연결이 없습니다.") }
        try input.write(contentsOf: JSONSerialization.data(withJSONObject: object) + Data([10]))
    }

    private func exchange(_ request: [String: Any]) throws -> Data {
        sequence += 1
        let id = sequence
        var request = request
        request["jsonrpc"] = "2.0"
        request["id"] = id
        try write(request)
        guard let output else { throw failure("위스퍼 MCP 연결이 없습니다.") }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let reply = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw failure("위스퍼 MCP가 잘못된 응답을 반환했습니다.")
                }
                if reply["id"] as? Int == id { return line }
            }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw failure("위스퍼 MCP 응답을 읽지 못했습니다.")
            }
            if ready > 0 {
                let chunk = output.availableData
                guard !chunk.isEmpty else { throw failure("위스퍼 MCP가 종료되었습니다. 앱 설치와 엔진 설정을 확인하세요.") }
                buffer.append(chunk)
                guard buffer.count <= 4_194_304 else { throw failure("위스퍼 MCP 응답이 너무 큽니다.") }
            }
        }
        throw failure("위스퍼 MCP 응답 시간이 초과되었습니다. 작업 목록을 확인한 뒤 재시도하세요.")
    }
}

@MainActor
enum StableWhisperMCPBridge {
    static let prefix = "linkdeck_whisper_"
    static let allowedTools: Set<String> = ["start_transcription", "list_transcriptions", "get_transcription_status",
                                           "cancel_transcription", "get_subtitle", "save_translated_subtitle"]

    static func executable() -> URL? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.pdg.stablewhisper"),
              let executable = Bundle(url: app)?.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return executable
    }

    static func response(to data: Data, client: StableWhisperMCPClient, executable: URL?,
                         fallback: () -> (status: Int, body: Data)) async -> (status: Int, body: Data) {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = request["method"] as? String, let id = request["id"] else { return fallback() }
        let params = request["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        guard method == "tools/list" || (method == "tools/call" && name.hasPrefix(prefix)) else { return fallback() }
        func encoded(_ object: [String: Any]) -> (status: Int, body: Data) {
            (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
        do {
            guard let executable else {
                if method == "tools/list" { return fallback() }
                throw NSError(domain: "LinkDeck.WhisperMCP", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Stable Whisper 앱을 설치하세요."])
            }
            if method == "tools/list" {
                let upstream = try await client.request(JSONSerialization.data(withJSONObject: ["method": "tools/list"]), executable: executable)
                let reply = try JSONSerialization.jsonObject(with: upstream) as? [String: Any]
                guard let result = reply?["result"] as? [String: Any], let tools = result["tools"] as? [[String: Any]] else {
                    throw NSError(domain: "LinkDeck.WhisperMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "위스퍼 도구 목록을 읽지 못했습니다."])
                }
                let forwarded = tools.compactMap { tool -> [String: Any]? in
                    guard let name = tool["name"] as? String, allowedTools.contains(name) else { return nil }
                    var tool = tool
                    tool["name"] = prefix + name
                    tool["description"] = "Stable Whisper via LinkDeck. " + (tool["description"] as? String ?? "")
                    return tool
                }
                var local = try JSONSerialization.jsonObject(with: fallback().body) as? [String: Any] ?? [:]
                var localResult = local["result"] as? [String: Any] ?? [:]
                localResult["tools"] = (localResult["tools"] as? [[String: Any]] ?? []) + forwarded
                local["result"] = localResult
                return encoded(local)
            }
            let upstreamName = String(name.dropFirst(prefix.count))
            guard allowedTools.contains(upstreamName), params["arguments"] == nil || params["arguments"] is [String: Any] else {
                return encoded(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Invalid Whisper tool or arguments"]])
            }
            let upstream = try await client.request(JSONSerialization.data(withJSONObject: ["method": "tools/call",
                "params": ["name": upstreamName, "arguments": params["arguments"] ?? [:]]]), executable: executable)
            var reply = try JSONSerialization.jsonObject(with: upstream) as? [String: Any] ?? [:]
            reply["id"] = id
            return encoded(reply)
        } catch {
            return encoded(["jsonrpc": "2.0", "id": id, "result": ["isError": true,
                "content": [["type": "text", "text": error.localizedDescription]]]])
        }
    }
}
