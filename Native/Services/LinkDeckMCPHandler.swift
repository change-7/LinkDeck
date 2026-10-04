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
                         execute: (LinkDeckMCPButton) throws -> String) -> (status: Int, body: Data) {
        func encoded(_ object: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
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
                      "instructions": "List saved LinkDeck buttons first. Execute a button only when the user asks for that action. Buttons can launch apps, send shortcuts or run saved terminal commands on the user's Mac."]
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
            default: return failure(-32602, "Unknown tool")
            }
        default: return failure(-32601, "Method not found")
        }
        return (200, encoded(["jsonrpc": "2.0", "id": id, "result": result]))
    }
}
