import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class FolderGitIntegrationTests: XCTestCase {
    func testActualHTTPMCPPullsRegisteredTemporaryRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LinkDeck-MCP-Git-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let git = GitSyncProcess()
        func command(_ arguments: [String], at folder: URL) async throws {
            let result = try await git.run(arguments, at: folder)
            XCTAssertEqual(result.status, 0, result.output)
            guard result.status == 0 else { throw GitSyncFailure(code: .commandFailed) }
        }
        let remote = directory.appendingPathComponent("remote.git")
        let writer = directory.appendingPathComponent("writer")
        let local = directory.appendingPathComponent("local")
        try await command(["init", "--bare", "--initial-branch=trunk", remote.path], at: directory)
        try await command(["clone", remote.path, writer.path], at: directory)
        try Data("first".utf8).write(to: writer.appendingPathComponent("note.md"))
        try await command(["add", "note.md"], at: writer)
        try await command(["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "first"], at: writer)
        try await command(["push", "-u", "origin", "trunk"], at: writer)
        try await command(["clone", remote.path, local.path], at: directory)
        try Data("remote update".utf8).write(to: writer.appendingPathComponent("note.md"))
        try await command(["add", "note.md"], at: writer)
        try await command(["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "second"], at: writer)
        try await command(["push"], at: writer)

        let suite = "LinkDeck.GitHTTPTest.\(UUID())"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let gitStore = GitSyncStore(storage: storage)
        let config = GitSyncConfiguration(name: "MCP temp", folder: try FolderReference(url: local), direction: .pull)
        gitStore.add(config)
        let folderStore = FolderPairStore(gitSyncStore: gitStore, initialPairs: [])
        let server = LinkDeckMCPServer()
        server.handle = { data in
            LinkDeckMCPHandler.response(to: data, buttons: [], folderSyncStore: folderStore) { _ in
                XCTFail("Must not execute buttons"); return ""
            }
        }
        let endpoint = try await server.start()
        defer { server.stop() }
        func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + server.token, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try XCTUnwrap(object["result"] as? [String: Any])
        }
        func tool(_ suffix: String, _ arguments: [String: Any]) async throws -> [String: Any] {
            let result = try await request("tools/call", params: ["name": "linkdeck_git_sync_" + suffix, "arguments": arguments])
            XCTAssertEqual(result["isError"] as? Bool, false)
            let content = try XCTUnwrap(result["content"] as? [[String: Any]])
            let string = try XCTUnwrap(content.first?["text"] as? String)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
        }
        let catalog = try await request("tools/list")
        XCTAssertTrue((catalog["tools"] as? [[String: Any]])?.contains { $0["name"] as? String == "linkdeck_git_sync_start" } == true)
        let listed = try await tool("list", [:])
        XCTAssertEqual((listed["syncs"] as? [[String: Any]])?.first?["sync_id"] as? String, config.id.uuidString)
        let started = try await tool("start", ["sync_id": config.id.uuidString])
        let jobID = try XCTUnwrap((started["job_id"] as? String).flatMap(UUID.init(uuidString:)))
        let completed = await gitStore.wait(jobID: jobID)
        XCTAssertEqual(completed?.success, true, completed?.errorMessage ?? "missing result")
        let status = try await tool("status", ["job_id": jobID.uuidString])
        XCTAssertEqual(status["success"] as? Bool, true)
        XCTAssertEqual(status["phase"] as? String, "completed")
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("note.md"), encoding: .utf8), "remote update")
    }

    func testRsyncProtectsGitFilesAndDirectoriesDuringDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let target = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: target.appendingPathComponent(".git/config"))
        try Data("remove".utf8).write(to: target.appendingPathComponent("old.txt"))
        try Data("gitdir: /private/test".utf8).write(to: source.appendingPathComponent(".git"))
        var options = SyncOptions(deleteExtraFiles: true)
        options.excludeGitMetadata = true
        try await RsyncRunner().copy(from: source, to: target, options: options)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent(".git/config"), encoding: .utf8), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("old.txt").path))
        try FileManager.default.removeItem(at: target.appendingPathComponent(".git"))
        try Data("gitdir: preserve".utf8).write(to: target.appendingPathComponent(".git"))
        try await RsyncRunner().copy(from: source, to: target, options: options)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent(".git"), encoding: .utf8), "gitdir: preserve")
    }

    func testLegacyOptionsKeepDeletionAndNewGitExclusionDefaults() throws {
        let options = try JSONDecoder().decode(SyncOptions.self, from: Data("{\"deleteExtraFiles\":true}".utf8))
        XCTAssertTrue(options.deleteExtraFiles)
        XCTAssertFalse(options.excludeGitMetadata)
        var protected = options
        protected.excludeGitMetadata = true
        let command = RsyncCommandBuilder.copyCommand(from: URL(fileURLWithPath: "/tmp/source"),
                                                       to: URL(fileURLWithPath: "/tmp/target"), options: protected)
        XCTAssertTrue(command.arguments.contains("--exclude=.git"))
        XCTAssertTrue(command.arguments.contains("--delete"))
        let roundtrip = try JSONDecoder().decode(SyncOptions.self, from: JSONEncoder().encode(protected))
        XCTAssertTrue(roundtrip.excludeGitMetadata)
    }

    func testFolderPairLinkRoundtripAndLegacyDecode() throws {
        var pair = FolderPair(name: "legacy", folderA: nil, syncOnLaunch: false)
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(pair)) as? [String: Any])
        object.removeValue(forKey: "gitSyncLink")
        let legacy = try JSONDecoder().decode(FolderPair.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.gitSyncLink)
        pair.gitSyncLink = GitSyncLink(syncID: UUID(), position: .before, direction: .pull)
        let decoded = try JSONDecoder().decode(FolderPair.self, from: encoder.encode(pair))
        XCTAssertEqual(decoded.gitSyncLink, pair.gitSyncLink)
        XCTAssertEqual(decoded.id, pair.id)
    }

    func testFolderSyncHonorsGitLinkOrderAndReportsDependentFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderGitLink-\(UUID())")
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("source".utf8).write(to: source.appendingPathComponent("source.md"))

        var before = FolderPair(name: "before", folderA: try FolderReference(url: source),
                                folderB: try FolderReference(url: target), syncOnLaunch: false)
        before.gitSyncLink = GitSyncLink(syncID: UUID(), position: .before)
        let beforeStore = FolderPairStore(gitSyncStore: GitSyncStore(storage: try isolatedDefaults()), initialPairs: [before])
        await beforeStore.sync(before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("source.md").path))
        guard case .failed = beforeStore.state(for: before) else { return XCTFail("A failed pre-sync must stop folder copying") }

        var after = FolderPair(name: "after", folderA: try FolderReference(url: source),
                               folderB: try FolderReference(url: target), syncOnLaunch: false)
        after.gitSyncLink = GitSyncLink(syncID: UUID(), position: .after)
        let afterStore = FolderPairStore(gitSyncStore: GitSyncStore(storage: try isolatedDefaults()), initialPairs: [after])
        await afterStore.sync(after)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("source.md"), encoding: .utf8), "source")
        guard case .failed = afterStore.state(for: after) else { return XCTFail("A failed post-sync must fail the combined operation") }
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "FolderGitLink.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testGitMCPRegisteredAlongsideLegacyTools() throws {
        let request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let response = LinkDeckMCPHandler.response(to: request, buttons: []) { _ in XCTFail(); return "" }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        for suffix in ["list", "start", "status", "cancel"] {
            XCTAssertTrue(names.contains("linkdeck_git_sync_" + suffix))
        }
        for suffix in ["list", "start", "status"] {
            XCTAssertTrue(names.contains("linkdeck_folder_sync_" + suffix))
        }
    }

    func testGitMCPRejectsArbitraryPathsAndInvalidSelectors() {
        let suite = "LinkDeck.GitMCPTest.\(UUID())"
        let storage = UserDefaults(suiteName: suite)!
        defer { storage.removePersistentDomain(forName: suite) }
        let store = GitSyncStore(storage: storage)
        let invalid: [(String, [String: Any])] = [
            ("start", ["sync_id": UUID().uuidString, "path": "/tmp"]),
            ("start", ["sync_id": UUID().uuidString, "direction": "force"]),
            ("status", ["job_id": UUID().uuidString, "sync_id": UUID().uuidString]),
            ("cancel", ["job_id": "invalid"])
        ]
        for (suffix, arguments) in invalid {
            let response = GitSyncMCP.response(name: "linkdeck_git_sync_" + suffix, arguments: arguments, store: store)
            XCTAssertEqual(response["isError"] as? Bool, true)
        }
        XCTAssertTrue(store.jobs.isEmpty)
    }
}
