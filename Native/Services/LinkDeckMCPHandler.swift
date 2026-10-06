import Foundation

struct LinkDeckMCPButton {
    let id: String
    let title: String
    let page: String
    let device: String
    let press: String
    let action: PadAction
    let commandFileID: String

    var metadata: [String: String] {
        ["id": id, "title": title, "page": page, "device": device,
         "press": press, "action": action.kind.title]
    }
}

@MainActor
enum LinkDeckMCPHandler {
    static let protocolVersions = ["2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"]

    static func buttons(macPages: [LaunchPage], phonePages: [SmartphonePage]) -> [LinkDeckMCPButton] {
        var entries: [LinkDeckMCPButton] = []
        for (pageIndex, page) in macPages.enumerated() {
            for pad in page.pads where pad.action.kind != .none {
                entries.append(LinkDeckMCPButton(id: "mac:\(page.id):\(pad.id)",
                    title: pad.title, page: page.name, device: "Mac", press: "short",
                    action: pad.action, commandFileID: TerminalCommandFileStore.macButtonIdentifier(pageIndex: pageIndex, padID: pad.id)))
            }
        }
        for page in phonePages {
            for button in page.buttons {
                for (press, action) in [("short", button.action), ("long", button.longPressAction)] where action.kind != .none {
                    entries.append(LinkDeckMCPButton(id: "phone:\(button.id):\(press)",
                        title: button.title, page: page.name, device: "스마트폰", press: press,
                        action: action, commandFileID: button.id + (press == "long" ? "_long_press" : "")))
                }
                for shortcut in button.folderShortcuts {
                    for (press, action) in [("short", shortcut.action), ("long", shortcut.longPressAction)] where action.kind != .none {
                        entries.append(LinkDeckMCPButton(id: "folder:\(button.id):\(shortcut.id):\(press)",
                            title: shortcut.title, page: page.name + " / " + button.title,
                            device: "스마트폰 폴더", press: press, action: action,
                            commandFileID: shortcut.id + (press == "long" ? "_long_press" : "")))
                    }
                }
            }
        }
        return entries
    }

    static func response(to data: Data, buttons: [LinkDeckMCPButton],
                         sleepStatus: () -> MacSleepStatus = MacSleepStatus.current,
                         folderSyncStore: FolderPairStore? = nil,
                         execute: (LinkDeckMCPButton) throws -> String) -> (status: Int, body: Data) {
        func encoded(_ object: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        }
        func toolText(_ text: String, isError: Bool = false) -> [String: Any] {
            var response: [String: Any] = ["content": [["type": "text", "text": text]]]
            if isError { response["isError"] = true }
            return response
        }
        func jsonText(_ object: [String: Any]) -> String {
            String(decoding: encoded(object), as: UTF8.self)
        }
        func pairForSyncTool(_ arguments: [String: Any], store: FolderPairStore) -> (FolderPair?, String?) {
            guard arguments.keys.allSatisfy({ $0 == "pair_id" }) else {
                return (nil, "지원하지 않는 인수가 있습니다.")
            }
            let pairID: UUID?
            if let value = arguments["pair_id"] {
                guard let string = value as? String, let parsedID = UUID(uuidString: string) else {
                    return (nil, "pair_id는 목록 도구에서 받은 UUID여야 합니다.")
                }
                pairID = parsedID
            } else {
                pairID = store.selectedPairID
            }
            guard let pairID else {
                return (nil, "선택된 동기화 목록이 없습니다. 목록을 조회한 뒤 pair_id를 지정하세요.")
            }
            guard let pair = store.pairs.first(where: { $0.id == pairID }) else {
                return (nil, "해당 동기화 목록을 찾을 수 없습니다. 목록을 다시 조회하세요.")
            }
            return (pair, nil)
        }
        func direction(_ pair: FolderPair) -> String {
            switch pair.syncMode {
            case .aToB: "A → B"
            case .bToA: "B → A"
            case .twoWay: "양방향"
            }
        }
        func syncStatus(_ state: SyncState) -> String {
            switch state {
            case .idle: "idle"
            case .syncing: "syncing"
            case .waitingForFolder: "waiting_for_folder"
            case .succeeded: "completed"
            case .failed: "failed"
            }
        }
        func syncStatusPayload(_ pair: FolderPair, selected: Bool? = nil, store: FolderPairStore) -> [String: Any] {
            let state = store.state(for: pair)
            var payload: [String: Any] = [
                "pair_id": pair.id.uuidString,
                "name": pair.name,
                "selected": selected ?? (store.selectedPairID == pair.id),
                "enabled": pair.isEnabled,
                "direction": direction(pair),
                "endpoint_a": pair.githubSync?.endpointSide == .a ? "GitHub" : "local_folder",
                "endpoint_b": pair.githubSync?.endpointSide == .b ? "GitHub" : "local_folder",
                "delete_extra_files": pair.options.deleteExtraFiles,
                "status": syncStatus(state)
            ]
            if let lastSyncedAt = pair.lastSyncedAt {
                payload["last_synced_at"] = ISO8601DateFormatter().string(from: lastSyncedAt)
            }
            if case .failed(let message) = state { payload["error"] = message }
            return payload
        }
        guard let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (200, encoded(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]]))
        }
        let id = request["id"] ?? NSNull()
        func failure(_ code: Int, _ message: String) -> (Int, Data) {
            (200, encoded(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]))
        }
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return failure(-32600, "Invalid Request")
        }
        if let requestID = request["id"], !(requestID is String) && !(requestID is NSNumber) {
            return failure(-32600, "Invalid request ID")
        }
        if request["id"] == nil {
            return method.hasPrefix("notifications/") ? (202, Data()) : failure(-32600, "Request ID required")
        }
        let params = request["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            result = ["protocolVersion": protocolVersions.contains(requested) ? requested : "2025-06-18",
                      "capabilities": ["tools": ["listChanged": false]],
                      "serverInfo": ["name": "LinkDeck", "version": "1.0.0"],
                      "instructions": "List saved LinkDeck buttons before executing them. For FolderSync, list sync pairs first, then start a sync only when the user asks. A sync uses the saved direction and options and may overwrite or delete destination files. Start returns immediately; check sync status to confirm completion. Buttons can launch apps, send shortcuts or run saved terminal commands on the user's Mac."]
        case "ping": result = [:]
        case "tools/list":
            result = ["tools": [
                ["name": "linkdeck_get_sleep_status", "description": "Read the Mac's current caffeinate sleep-prevention state. 불면증 means sleep prevention is active; 숙면 means caffeinate sleep prevention is off (not that the Mac is currently asleep). Checks actual active assertions, not the last button pressed. Other apps may independently prevent sleep.",
                 "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
                 "annotations": ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]],
                ["name": "linkdeck_list_buttons", "description": "List configured LinkDeck buttons and their IDs. No command contents or clipboard text are returned.",
                 "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
                 "annotations": ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]],
                ["name": "linkdeck_press_button", "description": "Execute an existing LinkDeck button on the user's Mac. Use an ID from linkdeck_list_buttons. May launch apps, send shortcuts, change web pages or run saved terminal commands. Ask the user before executing actions they have not requested.",
                 "inputSchema": ["type": "object", "properties": ["button_id": ["type": "string"]], "required": ["button_id"], "additionalProperties": false],
                 "annotations": ["readOnlyHint": false, "destructiveHint": true, "openWorldHint": true, "idempotentHint": false]],
                ["name": "linkdeck_folder_sync_list", "description": "List saved FolderSync pairs, selected pair, direction, status, and whether extra destination files may be deleted. Does not expose local paths.",
                 "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
                 "annotations": ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]],
                ["name": "linkdeck_folder_sync_status", "description": "Read the state and last completion time of a FolderSync pair. Omit pair_id to use the selected pair.",
                 "inputSchema": ["type": "object", "properties": ["pair_id": ["type": "string"]], "additionalProperties": false],
                 "annotations": ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]],
                ["name": "linkdeck_folder_sync_start", "description": "Start a saved FolderSync pair using its configured direction and options. Call only when the user explicitly asks to sync. The operation can overwrite or delete files. Use linkdeck_folder_sync_list to find pair_id; omit pair_id to use the selected pair. Returns immediately; check status for completion.",
                 "inputSchema": ["type": "object", "properties": ["pair_id": ["type": "string"]], "additionalProperties": false],
                 "annotations": ["readOnlyHint": false, "destructiveHint": true, "openWorldHint": true, "idempotentHint": false]]
            ]]
        case "tools/call":
            guard let name = params["name"] as? String else { return failure(-32602, "Tool name required") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            switch name {
            case "linkdeck_get_sleep_status":
                guard arguments.isEmpty else { return failure(-32602, "Unexpected arguments") }
                let status = sleepStatus()
                let payload = try? JSONEncoder().encode(status)
                result = ["isError": status.sleepPreventionEnabled == nil,
                          "content": [["type": "text", "text": String(decoding: payload ?? Data(), as: UTF8.self)]]]
            case "linkdeck_list_buttons":
                guard arguments.isEmpty else { return failure(-32602, "Unexpected arguments") }
                let catalog = encoded(["buttons": buttons.map(\.metadata)])
                result = ["content": [["type": "text", "text": String(decoding: catalog, as: UTF8.self)]]]
            case "linkdeck_press_button":
                guard arguments.count == 1, let buttonID = arguments["button_id"] as? String else {
                    return failure(-32602, "button_id required")
                }
                guard let button = buttons.first(where: { $0.id == buttonID }) else {
                    result = ["isError": true, "content": [["type": "text", "text": "버튼이 없거나 설정이 변경됐습니다. 목록을 다시 조회하세요."]]]
                    break
                }
                do {
                    result = ["content": [["type": "text", "text": try execute(button)]]]
                } catch {
                    result = ["isError": true, "content": [["type": "text", "text": error.localizedDescription]]]
                }
            case "linkdeck_folder_sync_list":
                guard arguments.isEmpty else { return failure(-32602, "Unexpected arguments") }
                guard let folderSyncStore else {
                    result = toolText("FolderSync를 사용할 수 없습니다.", isError: true)
                    break
                }
                let pairs = folderSyncStore.pairs.map { syncStatusPayload($0, store: folderSyncStore) }
                result = toolText(jsonText(["sync_pairs": pairs]))
            case "linkdeck_folder_sync_status":
                guard let folderSyncStore else {
                    result = toolText("FolderSync를 사용할 수 없습니다.", isError: true)
                    break
                }
                let (pair, error) = pairForSyncTool(arguments, store: folderSyncStore)
                if let error {
                    result = toolText(error, isError: true)
                } else if let pair {
                    result = toolText(jsonText(syncStatusPayload(pair, store: folderSyncStore)))
                } else {
                    result = toolText("동기화 목록을 찾을 수 없습니다.", isError: true)
                }
            case "linkdeck_folder_sync_start":
                guard let folderSyncStore else {
                    result = toolText("FolderSync를 사용할 수 없습니다.", isError: true)
                    break
                }
                let (selectedPair, selectionError) = pairForSyncTool(arguments, store: folderSyncStore)
                if let selectionError {
                    result = toolText(selectionError, isError: true)
                    break
                }
                guard let selectedPair else {
                    result = toolText("동기화 목록을 찾을 수 없습니다.", isError: true)
                    break
                }
                let (pair, startError) = folderSyncStore.startSyncFromMCP(selectedPair.id)
                if let startError {
                    result = toolText(startError, isError: true)
                } else if let pair {
                    result = toolText(jsonText([
                        "pair_id": pair.id.uuidString,
                        "name": pair.name,
                        "direction": direction(pair),
                        "status": "started",
                        "next_step": "Call linkdeck_folder_sync_status to confirm completion."
                    ]))
                } else {
                    result = toolText("동기화를 시작하지 못했습니다.", isError: true)
                }
            default: return failure(-32602, "Unknown tool")
            }
        default: return failure(-32601, "Method not found")
        }
        return (200, encoded(["jsonrpc": "2.0", "id": id, "result": result]))
    }
}
