import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class LinkDeckInstructionsGateTests: XCTestCase {
    func testMalformedEnvelopesNeverReachBridgedTools() async throws {
        let gate = LinkDeckInstructionsGate()
        var calls = 0
        for envelope: [String: Any] in [
            ["id": 1, "method": "tools/call", "params": ["name": "linkdeck_start_subtitle_batch"]],
            ["jsonrpc": "1.0", "id": 1, "method": "tools/call"],
            ["jsonrpc": "2.0", "id": [1], "method": "tools/call"],
            ["jsonrpc": "2.0", "method": "tools/call"]
        ] {
            let response = await gate.response(to: try JSONSerialization.data(withJSONObject: envelope),
                instructions: CustomInstructions(), revision: UUID()) { _ in
                    calls += 1
                    return (200, Data())
                }
            XCTAssertFalse(response.body.isEmpty)
        }
        XCTAssertEqual(calls, 0)
    }

    func testHTTPEntryGuardsAppToolsAndPublishesReceiptSchemaWithoutChangingAppArguments() async throws {
        let server = LinkDeckMCPServer()
        let preferences = CustomInstructions(text: "実機接続の確認", isEnabled: true)
        var revision = UUID()
        server.instructionsProvider = { (preferences, revision) }
        var appCalls = 0
        server.handle = { data in
            let request = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let params = request["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            if request["method"] as? String == "tools/list" {
                return (200, try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1,
                    "result": ["tools": [["name": "linkdeck_app_test", "inputSchema": ["type": "object",
                        "properties": ["value": ["type": "string"]], "required": ["value"], "additionalProperties": false]]]]]))
            }
            if name == "linkdeck_app_test" {
                // The bridge must receive only its original, validated arguments.
                let arguments = params["arguments"] as? [String: String]
                XCTAssertEqual(arguments, ["value": "test"])
                appCalls += 1
                return (200, try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": ["content": []]]))
            }
            return LinkDeckMCPHandler.response(to: data, buttons: [], customInstructions: preferences) { _ in
                XCTFail("No button should execute"); return ""
            }
        }
        let url = try await server.start()
        defer { server.stop() }
        func send(_ method: String, _ params: [String: Any] = [:], authenticated: Bool = true) async throws -> [String: Any] {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if authenticated { request.setValue("Bearer " + server.token, forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
            let (data, response) = try await URLSession.shared.data(for: request)
            if !authenticated {
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
                return [:]
            }
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let catalog = try await send("tools/list")
        let tools = try XCTUnwrap((catalog["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let schema = try XCTUnwrap(tools.first?["inputSchema"] as? [String: Any])
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), ["value", "instructions_receipt"])
        XCTAssertNotNil((schema["properties"] as? [String: Any])?["instructions_receipt"])
        let blocked = try await send("tools/call", ["name": "linkdeck_app_test", "arguments": ["value": "test"]])
        XCTAssertEqual((blocked["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertEqual(appCalls, 0)
        let read = try await send("tools/call", ["name": "linkdeck_list_buttons"])
        let content = try XCTUnwrap((read["result"] as? [String: Any])?["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let receipt = try XCTUnwrap((payload["custom_instructions"] as? [String: Any])?["instructions_receipt"] as? String)
        let params: [String: Any] = ["name": "linkdeck_app_test", "arguments": ["value": "test", "instructions_receipt": receipt]]
        _ = try await send("tools/call", params, authenticated: false)
        XCTAssertEqual(appCalls, 0)
        _ = try await send("tools/call", params)
        XCTAssertEqual(appCalls, 1)
        _ = try await send("tools/call", params)
        XCTAssertEqual(appCalls, 1)
        // Even saving identical content invalidates all previously issued receipts.
        revision = UUID()
        _ = try await send("tools/call", params)
        XCTAssertEqual(appCalls, 1)
    }

    func testEveryToolCallRequiresFreshReceiptAndChangesInvalidateOutstandingReceipts() async throws {
        let gate = LinkDeckInstructionsGate()
        var instructions = CustomInstructions(text: "한국어로 답변", isEnabled: true)
        var revision = UUID()
        var executions = 0
        let button = LinkDeckMCPButton(id: "test", title: "test", page: "test", device: "Mac", press: "short",
            action: PadAction(kind: .app, value: "test.app"), commandFileID: "test")
        func send(_ name: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1,
                "method": "tools/call", "params": ["name": name, "arguments": arguments]])
            let response = await gate.response(to: data, instructions: instructions, revision: revision) { forwarded in
                LinkDeckMCPHandler.response(to: forwarded, buttons: [button], customInstructions: instructions) { _ in
                    executions += 1
                    return "executed"
                }
            }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        }
        func receipt(_ name: String = "linkdeck_get_custom_instructions") async throws -> String {
            let response = try await send(name)
            let result = try XCTUnwrap(response["result"] as? [String: Any])
            let content = try XCTUnwrap(result["content"] as? [[String: Any]])
            let text = try XCTUnwrap(content.first?["text"] as? String)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let preferences = name == "linkdeck_list_buttons" ? try XCTUnwrap(payload["custom_instructions"] as? [String: Any]) : payload
            XCTAssertEqual(preferences["instructions"] as? String, instructions.isEnabled ? instructions.text : "")
            return try XCTUnwrap(preferences["instructions_receipt"] as? String)
        }
        let blocked = try await send("linkdeck_press_button", ["button_id": "test"])
        XCTAssertEqual((blocked["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertEqual(executions, 0)
        // A different client cannot execute merely because another client read preferences.
        let first = try await receipt()
        _ = try await send("linkdeck_press_button", ["button_id": "test"])
        XCTAssertEqual(executions, 0)
        _ = try await send("linkdeck_press_button", ["button_id": "test", "instructions_receipt": first])
        XCTAssertEqual(executions, 1)
        _ = try await send("linkdeck_press_button", ["button_id": "test", "instructions_receipt": first])
        XCTAssertEqual(executions, 1)
        let stale = try await receipt("linkdeck_list_buttons")
        instructions.text = "変更済み"
        revision = UUID()
        _ = try await send("linkdeck_press_button", ["button_id": "test", "instructions_receipt": stale])
        XCTAssertEqual(executions, 1)
        let fresh = try await receipt("linkdeck_list_buttons")
        _ = try await send("linkdeck_press_button", ["button_id": "test", "instructions_receipt": fresh])
        XCTAssertEqual(executions, 2)
        instructions.isEnabled = false
        revision = UUID()
        let disabled = try await receipt()
        _ = try await send("linkdeck_press_button", ["button_id": "test", "instructions_receipt": disabled])
        XCTAssertEqual(executions, 3)
    }
}
