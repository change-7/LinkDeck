import AppKit

@MainActor
final class SubtitlePipelineRuntime {
    static let shared = SubtitlePipelineRuntime()
    let whisper = StableWhisperMCPClient()
    let appAPIs: AppAPIMCPBridge
    private(set) var manager: SubtitlePipelineManager?
    private var initializationError: String?
    private var apps: [RegisteredAppAPI] = []

    private init() {
        appAPIs = AppAPIMCPBridge(sharedWhisper: whisper)
        do {
            let storage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LinkDeck/subtitle-pipeline/state.json")
            manager = try SubtitlePipelineManager(storage: storage, automatic: false) { [weak self] step, tool, arguments in
                guard let self else { throw SubtitlePipelineFailure("Pipeline runtime unavailable") }
                return try await self.call(step, tool: tool, arguments: arguments)
            }
            manager?.externalBusy = { [weak self] step in await self?.externalBusy(step) ?? true }
        } catch { initializationError = error.localizedDescription }
    }

    private func toolkit() throws -> RegisteredAppAPI {
        let matches = apps.filter { $0.approved && $0.manifest.id == "video_toolkit" }
        guard matches.count == 1, let app = matches.first,
              ["burn_subtitles", "get_subtitle_status", "cancel_subtitle_render"].allSatisfy(app.manifest.tools.contains) else {
            throw SubtitlePipelineFailure("Register and approve Video Simple Toolkit's app API in LinkDeck")
        }
        return app
    }

    private func bindings() throws -> [String: String] {
        guard let executable = StableWhisperMCPBridge.executable() else { throw SubtitlePipelineFailure("Install Stable Whisper first") }
        return ["whisper": executable.resolvingSymlinksInPath().path, "render": try toolkit().approvalKey]
    }

    private func shareStack() throws -> RegisteredAppAPI {
        let matches = apps.filter { $0.approved && ["share_stack", "sharestack"].contains($0.manifest.id) }
        guard matches.count == 1, let app = matches.first,
              ["prepare_media_job", "register_processed_media", "get_job"].allSatisfy(app.manifest.tools.contains) else {
            throw SubtitlePipelineFailure("Register and approve ShareStack's media resolution and result registration API in LinkDeck")
        }
        return app
    }

    private func isPrivateShareStackTool(_ name: String, apps: [RegisteredAppAPI]) -> Bool {
        apps.contains { app in
            ["share_stack", "sharestack"].contains(app.manifest.id) &&
            ["prepare_media_job", "register_processed_media"].contains { app.manifest.prefix + $0 == name }
        }
    }

    private func appResponse(to data: Data, apps: [RegisteredAppAPI], fallback: () async -> (status: Int, body: Data)) async -> (status: Int, body: Data) {
        let response = await appAPIs.response(to: data, apps: apps, fallback: fallback)
        let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard request?["method"] as? String == "tools/list",
              var object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              var result = object["result"] as? [String: Any] else { return response }
        let hidden = Set(apps.filter { ["share_stack", "sharestack"].contains($0.manifest.id) }
            .flatMap { app in ["prepare_media_job", "register_processed_media"].map { app.manifest.prefix + $0 } })
        result["tools"] = (result["tools"] as? [[String: Any]] ?? []).filter { !hidden.contains($0["name"] as? String ?? "") }
        object["result"] = result
        return (200, (try? JSONSerialization.data(withJSONObject: object)) ?? response.body)
    }

    private func shareStackBindings() throws -> [String: String] {
        var result = try bindings()
        result["share_stack"] = try shareStack().approvalKey
        return result
    }

    private func shareStackCall(_ tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        let app = try shareStack()
        let response: Data
        do { response = try await appAPIs.call(app, tool: tool, arguments: arguments) }
        catch { throw SubtitlePipelineFailure("ShareStack media request failed") }
        guard let reply = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = reply["result"] as? [String: Any], result["isError"] as? Bool != true else {
            throw SubtitlePipelineFailure("ShareStack media request failed")
        }
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first ?? ""
        guard let object = result["structuredContent"] as? [String: Any]
                ?? (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw SubtitlePipelineFailure("ShareStack returned an invalid media response")
        }
        return object
    }

    private func call(_ step: SubtitlePipelineStep, tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        var args = arguments
        let binding = args.removeValue(forKey: "_pipeline_bindings") as? [String: String] ?? [:]
        let response: Data
        if step == .render {
            let app = try toolkit()
            guard binding["render"] == app.approvalKey else { throw SubtitlePipelineFailure("Renderer registration or approval changed; restore the original app registration") }
            response = try await appAPIs.call(app, tool: tool, arguments: args)
        } else if step == .publish {
            let app = try shareStack()
            guard binding["share_stack"] == app.approvalKey else { throw SubtitlePipelineFailure("ShareStack registration or approval changed; restore the original app registration") }
            response = try await appAPIs.call(app, tool: tool, arguments: args)
        } else {
            guard let executable = StableWhisperMCPBridge.executable(), binding["whisper"] == executable.resolvingSymlinksInPath().path else {
                throw SubtitlePipelineFailure("Stable Whisper installation path changed or app unavailable")
            }
            response = try await whisper.request(JSONSerialization.data(withJSONObject: ["method": "tools/call", "params": ["name": tool, "arguments": args]]), executable: executable)
        }
        guard let reply = try JSONSerialization.jsonObject(with: response) as? [String: Any], let result = reply["result"] as? [String: Any] else { throw SubtitlePipelineFailure("Invalid app response") }
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first ?? ""
        let object = result["structuredContent"] as? [String: Any] ?? (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        if result["isError"] as? Bool == true {
            let error = object?["error"] as? String ?? text
            if ["get_subtitle_status", "get_transcription_status"].contains(tool), error.lowercased().contains("unknown"), error.lowercased().contains("job") {
                return ["state": "interrupted", "error": error]
            }
            throw SubtitlePipelineFailure(error)
        }
        guard let object else { throw SubtitlePipelineFailure("Missing structured app result") }
        return object
    }

    private func externalBusy(_ step: SubtitlePipelineStep) async -> Bool {
        let whisperBusy = await whisper.hasActiveJobs()
        let rendererBusy: Bool
        if let app = try? toolkit() { rendererBusy = await appAPIs.client(app).hasActiveJobs() }
        else { rendererBusy = false }
        if manager?.heavyJobLimit == 1 {
            return whisperBusy || rendererBusy
        }
        return step == .transcription ? whisperBusy : rendererBusy
    }

    func response(to data: Data, apps: [RegisteredAppAPI], fallback: () async -> (status: Int, body: Data)) async -> (status: Int, body: Data) {
        self.apps = apps
        manager?.resume()
        let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = request?["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        if request?["method"] as? String == "tools/call", isPrivateShareStackTool(name, apps: apps) {
            return failure(data, "ShareStack media resolution and publishing are available only through the LinkDeck subtitle pipeline")
        }
        guard let manager else {
            if SubtitlePipelineMCPBridge.names.map({ "linkdeck_" + $0 }).contains(name) || name.hasSuffix("start_transcription") || name.hasSuffix("burn_subtitles") || name.hasSuffix("start_download") {
                return failure(data, initializationError ?? "Pipeline unavailable")
            }
            return await appResponse(to: data, apps: apps, fallback: fallback)
        }
        var legacyStep: SubtitlePipelineStep?
        if request?["method"] as? String == "tools/call" {
            if name == "linkdeck_whisper_start_transcription" || apps.contains(where: { name == $0.manifest.prefix + "start_transcription" && $0.bundleID == "com.pdg.stablewhisper" }) { legacyStep = .transcription }
            if apps.contains(where: { $0.manifest.id == "video_toolkit" && ["burn_subtitles", "start_download"].contains(String(name.dropFirst($0.manifest.prefix.count))) && name.hasPrefix($0.manifest.prefix) }) { legacyStep = .render }
        }
        var legacyToken: String?
        if let legacyStep {
            guard let token = manager.claimLegacy(legacyStep) else {
                return failure(data, "Subtitle pipeline/app slot is occupied. Retry when the current job finishes.")
            }
            legacyToken = token
            if await externalBusy(legacyStep) {
                manager.releaseLegacy(token)
                return failure(data, "Subtitle pipeline/app slot is occupied. Retry when the current job finishes.")
            }
        }
        defer { if let legacyToken { manager.releaseLegacy(legacyToken) } }
        let bridge = SubtitlePipelineMCPBridge(manager: manager, bindings: { try self.bindings() },
            shareStackBindings: { try self.shareStackBindings() },
            resolveShareStack: { tool, arguments in try await self.shareStackCall(tool, arguments: arguments) })
        return await bridge.response(to: data) {
            await self.appResponse(to: data, apps: apps, fallback: fallback)
        }
    }

    private func failure(_ data: Data, _ message: String) -> (Int, Data) {
        let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (200, (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": request?["id"] ?? NSNull(), "result": ["isError": true, "content": [["type": "text", "text": message]]]])) ?? Data())
    }
}
