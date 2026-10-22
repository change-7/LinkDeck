import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class GitSyncEngineTests: XCTestCase {
    struct Fixture {
        let root: URL
        let local: URL
        let peer: URL
        let bare: URL
    }
    private func git(_ arguments: [String], at url: URL) async throws -> String {
        let result = try await GitSyncProcess().run(arguments, at: url)
        guard result.status == 0 else { throw NSError(domain: "TestGit", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: result.output]) }
        return result.output.trimmingCharacters(in: .newlines)
    }
    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitSyncTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bare = root.appendingPathComponent("remote.git"), local = root.appendingPathComponent("local"), peer = root.appendingPathComponent("peer")
        _ = try await git(["init", "--bare", bare.path], at: root)
        _ = try await git(["init", "-b", "notes", local.path], at: root)
        for key in ["user.name", "user.email"] { _ = try await git(["config", key, "git-sync-test"], at: local) }
        try "initial".write(to: local.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        _ = try await git(["add", "."], at: local)
        _ = try await git(["commit", "-m", "initial"], at: local)
        _ = try await git(["remote", "add", "vault", bare.path], at: local)
        _ = try await git(["push", "-u", "vault", "notes"], at: local)
        _ = try await git(["clone", "-b", "notes", bare.path, peer.path], at: root)
        for key in ["user.name", "user.email"] { _ = try await git(["config", key, "git-sync-test"], at: peer) }
        return Fixture(root: root, local: local, peer: peer, bare: bare)
    }
    private func commit(_ text: String, at url: URL, name: String = "note.txt") async throws {
        try text.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
        _ = try await git(["add", "--", name], at: url)
        _ = try await git(["commit", "-m", "test change"], at: url)
    }
    private func run(_ fixture: Fixture, direction: GitSyncDirection, auto: Bool = false, includes: [String] = []) async throws -> GitSyncJob {
        let config = GitSyncConfiguration(name: "test", folder: try FolderReference(url: fixture.local), direction: direction, autoCommit: auto, includePatterns: includes)
        return await GitSyncService().run(configuration: config, job: GitSyncJob(syncID: config.id, direction: direction)) { _ in }
    }
    func testDetectionWorktreePullPushAndNoOp() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let detected = try await GitSyncService().detect(folder: FolderReference(url: f.local))
        XCTAssertEqual(detected.remote, "vault"); XCTAssertEqual(detected.branch, "notes")
        let worktree = f.root.appendingPathComponent("worktree")
        _ = try await git(["worktree", "add", "-b", "linked", worktree.path], at: f.local)
        let linked = try await GitSyncService().inspect(url: worktree)
        XCTAssertEqual(linked.commonDirectory, detected.commonDirectory)
        XCTAssertNotEqual(linked.gitDirectory, detected.gitDirectory)
        try await commit("remote", at: f.peer)
        _ = try await git(["push"], at: f.peer)
        let pulled = try await run(f, direction: .pull)
        XCTAssertTrue(pulled.succeeded, pulled.errorMessage ?? "")
        XCTAssertEqual(try String(contentsOf: f.local.appendingPathComponent("note.txt"), encoding: .utf8), "remote")
        try await commit("local", at: f.local)
        let pushed = try await run(f, direction: .push)
        XCTAssertTrue(pushed.succeeded, pushed.errorMessage ?? "")
        XCTAssertEqual(pushed.localHEAD, pushed.remoteHEAD)
        let noOp = try await run(f, direction: .bidirectional)
        XCTAssertTrue(noOp.succeeded); XCTAssertEqual(noOp.commitCount, 0)
        XCTAssertFalse(noOp.steps.contains { $0.phase == .pushing || $0.phase == .committing })
    }

    func testExistingFolderPairUsesGitEngineAndItsDirection() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let suite = "IntegratedGitTest.\(UUID())"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let gitStore = GitSyncStore(storage: storage)
        var pair = FolderPair(name: "existing", folderA: try FolderReference(url: f.local),
            folderB: nil, syncMode: .bToA, githubSync: GitHubSyncConfiguration(repositoryURL: f.bare.path))
        let store = FolderPairStore(gitSyncStore: gitStore, initialPairs: [pair])
        XCTAssertEqual(gitStore.configurations.first?.id, pair.id)
        XCTAssertEqual(gitStore.configurations.first?.direction, .pull)
        XCTAssertFalse(try XCTUnwrap(gitStore.configurations.first).autoCommit)
        try await commit("remote integrated", at: f.peer)
        _ = try await git(["push"], at: f.peer)
        await store.syncToGitHub(pair)
        XCTAssertTrue(try XCTUnwrap(gitStore.latestJob(syncID: pair.id)).succeeded)
        XCTAssertEqual(try String(contentsOf: f.local.appendingPathComponent("note.txt"), encoding: .utf8), "remote integrated")
        pair.syncMode = .twoWay
        store.setSyncMode(.twoWay, for: pair)
        _ = store.integratedGitConfiguration(for: pair)
        XCTAssertEqual(gitStore.configurations.first?.direction, .bidirectional)
        try await commit("local integrated", at: f.local)
        await store.syncToGitHub(pair)
        XCTAssertTrue(try XCTUnwrap(gitStore.latestJob(syncID: pair.id)).succeeded)
        let localHead = try await git(["rev-parse", "HEAD"], at: f.local)
        let remoteHead = try await git(["rev-parse", "refs/heads/notes"], at: f.bare)
        XCTAssertEqual(localHead, remoteHead)
        pair.githubSync?.repositoryURL = f.root.appendingPathComponent("wrong.git").path
        await store.syncToGitHub(pair)
        if case .failed = store.state(for: pair) {} else { XCTFail("Wrong remote must stop") }
    }
    func testDirtyPullDivergenceAndAutoCommitOffPreserveFiles() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try "dirty".write(to: f.local.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let push = try await run(f, direction: .push)
        XCTAssertTrue(push.succeeded)
        XCTAssertEqual(try String(contentsOf: f.local.appendingPathComponent("note.txt"), encoding: .utf8), "dirty")
        try await commit("remote", at: f.peer); _ = try await git(["push"], at: f.peer)
        let dirty = try await run(f, direction: .pull)
        XCTAssertEqual(dirty.errorCode, .dirtyWorktree)
        try await commit("local", at: f.local)
        let diverged = try await run(f, direction: .bidirectional)
        XCTAssertEqual(diverged.errorCode, .diverged)
    }
    func testAutoCommitFiltersSecretsAndStagingPreservation() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try "allowed".write(to: f.local.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try "new".write(to: f.local.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let result = try await run(f, direction: .bidirectional, auto: true)
        XCTAssertTrue(result.succeeded, result.errorMessage ?? "")
        XCTAssertEqual(result.fileCount, 1)
        let status = try await git(["status", "--porcelain"], at: f.local)
        XCTAssertTrue(status.contains("?? new.txt"))
        _ = try await git(["add", "new.txt"], at: f.local)
        let indexBefore = try Data(contentsOf: f.local.appendingPathComponent(".git/index"))
        let staged = try await run(f, direction: .push, auto: true)
        XCTAssertEqual(staged.errorCode, .stagedChanges)
        XCTAssertEqual(indexBefore, try Data(contentsOf: f.local.appendingPathComponent(".git/index")))
        _ = try await git(["commit", "-m", "user staged"], at: f.local)
        try "password=supersecretvalue".write(to: f.local.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        let secret = try await run(f, direction: .push, auto: true)
        XCTAssertEqual(secret.errorCode, .sensitiveFile)
        XCTAssertFalse(secret.errorMessage?.contains("supersecretvalue") ?? true)
        try "safe".write(to: f.local.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try "safe".write(to: f.local.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let env = try await run(f, direction: .push, auto: true, includes: ["*"])
        XCTAssertEqual(env.errorCode, .sensitiveFile)
    }

    func testAutoCommitTreatsWildcardFilenameLiterallyAndHonorsExclusion() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try "initial wildcard".write(to: f.local.appendingPathComponent("*"), atomically: true, encoding: .utf8)
        _ = try await git(["--literal-pathspecs", "add", "--", "*"], at: f.local)
        _ = try await git(["commit", "-m", "literal wildcard"], at: f.local)
        try "changed wildcard".write(to: f.local.appendingPathComponent("*"), atomically: true, encoding: .utf8)
        try "password=supersecretvalue".write(to: f.local.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let config = GitSyncConfiguration(name: "literal", folder: try FolderReference(url: f.local),
                                          direction: .push, autoCommit: true, excludePatterns: [".env"])
        let job = await GitSyncService().run(configuration: config, job: GitSyncJob(syncID: config.id, direction: .push)) { _ in }
        XCTAssertTrue(job.succeeded, job.errorMessage ?? "")
        let observer = f.root.appendingPathComponent("observer")
        _ = try await git(["clone", "--branch", "notes", f.bare.path, observer.path], at: f.root)
        XCTAssertEqual(try String(contentsOf: observer.appendingPathComponent("*"), encoding: .utf8), "changed wildcard")
        let tree = try await git(["ls-tree", "--name-only", "HEAD"], at: observer)
        XCTAssertTrue(tree.split(separator: "\n").map(String.init).contains("*"))
        XCTAssertFalse(tree.contains(".env"))
        XCTAssertEqual(try String(contentsOf: f.local.appendingPathComponent(".env"), encoding: .utf8), "password=supersecretvalue")
    }

    func testAutoCommitDoesNotDeleteRenameSourceWhenDestinationIsExcluded() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try "rename content".write(to: f.local.appendingPathComponent("old.md"), atomically: true, encoding: .utf8)
        _ = try await git(["add", "old.md"], at: f.local)
        _ = try await git(["commit", "-m", "old file"], at: f.local)
        _ = try await git(["push"], at: f.local)
        try FileManager.default.moveItem(at: f.local.appendingPathComponent("old.md"), to: f.local.appendingPathComponent("new.md"))
        let excluded = GitSyncConfiguration(name: "rename", folder: try FolderReference(url: f.local),
                                            direction: .push, autoCommit: true)
        let skipped = await GitSyncService().run(configuration: excluded, job: GitSyncJob(syncID: excluded.id, direction: .push)) { _ in }
        XCTAssertTrue(skipped.succeeded, skipped.errorMessage ?? "")
        XCTAssertEqual(skipped.commitCount, 0)
        let beforeObserver = f.root.appendingPathComponent("before-observer")
        _ = try await git(["clone", "--branch", "notes", f.bare.path, beforeObserver.path], at: f.root)
        let peerTree = try await git(["ls-tree", "--name-only", "HEAD"], at: beforeObserver)
        XCTAssertTrue(peerTree.contains("old.md"))

        var included = excluded
        included.includePatterns = ["old.md", "new.md"]
        let committed = await GitSyncService().run(configuration: included, job: GitSyncJob(syncID: included.id, direction: .push)) { _ in }
        XCTAssertTrue(committed.succeeded, committed.errorMessage ?? "")
        let observer = f.root.appendingPathComponent("observer")
        _ = try await git(["clone", "--branch", "notes", f.bare.path, observer.path], at: f.root)
        XCTAssertEqual(try String(contentsOf: observer.appendingPathComponent("new.md"), encoding: .utf8), "rename content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: observer.appendingPathComponent("old.md").path))
    }
    func testStoreDuplicatePersistenceAndInterruptedRecovery() async throws {
        let f = try await fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let name = "GitSyncTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        let store = GitSyncStore(storage: defaults)
        let config = GitSyncConfiguration(name: "saved", folder: try FolderReference(url: f.local))
        store.add(config)
        let first = try store.start(syncID: config.id)
        let duplicate = try store.start(syncID: config.id)
        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertThrowsError(try store.start(syncID: config.id, direction: .pull))
        let interrupted = GitSyncStore(storage: defaults)
        XCTAssertEqual(interrupted.configurations.map(\.id), [config.id])
        XCTAssertEqual(interrupted.configurations.first?.name, config.name)
        XCTAssertNotNil(interrupted.configurations.first?.lastRunAt)
        XCTAssertEqual(interrupted.job(id: first.id)?.phase, .interrupted)
        let done = await store.wait(jobID: first.id)
        XCTAssertEqual(done?.success, true)
        let restored = GitSyncStore(storage: defaults)
        XCTAssertEqual(restored.job(id: first.id)?.phase, .completed)
    }
    func testCommandTimeoutCancellationAndSanitizedFailures() async throws {
        let root = FileManager.default.temporaryDirectory
        var runner = GitSyncProcess(executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.1)
        do { _ = try await runner.run(["10"], at: root); XCTFail("must timeout") } catch { XCTAssertEqual((error as? GitSyncFailure)?.code, .timedOut) }
        runner.timeout = 30
        let task = Task { try await runner.run(["10"], at: root) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("must cancel") } catch { XCTAssertEqual((error as? GitSyncFailure)?.code, .cancelled) }
        let authentication = GitSyncProcess.failure("fatal: Authentication failed for https://user:secret@example.com")
        XCTAssertEqual(authentication.code, .authenticationFailed)
        XCTAssertFalse(authentication.message.contains("secret"))
        XCTAssertEqual(GitSyncProcess.failure("Could not resolve host private.example").code, .networkFailed)
    }
}
