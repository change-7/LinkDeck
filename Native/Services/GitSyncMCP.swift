import Foundation

@MainActor
enum GitSyncMCP {
    static var tools: [[String: Any]] {
        [
            tool("list", "List registered Git sync configurations without credentials or local paths.", [:], []),
            tool("start", "Start a registered Git sync. Returns a job ID; query status until finished.",
                 ["sync_id": ["type": "string"], "direction": ["type": "string", "enum": ["pull", "push", "bidirectional"]]], ["sync_id"]),
            tool("status", "Read Git sync progress and final results. Supply exactly one job_id or sync_id.",
                 ["job_id": ["type": "string"], "sync_id": ["type": "string"]], []),
            tool("cancel", "Request cancellation of an active job. Completed commits and pushes are preserved; check status.",
                 ["job_id": ["type": "string"]], ["job_id"])
        ]
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["name": "linkdeck_git_sync_" + name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
         "annotations": ["readOnlyHint": name == "list" || name == "status", "destructiveHint": name == "start", "openWorldHint": name == "start"]]
    }

    static func response(name: String, arguments: [String: Any], store: GitSyncStore?) -> [String: Any] {
        func text(_ value: String, error: Bool = false) -> [String: Any] {
            ["content": [["type": "text", "text": value]], "isError": error]
        }
        func json(_ value: Any) -> [String: Any] {
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
                return text("결과를 인코딩하지 못했습니다.", error: true)
            }
            return text(String(decoding: data, as: UTF8.self))
        }
        func jobJSON(_ job: GitSyncJob) throws -> Any {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try JSONSerialization.jsonObject(with: encoder.encode(job))
        }
        func id(_ key: String) throws -> UUID {
            guard let string = arguments[key] as? String, let id = UUID(uuidString: string) else {
                throw NSError(domain: "GitSyncMCP", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(key)는 목록에서 받은 UUID여야 합니다."])
            }
            return id
        }
        guard let store else { return text("Git Sync를 사용할 수 없습니다.", error: true) }
        do {
            switch name {
            case "linkdeck_git_sync_list":
                guard arguments.isEmpty else { return text("지원하지 않는 인수가 있습니다.", error: true) }
                return json(["syncs": store.configurations.map { config -> [String: Any] in
                    ["sync_id": config.id.uuidString, "name": config.name,
                     "repository": URL(fileURLWithPath: config.folder.displayPath).lastPathComponent,
                     "remote": config.remote, "branch": config.branch, "direction": config.direction.rawValue,
                     "status": store.latestJob(syncID: config.id)?.phase.rawValue ?? "idle"]
                }])
            case "linkdeck_git_sync_start":
                guard Set(arguments.keys).isSubset(of: ["sync_id", "direction"]) else { return text("지원하지 않는 인수가 있습니다.", error: true) }
                var direction: GitSyncDirection?
                if let value = arguments["direction"] {
                    guard let string = value as? String, let parsed = GitSyncDirection(rawValue: string) else {
                        return text("direction은 pull, push, bidirectional 중 하나여야 합니다.", error: true)
                    }
                    direction = parsed
                }
                let job = try store.start(syncID: id("sync_id"), direction: direction)
                return json(["job_id": job.id.uuidString, "sync_id": job.syncID.uuidString,
                             "status": job.phase.rawValue, "direction": job.direction.rawValue])
            case "linkdeck_git_sync_status":
                guard arguments.count == 1, Set(arguments.keys).isSubset(of: ["job_id", "sync_id"]) else {
                    return text("job_id 또는 sync_id 하나만 지정하세요.", error: true)
                }
                let job: GitSyncJob?
                if arguments["job_id"] != nil {
                    let jobID = try id("job_id")
                    job = store.jobs.first { $0.id == jobID }
                } else {
                    let syncID = try id("sync_id")
                    guard store.configurations.contains(where: { $0.id == syncID }) else { return text("등록된 Git Sync가 없습니다.", error: true) }
                    job = store.latestJob(syncID: syncID)
                    if job == nil { return json(["sync_id": syncID.uuidString, "status": "idle"]) }
                }
                guard let job else { return text("작업을 찾을 수 없습니다.", error: true) }
                return json(try jobJSON(job))
            case "linkdeck_git_sync_cancel":
                guard arguments.count == 1, arguments["job_id"] != nil else { return text("job_id 하나만 지정하세요.", error: true) }
                let jobID = try id("job_id")
                guard store.jobs.contains(where: { $0.id == jobID }) else { return text("작업을 찾을 수 없습니다.", error: true) }
                Task { await store.cancel(jobID: jobID) }
                return json(["job_id": jobID.uuidString, "status": "cancellation_requested"])
            default: return text("알 수 없는 Git 도구입니다.", error: true)
            }
        } catch {
            return text(error.localizedDescription, error: true)
        }
    }
}
