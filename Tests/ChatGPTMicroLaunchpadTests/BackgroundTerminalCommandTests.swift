import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

final class BackgroundTerminalCommandTests: XCTestCase {
    func testLegacyTerminalAction_defaultsToVisibleWindowAndRoundTripsHiddenSelection() throws {
        let legacy = Data(#"{"kind":"terminalCommand","value":"echo test"}"#.utf8)
        var action = try JSONDecoder().decode(PadAction.self, from: legacy)
        XCTAssertTrue(action.showTerminalWindow)
        action.showTerminalWindow = false
        XCTAssertEqual(try JSONDecoder().decode(PadAction.self, from: JSONEncoder().encode(action)), action)
    }

    @MainActor
    func testBackgroundCommand_runsShellSyntaxWithoutTerminal() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("background-command-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let process = try MacActionRunner.runBackgroundTerminalCommand("value='hello world'; printf '%s' \"$value\" > '\(file.path)'")
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello world")
    }

    @MainActor
    func testHiddenAction_startsLongCommandWithoutBlockingCaller() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("background-long-command-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let action = PadAction(kind: .terminalCommand,
            value: "sleep 1; printf done > '\(file.path)'", showTerminalWindow: false)
        let started = Date()
        XCTAssertEqual(try MacActionRunner().execute(action), "터미널 명령을 백그라운드에서 실행했습니다.")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.75)
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: file.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "done")
    }
}
