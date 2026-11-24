import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

final class LinkDeckDiagnosticLogTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("linkdeck-log-test-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRotationKeepsNewestRecordsAcrossRestart() throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root, fileLimit: 3, recordLimit: 2)
        for index in 0..<10 { log.record("test", code: index) }
        log.waitForPendingWrites()
        let restarted = LinkDeckDiagnosticLog(directory: root, fileLimit: 3, recordLimit: 2)
        restarted.record("test", code: 10)
        restarted.waitForPendingWrites()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(files.count, 3)
        var codes: [Int] = []
        for file in files {
            let lines = try Data(contentsOf: file).split(separator: 10)
            XCTAssertLessThanOrEqual(lines.count, 2)
            for line in lines {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
                codes.append(try XCTUnwrap(object["code"] as? Int))
            }
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
        }
        XCTAssertEqual(codes.sorted(), [6, 7, 8, 9, 10])
    }

    func testByteLimitAndConcurrentWrites() throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root, fileLimit: 2, recordLimit: 100, byteLimit: 512)
        DispatchQueue.concurrentPerform(iterations: 100) { index in log.record("test", code: index) }
        log.waitForPendingWrites()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(files.count, 2)
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertLessThanOrEqual(data.count, 512)
            for line in data.split(separator: 10) { XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line))) }
        }
    }

    func testTunnelOutputIsBoundedAndNeverPersistsRawSecrets() throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root)
        log.consumeTunnelOutput(Data("{\"error\":\"401 token_invalidated SECRET-KEY\"}".utf8))
        log.consumeTunnelOutput(Data("\n".utf8))
        log.consumeTunnelOutput(Data(repeating: 65, count: 100_000))
        log.consumeTunnelOutput(Data("\n{\"msg\":\"deadline exceeded PRIVATE-CONTENT\"}\n".utf8))
        log.waitForPendingWrites()
        let text = try String(contentsOf: root.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertTrue(text.contains("authentication"))
        XCTAssertTrue(text.contains("oversized_line"))
        XCTAssertTrue(text.contains("timeout"))
        XCTAssertFalse(text.contains("SECRET-KEY"))
        XCTAssertFalse(text.contains("PRIVATE-CONTENT"))
        XCTAssertEqual(text.split(separator: "\n").count, 3)
    }

    @MainActor
    func testServerRecordsDeadlineAndLateResponseWithoutPayload() async throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root)
        let server = LinkDeckMCPServer(log: log, connectionTimeout: .milliseconds(100))
        server.handle = { _ in
            XCTAssertNotNil(LinkDeckRequestContext.id)
            try? await Task.sleep(for: .milliseconds(250))
            return (200, Data("{\"result\":{}}".utf8))
        }
        let url = try await server.start()
        defer { server.stop(); log.waitForPendingWrites() }
        let request = toolRequest(url: url, token: server.token, tool: "test_tool")
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("The server must close the connection at its deadline")
        } catch { }
        try await Task.sleep(for: .milliseconds(350))
        log.waitForPendingWrites()
        let text = try String(contentsOf: root.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertTrue(text.contains("request.timeout"))
        XCTAssertTrue(text.contains("late_response"))
        XCTAssertFalse(text.contains("PRIVATE-PAYLOAD"))
        XCTAssertFalse(text.contains(server.token))
        let rows = try text.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        let requestRows = rows.filter { ["request.started", "request.timeout", "request.completed"].contains($0["event"] as? String ?? "") }
        XCTAssertEqual(Set(requestRows.compactMap { $0["request_id"] as? String }).count, 1)
    }

    func testFinalTunnelLineIsFlushedAndNextRunStartsClean() throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root)
        log.consumeTunnelOutput(Data("401 SECRET".utf8))
        log.finishTunnelOutput()
        log.consumeTunnelOutput(Data("deadline exceeded".utf8))
        log.finishTunnelOutput()
        log.waitForPendingWrites()
        let text = try String(contentsOf: root.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 2)
        XCTAssertTrue(text.contains("authentication"))
        XCTAssertTrue(text.contains("timeout"))
        XCTAssertFalse(text.contains("SECRET"))
    }

    func testIndependentWritersShareOneRetentionLimit() throws {
        let root = try directory()
        let first = LinkDeckDiagnosticLog(directory: root, fileLimit: 2, recordLimit: 2)
        let second = LinkDeckDiagnosticLog(directory: root, fileLimit: 2, recordLimit: 2)
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            (index.isMultiple(of: 2) ? first : second).record("test", code: index)
        }
        first.waitForPendingWrites()
        second.waitForPendingWrites()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
        XCTAssertEqual(files.count, 2)
        for file in files {
            let lines = try Data(contentsOf: file).split(separator: 10)
            XCTAssertEqual(lines.count, 2)
            for line in lines { XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line))) }
        }
    }

    func testSummaryCountsTimeoutAndLateCompletionOnce() async throws {
        let log = LinkDeckDiagnosticLog(directory: try directory())
        log.record("request.started", requestID: "a", method: "tools/call", tool: "demo")
        log.record("request.timeout", requestID: "a")
        log.record("request.completed", requestID: "a", method: "tools/call", tool: "demo",
                   outcome: "late_response", elapsedMS: 1_000)
        log.record("request.completed", requestID: "b", method: "tools/call", tool: "demo",
                   outcome: "success", elapsedMS: 100)
        log.record("tunnel.reconnecting")
        let summary = try await log.summary()
        XCTAssertEqual(summary.reconnects, 1)
        XCTAssertEqual(summary.calls.count, 2)
        XCTAssertEqual(summary.tools.first?.failures, 1)
        XCTAssertEqual(summary.tools.first?.p50, 100)
        XCTAssertEqual(summary.tools.first?.p95, 1_000)
        XCTAssertEqual(summary.calls.first(where: { $0.id == "a" })?.outcome, "timeout · late_response")
    }

    func testSummaryReadsLegacyLogsAndExcludesOlderRecords() async throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root)
        log.record("server.ready")
        log.waitForPendingWrites()
        let contents = """
        {"time":"2026-11-01T00:00:00Z","event":"tunnel.reconnecting"}
        {"time":"2026-11-20T00:00:00Z","event":"request.completed","request_id":"legacy","method":"tools/call","tool":"demo","elapsed_ms":100,"outcome":"success"}
        """
        try contents.write(to: root.appendingPathComponent("events.jsonl"), atomically: false, encoding: .utf8)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-21T00:00:00Z"))
        let summary = try await log.summary(now: now)
        XCTAssertEqual(summary.reconnects, 0)
        XCTAssertEqual(summary.calls.map(\.id), ["legacy"])
    }

    @MainActor
    func testConcurrentToolLatencyAndLoggingFailure() async throws {
        let directory = try directory()
        let log = LinkDeckDiagnosticLog(directory: directory)
        let delays: [String: Duration] = ["short": .milliseconds(100), "long": .seconds(1)]
        let server = LinkDeckMCPServer(log: log)
        server.handle = { body in
            let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            let tool = (payload?["params"] as? [String: Any])?["name"] as? String
            if let tool, let delay = delays[tool] { try? await Task.sleep(for: delay) }
            return (200, Data("{\"result\":{}}".utf8))
        }
        let url = try await server.start()
        defer { server.stop(); log.waitForPendingWrites() }
        let shortRequest = toolRequest(url: url, token: server.token, tool: "short")
        let longRequest = toolRequest(url: url, token: server.token, tool: "long")
        async let short = URLSession.shared.data(for: shortRequest)
        async let long = URLSession.shared.data(for: longRequest)
        _ = try await (short, long)
        let summary = try await log.summary()
        XCTAssertEqual(summary.calls.count, 2)
        for (tool, expected) in [("short", 100), ("long", 1_000)] {
            let actual = try XCTUnwrap(summary.tools.first { $0.id == tool }?.p95)
            XCTAssertGreaterThanOrEqual(actual, expected - 5)
            XCTAssertLessThanOrEqual(actual, expected + 250)
        }

        let blockedLocation = directory.appendingPathComponent("blocked")
        try Data().write(to: blockedLocation)
        let failingLog = LinkDeckDiagnosticLog(directory: blockedLocation)
        let failingServer = LinkDeckMCPServer(log: failingLog)
        failingServer.handle = { _ in (200, Data("{\"result\":{}}".utf8)) }
        let failingURL = try await failingServer.start()
        defer { failingServer.stop(); failingLog.waitForPendingWrites() }
        let (_, response) = try await URLSession.shared.data(
            for: toolRequest(url: failingURL, token: failingServer.token, tool: "demo"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    @MainActor
    func testDiagnosticLatencyWithRecordingOnAndOff() async throws {
        for enabled in [false, true] {
            let log = LinkDeckDiagnosticLog(directory: try directory(), isEnabled: { enabled })
            let server = LinkDeckMCPServer(log: log)
            server.handle = { _ in (200, Data("{\"result\":{}}".utf8)) }
            let url = try await server.start()
            defer { server.stop(); log.waitForPendingWrites() }
            let request = toolRequest(url: url, token: server.token, tool: "benchmark")
            var durations: [Double] = []
            for index in 0..<1_010 {
                let start = ContinuousClock.now
                let (_, response) = try await URLSession.shared.data(for: request)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                if index >= 10 {
                    let elapsed = start.duration(to: .now).components
                    durations.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                }
            }
            let summary = try await log.summary()
            XCTAssertEqual(summary.calls.isEmpty, !enabled)
            print("MCP loopback p95 (recording \(enabled ? "on" : "off"), 1,000 calls): \(durations.sorted()[949]) ms")
        }
    }

    private func toolRequest(url: URL, token: String, tool: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"\(tool)\",\"arguments\":{\"text\":\"PRIVATE-PAYLOAD\"}}}".utf8)
        return request
    }

    func testChatViewStagesJoinAcrossRequestsWithoutPersistingContent() async throws {
        let root = try directory()
        let log = LinkDeckDiagnosticLog(directory: root)
        let taskID = UUID().uuidString
        LinkDeckRequestContext.$id.withValue("start") {
            log.recordChatViewTask(["taskId": taskID, "createdAt": 100.0, "answer": "PRIVATE-ANSWER"],
                                   tool: "chat_view_start_task")
            log.record("app.request.completed", method: "tools/call", tool: "chat_view_start_task",
                       app: "ChatView", outcome: "success", elapsedMS: 25)
            log.record("request.completed", method: "tools/call", tool: "linkdeck_app_chat_view_plus__chat_view_start_task",
                       outcome: "success", elapsedMS: 30)
        }
        LinkDeckRequestContext.$id.withValue("poll") {
            log.recordChatViewTask(["taskId": taskID, "createdAt": 100.0, "startedAt": 100.5, "completedAt": 102.0],
                                   tool: "chat_view_task_status")
            log.record("request.completed", method: "tools/call", tool: "linkdeck_app_chat_view_plus__chat_view_task_status",
                       outcome: "success", elapsedMS: 20)
        }
        let summary = try await log.summary()
        let start = try XCTUnwrap(summary.calls.first { $0.id == "start" })
        XCTAssertEqual(start.appSteps.map(\.elapsedMS), [25])
        XCTAssertEqual(start.queueMS, 500)
        XCTAssertEqual(start.executionMS, 1_500)
        XCTAssertNil(summary.calls.first { $0.id == "poll" }?.executionMS)
        let text = try String(contentsOf: root.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertFalse(text.contains("PRIVATE-ANSWER"))
    }

    func testSpikeAndComparisonUsePerToolSamples() throws {
        let now = Date()
        func event(_ index: Int, offset: TimeInterval, duration: Int) -> LinkDeckDiagnosticSummary.Event {
            .init(time: now.addingTimeInterval(offset), event: "request.completed", request_id: String(index),
                  method: "tools/call", tool: "demo", outcome: "success", elapsed_ms: duration, app: nil, task_id: nil)
        }
        let baseline = (1...5).map { event($0, offset: -Double($0 * 100), duration: 100) }
        let latest = event(0, offset: -1, duration: 250)
        let summary = LinkDeckDiagnosticSummary(events: baseline + [latest], now: now)
        XCTAssertEqual(summary.tools.first?.latestSpike, true)
        let row = try XCTUnwrap(summary.compare(at: now.addingTimeInterval(-50)).first)
        XCTAssertEqual(row.beforeCount, 5)
        XCTAssertEqual(row.afterCount, 1)
        XCTAssertEqual(row.beforeP95, 100)
        XCTAssertEqual(row.afterP95, 250)
    }

    func testResponseOutcomes() {
        XCTAssertEqual(LinkDeckDiagnosticLog.responseOutcome(Data(), httpStatus: 202), "accepted")
        XCTAssertEqual(LinkDeckDiagnosticLog.responseOutcome(Data("{\"result\":{\"isError\":true}}".utf8)), "tool_error")
        XCTAssertEqual(LinkDeckDiagnosticLog.responseOutcome(Data("{\"error\":{\"code\":-1}}".utf8)), "tool_error")
        XCTAssertEqual(LinkDeckDiagnosticLog.responseOutcome(Data("{\"result\":{}}".utf8)), "success")
        XCTAssertEqual(LinkDeckDiagnosticLog.responseOutcome(Data()), "invalid_response")
    }
}
