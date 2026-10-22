import Foundation
import CryptoKit
import Darwin

private actor GitSyncRepositoryLocks {
    static let shared = GitSyncRepositoryLocks()
    private var occupied: Set<String> = []
    func acquire(_ key: String) throws {
        guard occupied.insert(key).inserted else { throw GitSyncFailure(code: .repositoryBusy) }
    }
    func release(_ key: String) { occupied.remove(key) }
}

struct GitSyncService: Sendable {
    var process = GitSyncProcess()

    private func git(_ args: [String], _ url: URL, environment: [String: String] = [:]) async throws -> String {
        let result = try await process.run(args, at: url, environment: environment)
        guard result.status == 0 else { throw GitSyncProcess.failure(result.output) }
        return result.output.trimmingCharacters(in: .newlines)
    }

    func inspect(folder: FolderReference, remote: String = "", branch: String = "") async throws -> GitSyncRepository {
        let url: URL
        do { url = try BookmarkManager.resolve(folder) } catch { throw GitSyncFailure(code: .notRepository) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try await inspect(url: url, remote: remote, branch: branch)
    }

    func inspect(url: URL, remote: String = "", branch: String = "") async throws -> GitSyncRepository {
        let root: String
        do { root = try await git(["rev-parse", "--show-toplevel"], url) }
        catch { throw GitSyncFailure(code: .notRepository) }
        let common = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], url)
        let gitDir = try await git(["rev-parse", "--absolute-git-dir"], url)
        let local = (try? await git(["symbolic-ref", "--quiet", "--short", "HEAD"], url)) ?? ""
        let remotes = try await git(["remote"], url).split(separator: "\n").map(String.init)
        let upstreamRemote = local.isEmpty ? "" : ((try? await git(["config", "--get", "branch.\(local).remote"], url)) ?? "")
        let upstreamBranch = local.isEmpty ? "" : ((try? await git(["config", "--get", "branch.\(local).merge"], url)) ?? "")
        let selectedRemote = remote.isEmpty ? (remotes.contains(upstreamRemote) ? upstreamRemote : (remotes.count == 1 ? remotes[0] : "")) : remote
        let selectedBranch = branch.isEmpty && selectedRemote == upstreamRemote ? String(upstreamBranch.dropFirst(upstreamBranch.hasPrefix("refs/heads/") ? 11 : 0)) : branch
        let branches = (try? await git(["for-each-ref", "--format=%(refname:short)", "refs/remotes"], url))?.split(separator: "\n").map(String.init) ?? []
        return GitSyncRepository(rootPath: root, commonDirectory: URL(fileURLWithPath: common).resolvingSymlinksInPath().standardized.path, gitDirectory: gitDir, localBranch: local, remote: selectedRemote, branch: selectedBranch, remotes: remotes, branches: branches)
    }

    func detect(folder: FolderReference, remote: String = "", branch: String = "") async throws -> GitSyncRepository {
        let repository = try await inspect(folder: folder, remote: remote, branch: branch)
        try await validate(repository)
        return repository
    }

    private func validate(_ repository: GitSyncRepository) async throws {
        guard !repository.localBranch.isEmpty else { throw GitSyncFailure(code: .detachedHead) }
        guard repository.remotes.contains(repository.remote), !repository.remote.hasPrefix("-") else { throw GitSyncFailure(code: .missingRemote) }
        guard !repository.branch.isEmpty, !repository.branch.hasPrefix("-") else { throw GitSyncFailure(code: .missingUpstream) }
        let result = try await process.run(["check-ref-format", "refs/heads/\(repository.branch)"], at: URL(fileURLWithPath: repository.rootPath))
        guard result.status == 0 else { throw GitSyncFailure(code: .missingUpstream) }
    }

    private func checkBusy(_ repository: GitSyncRepository) throws {
        for directory in Set([repository.gitDirectory, repository.commonDirectory]) {
            for name in ["index.lock", "HEAD.lock", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer"] {
                if FileManager.default.fileExists(atPath: directory + "/" + name) { throw GitSyncFailure(code: .repositoryBusy) }
            }
        }
    }

    private func snapshot(_ url: URL) async throws -> String {
        let head = try await git(["rev-parse", "HEAD"], url)
        let branch = try await git(["symbolic-ref", "HEAD"], url)
        let status = try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], url)
        let diff = try await git(["diff", "HEAD", "--binary", "--no-ext-diff"], url)
        var data = Data((head + branch + status + diff).utf8)
        let index = try await git(["rev-parse", "--path-format=absolute", "--git-path", "index"], url)
        data.append(try Data(contentsOf: URL(fileURLWithPath: index)))
        let untracked = try await git(["ls-files", "--others", "--exclude-standard", "-z"], url)
        for path in untracked.split(separator: "\0") {
            if let contents = try? Data(contentsOf: url.appendingPathComponent(String(path))) { data.append(contents) }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func run(configuration: GitSyncConfiguration, job: GitSyncJob, progress: @escaping @Sendable (GitSyncPhase) async -> Void) async -> GitSyncJob {
        var result = job
        var heldLock: String?
        var scopeURL: URL?
        var accessing = false
        do {
            result.phase = .checking
            await progress(.checking)
            do { scopeURL = try BookmarkManager.resolve(configuration.folder) } catch { throw GitSyncFailure(code: .notRepository) }
            let selectedURL = scopeURL!
            accessing = selectedURL.startAccessingSecurityScopedResource()
            let repository = try await inspect(url: selectedURL, remote: configuration.remote, branch: configuration.branch)
            let url = URL(fileURLWithPath: repository.rootPath)
            try await validate(repository)
            try await GitSyncRepositoryLocks.shared.acquire(repository.commonDirectory)
            heldLock = repository.commonDirectory
            try checkBusy(repository)
            var expected = try await snapshot(url)
            func unchanged() async throws {
                try Task.checkCancellation()
                try checkBusy(repository)
                guard try await snapshot(url) == expected else { throw GitSyncFailure(code: .repositoryChanged) }
            }
            let remoteRef = "refs/remotes/\(repository.remote)/\(repository.branch)"
            result.phase = .fetching
            await progress(.fetching)
            _ = try await git(["fetch", "--no-tags", "--", repository.remote, "+refs/heads/\(repository.branch):\(remoteRef)"], url)
            result.steps.append(.init(phase: .fetching, success: true, message: "Fetch 완료"))
            try await unchanged()
            func counts() async throws -> (Int, Int) {
                let text = try await git(["rev-list", "--left-right", "--count", "HEAD...\(remoteRef)"], url)
                let values = text.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                guard values.count == 2 else { throw GitSyncFailure(code: .commandFailed) }
                return (values[0], values[1])
            }
            var (ahead, behind) = try await counts()
            if ahead > 0 && behind > 0 { throw GitSyncFailure(code: .diverged) }
            if job.direction == .push && behind > 0 { throw GitSyncFailure(code: .pushRejected) }
            if configuration.autoCommit && job.direction != .pull {
                result.phase = .committing
            await progress(.committing)
                result.fileCount = try await autoCommit(configuration, repository: repository, url: url, expected: expected)
                expected = try await snapshot(url)
                if result.fileCount > 0 { result.steps.append(.init(phase: .committing, success: true, message: "Commit 완료")) }
                (ahead, behind) = try await counts()
                if ahead > 0 && behind > 0 { throw GitSyncFailure(code: .diverged) }
            }
            if behind > 0 && job.direction != .push {
                try await unchanged()
                guard try await git(["status", "--porcelain=v1", "--untracked-files=all"], url).isEmpty else { throw GitSyncFailure(code: .dirtyWorktree) }
                result.phase = .pulling
            await progress(.pulling)
                let before = try await git(["rev-parse", "HEAD"], url)
                _ = try await git(["merge", "--ff-only", "--no-edit", remoteRef], url)
                let files = try await git(["diff", "--name-only", "-z", before, "HEAD"], url)
                result.fileCount += files.split(separator: "\0").count
                result.commitCount += behind
                result.steps.append(.init(phase: .pulling, success: true, message: "Fast-forward 완료"))
                expected = try await snapshot(url)
            }
            (ahead, behind) = try await counts()
            if ahead > 0 && job.direction != .pull {
                try await unchanged()
                result.phase = .pushing
            await progress(.pushing)
                let pushed = try await process.run(["push", "--porcelain", "--", repository.remote, "HEAD:refs/heads/\(repository.branch)"], at: url)
                guard pushed.status == 0 else { throw GitSyncProcess.failure(pushed.output, fallback: .pushRejected) }
                result.commitCount += ahead
                result.steps.append(.init(phase: .pushing, success: true, message: "Push 완료"))
            }
            result.phase = .verifying
            await progress(.verifying)
            try await unchanged()
            result.localHEAD = try await git(["rev-parse", "HEAD"], url)
            let remote = try await git(["ls-remote", "--exit-code", "--", repository.remote, "refs/heads/\(repository.branch)"], url)
            result.remoteHEAD = remote.split(whereSeparator: \.isWhitespace).first.map(String.init)
            result.verifiedAt = Date()
            if job.direction != .pull && result.localHEAD != result.remoteHEAD { throw GitSyncFailure(code: .pushRejected) }
            if job.direction == .pull && behind == 0 && ahead == 0 && result.localHEAD != result.remoteHEAD { throw GitSyncFailure(code: .repositoryChanged) }
            result.phase = .completed
            result.success = true
        } catch {
            let failure = (error as? GitSyncFailure) ?? GitSyncFailure(code: error is CancellationError ? .cancelled : .commandFailed)
            result.steps.append(.init(phase: result.phase, success: false, message: failure.message))
            result.phase = failure.code == .cancelled ? .cancelled : .failed
            result.success = false
            result.errorCode = failure.code
            result.errorMessage = failure.message
        }
        if let heldLock { await GitSyncRepositoryLocks.shared.release(heldLock) }
        if accessing { scopeURL?.stopAccessingSecurityScopedResource() }
        result.endedAt = Date()
        return result
    }

    private func autoCommit(_ config: GitSyncConfiguration, repository: GitSyncRepository, url: URL, expected: String) async throws -> Int {
        guard try await git(["diff", "--cached", "--name-only", "-z"], url).isEmpty else { throw GitSyncFailure(code: .stagedChanges) }
        let status = try await git(["diff", "--name-status", "--find-renames", "-z", "HEAD"], url)
            .split(separator: "\0").map(String.init)
        let untracked = try await git(["ls-files", "--others", "--exclude-standard", "-z"], url).split(separator: "\0").map(String.init)
        func matches(_ path: String, _ patterns: [String]) -> Bool { patterns.contains { fnmatch($0, path, 0) == 0 } }
        var tracked = [String]()
        var renameSources = Set<String>()
        var statusIndex = 0
        while statusIndex < status.count {
            let change = status[statusIndex]
            statusIndex += 1
            if change.hasPrefix("R") || change.hasPrefix("C") {
                guard statusIndex + 1 < status.count else { throw GitSyncFailure(code: .commandFailed) }
                let oldPath = status[statusIndex]
                let newPath = status[statusIndex + 1]
                statusIndex += 2
                guard !config.includePatterns.isEmpty, matches(newPath, config.includePatterns) else { continue }
                tracked.append(oldPath)
                tracked.append(newPath)
                renameSources.insert(oldPath)
            } else {
                guard statusIndex < status.count else { throw GitSyncFailure(code: .commandFailed) }
                let path = status[statusIndex]
                if change != "D" || matches(path, config.includePatterns) { tracked.append(path) }
                statusIndex += 1
            }
        }
        let candidates = Set(tracked + untracked.filter { matches($0, config.includePatterns) }).filter {
            (renameSources.contains($0) || config.includePatterns.isEmpty || matches($0, config.includePatterns))
                && !matches($0, config.excludePatterns)
        }.sorted()
        guard !candidates.isEmpty else { return 0 }
        for path in candidates {
            let lower = path.lowercased()
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".pem") || name.hasSuffix(".key") || name.hasPrefix("id_rsa") || name.hasPrefix("id_ed25519") || lower.contains(".obsidian/") || lower.contains("credentials") { throw GitSyncFailure(code: .sensitiveFile) }
            if let contents = try? Data(contentsOf: url.appendingPathComponent(path)), let text = String(data: contents, encoding: .utf8) {
                let pattern = "(?i)(-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|(?:api[_-]?key|access[_-]?token|password|secret)\\s*[\\\"']?\\s*[:=]\\s*[\\\"']?[^\\s\\\"']{6,})"
                if text.range(of: pattern, options: .regularExpression) != nil { throw GitSyncFailure(code: .sensitiveFile) }
            }
        }
        guard try await snapshot(url) == expected else { throw GitSyncFailure(code: .repositoryChanged) }
        let index = URL(fileURLWithPath: repository.gitDirectory).appendingPathComponent("index")
        let lock = index.path + ".lock"
        let descriptor = open(lock, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw GitSyncFailure(code: .repositoryBusy) }
        close(descriptor)
        let temporaryIndex = URL(fileURLWithPath: repository.gitDirectory).appendingPathComponent("linkdeck-index-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(atPath: lock)
            try? FileManager.default.removeItem(at: temporaryIndex)
            try? FileManager.default.removeItem(atPath: temporaryIndex.path + ".lock")
        }
        try FileManager.default.copyItem(at: index, to: temporaryIndex)
        let env = ["GIT_INDEX_FILE": temporaryIndex.path]
        _ = try await git(["--literal-pathspecs", "add", "-A", "--"] + candidates, url, environment: env)
        guard try await snapshot(url) == expected else { throw GitSyncFailure(code: .repositoryChanged) }
        let headBeforeCommit = try await git(["rev-parse", "HEAD"], url)
        let commitMessage = config.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = commitMessage.isEmpty ? "Sync changes from LinkDeck" : commitMessage
        do {
            _ = try await git(["commit", "-m", message], url, environment: env)
        } catch {
            let recovery = Task.detached { try await self.git(["rev-parse", "HEAD"], url) }
            if let headAfterCommit = try? await recovery.value, headAfterCommit != headBeforeCommit {
                _ = rename(temporaryIndex.path, index.path)
            }
            throw error
        }
        // Publish the committed index while the real index lock still excludes other writers.
        guard rename(temporaryIndex.path, index.path) == 0 else { throw GitSyncFailure(code: .commandFailed) }
        return candidates.count
    }
}
