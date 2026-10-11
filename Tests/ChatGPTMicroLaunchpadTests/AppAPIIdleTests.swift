import Foundation
import Darwin
import XCTest
@testable import ChatGPTMicroLaunchpad

final class AppAPIIdleTests: XCTestCase {
    private actor QuitRecorder {
        var calls = 0
        func quit() -> Bool { calls += 1; return true }
    }

    func testAppManagedChatViewKeepsGUIAndBridgeAliveIncludingManualLaunch() async throws {
        for mode in ["app_managed_chat_view", "app_managed_manual_chat_view"] {
            let recorder = QuitRecorder()
            let client = StableWhisperMCPClient(idleTimeout: .milliseconds(200), chatView: true,
                terminateChatView: { await recorder.quit() }, launchChatView: { _ in })
            let firstPID = try await call(client, "pid")
            _ = try await call(client, mode)
            try await Task.sleep(for: .milliseconds(450))
            let quitCalls = await recorder.calls
            XCTAssertEqual(quitCalls, 0, mode)
            XCTAssertEqual(kill(try XCTUnwrap(Int32(firstPID)), 0), 0, mode)
            _ = try await call(client, "chat_view_start_task")
            _ = try await call(client, "chat_view_task_status")
            try await Task.sleep(for: .milliseconds(450))
            let laterQuitCalls = await recorder.calls
            XCTAssertEqual(laterQuitCalls, 0, mode)
            let reusedPID = try await call(client, "pid")
            XCTAssertEqual(reusedPID, firstPID, mode)
            _ = try await call(client, "simulate_cold_chat_view")
            _ = try await call(client, "chatgpt_state")
            let reconnectedPID = try await call(client, "pid")
            XCTAssertEqual(reconnectedPID, firstPID, mode)
            await client.stop()
            let pid = try XCTUnwrap(Int32(firstPID))
            let deadline = Date().addingTimeInterval(1)
            while kill(pid, 0) == 0, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(kill(pid, 0), -1, mode)
        }
    }

    func testChatViewRelaunchesWithExistingBridgeAndWaitsBeforeStartingTask() async throws {
        let recorder = QuitRecorder()
        let client = StableWhisperMCPClient(chatView: true, launchChatView: { _ in _ = await recorder.quit() })
        let firstPID = try await call(client, "pid")
        _ = try await call(client, "simulate_cold_chat_view")
        let task = try await call(client, "chat_view_start_task")
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(task.utf8)) as? [String: Any])
        XCTAssertEqual(result["unavailableStates"] as? Int, 0)
        XCTAssertEqual(result["taskStarts"] as? Int, 1)
        let reusedPID = try await call(client, "pid")
        XCTAssertEqual(reusedPID, firstPID)
        let launches = await recorder.calls
        XCTAssertEqual(launches, 4)
        await client.stop()
    }

    func testChatViewWaitsForResultRetrievalThenQuitsAndRestarts() async throws {
        let recorder = QuitRecorder()
        let client = StableWhisperMCPClient(idleTimeout: .milliseconds(200), chatView: true, terminateChatView: { await recorder.quit() }, launchChatView: { _ in })
        let pidText = try await call(client, "pid")
        let pid = try XCTUnwrap(Int32(pidText))
        _ = try await call(client, "chat_view_start_task")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(kill(pid, 0), 0)
        let before = await recorder.calls
        XCTAssertEqual(before, 0)
        _ = try await call(client, "chat_view_task_status")
        try await Task.sleep(for: .milliseconds(450))
        let after = await recorder.calls
        XCTAssertEqual(after, 1)
        XCTAssertEqual(kill(pid, 0), -1)
        let restarted = try await call(client, "pid")
        XCTAssertNotEqual(pidText, restarted)
        await client.stop()
    }

    func testManualChatViewIsKeptAlive() async throws {
        let recorder = QuitRecorder()
        let client = StableWhisperMCPClient(idleTimeout: .milliseconds(200), chatView: true, terminateChatView: { await recorder.quit() }, launchChatView: { _ in })
        let pidText = try await call(client, "pid")
        _ = try await call(client, "manual_chat_view")
        try await Task.sleep(for: .milliseconds(450))
        let calls = await recorder.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(kill(try XCTUnwrap(Int32(pidText)), 0), 0)
        await client.stop()
    }
    func testChatViewRequiresHiddenAutomationAndEveryPanelIdle() {
        let panel: [String: Any] = ["taskBusy": false, "promptBusy": false, "isLoading": false, "queuedTaskCount": 0, "state": "completed"]
        var state: [String: Any] = ["presentation": ["mode": "codex", "windowHidden": true, "humanInterventionRequired": false], "activeTaskCount": 0, "busyPanelIndices": [Int](), "panels": [panel, panel]]
        XCTAssertTrue(StableWhisperMCPClient.chatViewCanQuit(state))
        for presentation: [String: Any] in [
            ["mode": "manual", "windowHidden": true, "humanInterventionRequired": false],
            ["mode": "codex", "windowHidden": false, "humanInterventionRequired": false],
            ["mode": "codex", "windowHidden": true, "humanInterventionRequired": true]
        ] {
            var changed = state
            changed["presentation"] = presentation
            XCTAssertFalse(StableWhisperMCPClient.chatViewCanQuit(changed))
        }
        for key in ["taskBusy", "promptBusy", "isLoading", "queuedTaskCount", "state"] {
            var busy = panel
            busy[key] = key == "state" ? "answering" : key == "queuedTaskCount" ? 1 : true
            state["panels"] = [panel, busy]
            XCTAssertFalse(StableWhisperMCPClient.chatViewCanQuit(state))
        }
        XCTAssertFalse(StableWhisperMCPClient.chatViewCanQuit([:]))
    }
    private func call(_ client: StableWhisperMCPClient, _ name: String) async throws -> String {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/app_api_mcp.py")
        let request = try JSONSerialization.data(withJSONObject: ["method": "tools/call", "params": ["name": name, "arguments": [:]]])
        let reply = try await client.request(request, executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture.path])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return try XCTUnwrap(content.first?["text"] as? String)
    }

    func testIdleServerExitsAndNextCallStartsNewServer() async throws {
        let client = StableWhisperMCPClient(idleTimeout: .milliseconds(200))
        let first = try await call(client, "pid")
        try await Task.sleep(for: .milliseconds(100))
        let reused = try await call(client, "pid")
        XCTAssertEqual(first, reused)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(kill(try XCTUnwrap(Int32(first)), 0), -1)
        let restarted = try await call(client, "pid")
        XCTAssertNotEqual(first, restarted)
        await client.stop()
    }

    func testRunningDownloadSurvivesIdleAndCompletedDownloadExits() async throws {
        let client = StableWhisperMCPClient(idleTimeout: .milliseconds(200))
        let pidText = try await call(client, "pid")
        let pid = try XCTUnwrap(Int32(pidText))
        _ = try await call(client, "start_download")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(kill(pid, 0), 0)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(kill(pid, 0), -1)
        await client.stop()
    }
}
