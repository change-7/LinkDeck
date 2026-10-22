import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class LinkDeckMCPTests: XCTestCase {
    func testInstalledWhisperBridge_discoversCallsAndRejectsUnknownTools() async throws {
        guard let executable = StableWhisperMCPBridge.executable() else { throw XCTSkip("Stable Whisper is not installed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("linkdeck-whisper-test-\(UUID())")
        let client = StableWhisperMCPClient(jobsDirectory: directory)
        func invoke(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
            let data = try request(method, params: params)
            let response = await StableWhisperMCPBridge.response(to: data, client: client, executable: executable) {
                LinkDeckMCPHandler.response(to: data, buttons: []) { _ in XCTFail("Must not execute buttons"); return "" }
            }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        }
        do {
            let listed = try await invoke("tools/list")
            let result = try XCTUnwrap(listed["result"] as? [String: Any])
            let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.filter { ($0["name"] as? String ?? "").hasPrefix("linkdeck_whisper_") }.count, 6)
            let start = try XCTUnwrap(tools.first { $0["name"] as? String == "linkdeck_whisper_start_transcription" })
            let schema = try XCTUnwrap(start["inputSchema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertNotNil(properties["url"])
            XCTAssertNotNil(properties["file_path"])
            let jobs = try await invoke("tools/call", ["name": "linkdeck_whisper_list_transcriptions", "arguments": [:]])
            XCTAssertEqual(jobs["id"] as? Int, 1)
            let jobsResult = try XCTUnwrap(jobs["result"] as? [String: Any])
            XCTAssertEqual(jobsResult["isError"] as? Bool, false)
            let invalid = try await invoke("tools/call", ["name": "linkdeck_whisper_start_transcription", "arguments": ["file_path": "/missing/linkdeck-test.mp4"]])
            XCTAssertEqual((invalid["result"] as? [String: Any])?["isError"] as? Bool, true)
            let unknown = try await invoke("tools/call", ["name": "linkdeck_whisper_run_command", "arguments": [:]])
            XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32602)
        } catch {
            await client.stop()
            throw error
        }
        await client.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func testTranscriptionDiscovery_exposesAppIdentityAndExplainsLaunchLimit() throws {
        let button = LinkDeckMCPButton(id: "whisper", title: "전사", page: "Page", device: "Mac", press: "short",
            action: PadAction(kind: .app, value: "com.example.stable-whisper"), commandFileID: "whisper")
        XCTAssertEqual(button.metadata["app_bundle_identifier"], "com.example.stable-whisper")
        let shortcut = LinkDeckMCPButton(id: "shortcut", title: "전사", page: "Page", device: "Mac", press: "short",
            action: PadAction(kind: .shortcut, value: "private shortcut", targetAppBundleIdentifier: "com.example.stable-whisper"), commandFileID: "shortcut")
        XCTAssertEqual(shortcut.metadata["app_bundle_identifier"], "com.example.stable-whisper")
        XCTAssertFalse(shortcut.metadata.values.contains("private shortcut"))
        let initialized = LinkDeckMCPHandler.response(to: try request("initialize", params: ["protocolVersion": "2025-06-18"]), buttons: [button]) { _ in XCTFail("Must not execute"); return "" }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: initialized.body) as? [String: Any])
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let instructions = try XCTUnwrap(result["instructions"] as? String)
        XCTAssertTrue(instructions.contains("Stable Whisper"))
        XCTAssertTrue(instructions.contains("linkdeck_whisper_*"))
        let listed = LinkDeckMCPHandler.response(to: try request("tools/list"), buttons: [button]) { _ in XCTFail("Must not execute"); return "" }
        XCTAssertTrue(String(decoding: listed.body, as: UTF8.self).contains("Stable Whisper"))
    }

    private func request(_ method: String, params: [String: Any] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
    }

    func testQuitToolUsesOnlyTheCheckedExistingButtonAndRejectsInjectedTargets() throws {
        var button = LinkDeckMCPButton(id: "app-button", title: "App", page: "Page", device: "Mac", press: "short",
            action: PadAction(kind: .app, value: "test.app", allowsAppTermination: true), commandFileID: "app-button")
        var calls = 0
        func invoke(_ arguments: [String: Any], buttons: [LinkDeckMCPButton]) throws -> String {
            let response = LinkDeckMCPHandler.response(to: try request("tools/call", params: ["name": "linkdeck_quit_app", "arguments": arguments]), buttons: buttons) { saved in
                calls += 1
                XCTAssertEqual(saved.action.kind, .appQuit)
                XCTAssertEqual(saved.action.value, "test.app")
                return "quit requested"
            }
            return String(decoding: response.body, as: UTF8.self)
        }
        XCTAssertEqual(button.metadata["can_quit_app"], "true")
        XCTAssertTrue(try invoke(["button_id": "app-button"], buttons: [button]).contains("quit requested"))
        button = LinkDeckMCPButton(id: button.id, title: button.title, page: button.page, device: button.device, press: button.press,
            action: PadAction(kind: .app, value: "test.app"), commandFileID: button.commandFileID)
        XCTAssertEqual(button.metadata["can_quit_app"], "false")
        XCTAssertTrue(try invoke(["button_id": "app-button"], buttons: [button]).contains("isError"))
        XCTAssertTrue(try invoke(["button_id": "app-button"], buttons: []).contains("isError"))
        let invalidArguments: [[String: Any]] = [["bundle_identifier": "test.app"], ["button_id": "app-button", "force": true], ["button_id": "app-button", "command": "killall"]]
        for arguments in invalidArguments {
            XCTAssertTrue(try invoke(arguments, buttons: [button]).contains("-32602"))
        }
        XCTAssertEqual(calls, 1)
    }

    func testQuitPermissionIsDiscoverableForAlternateAppButtons() {
        let button = SmartphoneButton(id: "phone", action: PadAction(kind: .url, value: "https://example.com"),
            secondAction: PadAction(kind: .app, value: "test.alternate", allowsAppTermination: true))
        let catalog = LinkDeckMCPHandler.buttons(macPages: [], phonePages: [SmartphonePage(id: "page", name: "Page", buttons: [button])])
        XCTAssertEqual(catalog.first { $0.id == "phone:phone:second" }?.metadata["can_quit_app"], "true")
    }

    func testSleepStatus_ignoresOtherAppsInactiveAndDisplayOnlyAssertions() {
        let idle: [String: Any] = ["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 1]
        XCTAssertTrue(MacSleepStatus.from(assertions: [idle], processName: "caffeinate"))
        XCTAssertFalse(MacSleepStatus.from(assertions: [idle], processName: "powerd"))
        XCTAssertFalse(MacSleepStatus.from(assertions: [["AssertType": "PreventUserIdleDisplaySleep", "AssertLevel": 1]], processName: "caffeinate"))
        XCTAssertFalse(MacSleepStatus.from(assertions: [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 0]], processName: "caffeinate"))
    }

    func testSleepStatusTool_readsWithoutExecutingAndRejectsArguments() throws {
        var reads = 0
        let response = LinkDeckMCPHandler.response(to: try request("tools/call", params: ["name": "linkdeck_get_sleep_status"]),
            buttons: [], sleepStatus: { reads += 1; return .unknown }) { _ in XCTFail("Must not execute"); return "" }
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).contains("unknown"))
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).contains("isError"))
        let rejected = LinkDeckMCPHandler.response(to: try request("tools/call", params: ["name": "linkdeck_get_sleep_status", "arguments": ["command": "injected"]]),
            buttons: [], sleepStatus: { XCTFail("Invalid arguments"); return .unknown }) { _ in XCTFail("Must not execute"); return "" }
        XCTAssertTrue(String(decoding: rejected.body, as: UTF8.self).contains("-32602"))
    }

    func testActualSleepStatus_detectsOwnedCaffeinateAndClearsOnExit() async throws {
        let baseline = MacSleepStatus.current()
        XCTAssertNotNil(baseline.sleepPreventionEnabled)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i"]
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(MacSleepStatus.current().mode, "insomnia")
        process.terminate()
        process.waitUntilExit()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(MacSleepStatus.current(), baseline)
    }

    func testCatalog_preservesShortLongAndFolderActionsWithoutExposingCommandContents() throws {
        let secret = "private clipboard content"
        let button = SmartphoneButton(id: "button", title: "Test", action: PadAction(kind: .clipboardText, value: secret),
            folderShortcuts: [SmartphoneFolderShortcut(id: "child", title: "Child", action: PadAction(kind: .url, value: "https://example.com"))],
            longPressAction: PadAction(kind: .terminalCommand, value: "echo secret"))
        let catalog = LinkDeckMCPHandler.buttons(macPages: [], phonePages: [SmartphonePage(id: "page", name: "Page", buttons: [button])])
        XCTAssertEqual(catalog.map(\.id), ["phone:button:short", "phone:button:long", "folder:button:child:short"])
        XCTAssertEqual(catalog[1].commandFileID, "button_long_press")
        let response = LinkDeckMCPHandler.response(to: try request("tools/call", params: ["name": "linkdeck_list_buttons"]),
            buttons: catalog) { _ in XCTFail("List must not execute actions"); return "" }
        let text = String(decoding: response.body, as: UTF8.self)
        XCTAssertTrue(text.contains("phone:button:long"))
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("echo secret"))
        XCTAssertFalse(text.contains("https://example.com"))
    }

    func testButtonCall_executesOnlyExactSavedIDAndRejectsInjectedArguments() throws {
        let action = PadAction(kind: .terminalCommand, value: "saved command", showTerminalWindow: false)
        let button = LinkDeckMCPButton(id: "saved", title: "Test", page: "Page", device: "Mac", press: "short", action: action, commandFileID: "saved")
        var calls = 0
        func invoke(_ arguments: [String: Any]) throws -> String {
            let response = LinkDeckMCPHandler.response(to: try request("tools/call", params: ["name": "linkdeck_press_button", "arguments": arguments]),
                buttons: [button]) { saved in
                    calls += 1
                    XCTAssertEqual(saved.action, action)
                    return "executed saved action"
                }
            return String(decoding: response.body, as: UTF8.self)
        }
        XCTAssertTrue(try invoke(["button_id": "missing"]).contains("isError"))
        XCTAssertTrue(try invoke(["button_id": "saved", "command": "injected"]).contains("-32602"))
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(try invoke(["button_id": "saved"]).contains("executed saved action"))
        XCTAssertEqual(calls, 1)
    }

    func testHTTP_rejectsMissingTokenBrowserOriginsAndAmbiguousFraming() {
        let body = Data("{}".utf8)
        let valid = LinkDeckHTTPRequest(method: "POST", path: "/mcp",
            headers: ["host": "127.0.0.1:1234", "authorization": "Bearer test", "content-type": "application/json"], body: body)
        XCTAssertNil(valid.authorizationStatus(token: "test"))
        XCTAssertEqual(valid.authorizationStatus(token: "different"), 401)
        var headers = valid.headers
        headers["origin"] = "https://untrusted.example"
        XCTAssertEqual(LinkDeckHTTPRequest(method: "POST", path: "/mcp", headers: headers, body: body).authorizationStatus(token: "test"), 403)
        let duplicate = Data("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 0\r\n\r\n{}".utf8)
        if case .rejected(400) = LinkDeckHTTPRequest.parse(duplicate) {} else { XCTFail("Duplicate framing must be rejected") }
        let partial = Data("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{".utf8)
        if case .incomplete = LinkDeckHTTPRequest.parse(partial) {} else { XCTFail("Partial body must wait") }
        let complete = Data("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}".utf8)
        if case .complete(let parsed) = LinkDeckHTTPRequest.parse(complete) { XCTAssertEqual(parsed.body, body) }
        else { XCTFail("Complete body must parse") }
    }

    func testTunnelLaunch_keepsKeysOutOfArgumentsAndDoesNotInheritOtherCredentials() {
        let launch = LinkDeckTunnelLaunch(tunnelID: "tunnel_test", apiKey: "private-key",
            serverURL: URL(string: "http://127.0.0.1:1234/mcp")!, localToken: "local-secret", healthFile: "/tmp/health.url")
        XCTAssertFalse(launch.arguments.joined(separator: " ").contains("private-key"))
        XCTAssertFalse(launch.arguments.joined(separator: " ").contains("local-secret"))
        XCTAssertEqual(launch.environment["LINKDECK_TUNNEL_API_KEY"], "private-key")
        XCTAssertNil(launch.environment["OPENAI_ADMIN_KEY"])
        XCTAssertTrue(launch.arguments.contains("127.0.0.1:0"))
    }

    func testLiveServer_initializeListExecuteAndStopWithAuthentication() async throws {
        let server = LinkDeckMCPServer()
        let button = LinkDeckMCPButton(id: "saved", title: "Test", page: "Page", device: "Mac", press: "short", action: PadAction(kind: .url, value: "https://example.com"), commandFileID: "saved")
        var calls = 0
        let appButton = LinkDeckMCPButton(id: "app", title: "App", page: "Page", device: "Mac", press: "short",
            action: PadAction(kind: .app, value: "test.app", allowsAppTermination: true), commandFileID: "app")
        var lastAction: PadAction?
        server.handle = { data in
            LinkDeckMCPHandler.response(to: data, buttons: [button, appButton]) { saved in
                calls += 1; lastAction = saved.action; return "ran"
            }
        }
        let url = try await server.start()
        defer { server.stop() }
        XCTAssertEqual(url.host, "127.0.0.1")
        func send(_ body: Data, authenticated: Bool = true) async throws -> (Data, Int) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if authenticated { request.setValue("Bearer " + server.token, forHTTPHeaderField: "Authorization") }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let initialize = try await send(request("initialize", params: ["protocolVersion": "2025-06-18"]))
        XCTAssertEqual(initialize.1, 200)
        XCTAssertTrue(String(decoding: initialize.0, as: UTF8.self).contains("2025-06-18"))
        let denied = try await send(request("tools/list"), authenticated: false)
        XCTAssertEqual(denied.1, 401)
        let list = try await send(request("tools/list"))
        XCTAssertTrue(String(decoding: list.0, as: UTF8.self).contains("linkdeck_press_button"))
        let ran = try await send(request("tools/call", params: ["name": "linkdeck_press_button", "arguments": ["button_id": "saved"]]))
        XCTAssertTrue(String(decoding: ran.0, as: UTF8.self).contains("ran"))
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(String(decoding: list.0, as: UTF8.self).contains("linkdeck_quit_app"))
        let quit = try await send(request("tools/call", params: ["name": "linkdeck_quit_app", "arguments": ["button_id": "app"]]))
        XCTAssertTrue(String(decoding: quit.0, as: UTF8.self).contains("ran"))
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(lastAction?.kind, .appQuit)
        XCTAssertEqual(lastAction?.value, "test.app")
        let notification = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        let accepted = try await send(notification)
        XCTAssertEqual(accepted.1, 202)
        XCTAssertTrue(accepted.0.isEmpty)
        server.stop()
        do { _ = try await send(request("tools/list")); XCTFail("Stopped server must reject connections") }
        catch { /* Expected connection failure. */ }
    }
}
