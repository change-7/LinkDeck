import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexDesktopApprovalMonitorTests: XCTestCase {
    func testMonitorReusesHealthySocketAndReconnectsAfterClosure() async throws {
        let root = URL(fileURLWithPath: "/tmp/ld-ipc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("ipc.sock")
        let ready = root.appendingPathComponent("ready")
        let finished = root.appendingPathComponent("finished")
        let server = Process()
        let errors = Pipe()
        server.standardError = errors
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", """
            import json, pathlib, socket, struct, sys, time

            def receive(stream):
                size, = struct.unpack("<I", stream.read(4))
                return json.loads(stream.read(size))

            def send(conn, message):
                data = json.dumps(message).encode()
                conn.sendall(struct.pack("<I", len(data)) + data)

            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(sys.argv[1])
                listener.listen()
                listener.settimeout(3)
                pathlib.Path(sys.argv[2]).touch()
                for poll_count in (2, 1):
                    conn, _ = listener.accept()
                    with conn, conn.makefile("rb") as stream:
                        conn.settimeout(3)
                        init = receive(stream)
                        assert init["method"] == "initialize"
                        send(conn, {"requestId": init["requestId"], "resultType": "success"})
                        for _ in range(poll_count):
                            assert receive(stream)["method"] == "thread-stream-following-status-requested"
                            send(conn, {"type": "broadcast", "method": "thread-stream-following-changed",
                                "params": {"hostId": "local", "conversationId": "example", "following": False}})
                        if poll_count == 2:
                            assert receive(stream)["method"] == "thread-stream-following-status-requested"
                        else:
                            for _ in range(300):
                                if pathlib.Path(sys.argv[3]).exists():
                                    break
                                time.sleep(0.01)
                            else:
                                raise TimeoutError("Swift client did not finish")
            """, socket.path, ready.path, finished.path]
        try server.run()
        defer { if server.isRunning { server.terminate() } }
        let deadline = ContinuousClock.now + .seconds(5)
        while server.isRunning, !FileManager.default.fileExists(atPath: ready.path),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard FileManager.default.fileExists(atPath: ready.path) else {
            if server.isRunning { server.terminate() }
            server.waitUntilExit()
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail("IPC fixture did not start: \(message)")
            return
        }

        let monitor = CodexDesktopApprovalIPC.Monitor(
            socketPath: socket.path, globalStateURL: root.appendingPathComponent("state.json")
        )
        let first = try await monitor.pendingApprovals()
        let second = try await monitor.pendingApprovals()
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        do {
            _ = try await monitor.pendingApprovals()
            XCTFail("Expected the closed connection to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Codex IPC 연결이 종료되었습니다.")
        }
        let afterReconnect = try await monitor.pendingApprovals()
        XCTAssertTrue(afterReconnect.isEmpty)
        try Data().write(to: finished)
        server.waitUntilExit()
        XCTAssertEqual(server.terminationStatus, 0)
    }
}
