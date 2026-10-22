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

    private func call(_ step: SubtitlePipelineStep, tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        var args = arguments
        let binding = args.removeValue(forKey: "_pipeline_bindings") as? [String: String] ?? [:]
        let response: Data
        if step == .render {
            let app = try toolkit()
            guard binding["render"] == app.approvalKey else { throw SubtitlePipelineFailure("Renderer registration or approval changed; restore the original app registration") }
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
        guard let manager else {
            if SubtitlePipelineMCPBridge.names.map({ "linkdeck_" + $0 }).contains(name) || name.hasSuffix("start_transcription") || name.hasSuffix("burn_subtitles") || name.hasSuffix("start_download") {
                return failure(data, initializationError ?? "Pipeline unavailable")
            }
            return await appAPIs.response(to: data, apps: apps, fallback: fallback)
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
        let bridge = SubtitlePipelineMCPBridge(manager: manager, bindings: { try self.bindings() })
        return await bridge.response(to: data) {
            await self.appAPIs.response(to: data, apps: apps, fallback: fallback)
        }
    }

    private func failure(_ data: Data, _ message: String) -> (Int, Data) {
        let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (200, (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": request?["id"] ?? NSNull(), "result": ["isError": true, "content": [["type": "text", "text": message]]]])) ?? Data())
    }
}
