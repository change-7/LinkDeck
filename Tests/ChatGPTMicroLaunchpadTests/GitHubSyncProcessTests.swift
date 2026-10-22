import XCTest
@testable import ChatGPTMicroLaunchpad

final class GitHubSyncProcessTests: XCTestCase {
    func testStalledProcessStillTimesOut() async throws {
        let service = GitHubSyncService(commandTimeout: 0.1)
        do {
            _ = try await service.run(
                executableURL: URL(filePath: "/bin/sleep"),
                command: GitHubCommand(arguments: ["10"], workingDirectory: FileManager.default.temporaryDirectory)
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? GitHubSyncError, .commandTimedOut)
        }
    }

    func testLargeOutputDoesNotBlockProcessExit() async throws {
        let service = GitHubSyncService(commandTimeout: 3)
        let result = try await service.run(
            executableURL: URL(filePath: "/bin/sh"),
            command: GitHubCommand(
                arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do printf 'changed-file-output\\n'; i=$((i+1)); done"],
                workingDirectory: FileManager.default.temporaryDirectory
            )
        )
        XCTAssertEqual(result.split(separator: "\n").count, 20000)
    }

    func testFailurePreservesStandardError() async throws {
        let service = GitHubSyncService(commandTimeout: 3)
        do {
            _ = try await service.run(
                executableURL: URL(filePath: "/bin/sh"),
                command: GitHubCommand(arguments: ["-c", "printf 'push rejected' >&2; exit 1"], workingDirectory: FileManager.default.temporaryDirectory)
            )
            XCTFail("Expected command failure")
        } catch {
            XCTAssertEqual(error as? GitHubSyncError, .commandFailed("push rejected"))
        }
    }
}
