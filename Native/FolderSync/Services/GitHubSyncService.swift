import Foundation

struct GitHubCommand: Equatable {
    let arguments: [String]
    let workingDirectory: URL
}

enum GitHubCommandBuilder {
    static func cloneCommand(repositoryURL: String, into mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["clone", "--quiet", repositoryURL, mirror.path], workingDirectory: mirror.deletingLastPathComponent())
    }

    static func remoteURLCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["remote", "get-url", "origin"], workingDirectory: mirror)
    }

    static func remoteURLUpdateCommand(repositoryURL: String, at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["remote", "set-url", "origin", repositoryURL], workingDirectory: mirror)
    }

    static func statusCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["status", "--short"], workingDirectory: mirror)
    }

    static func branchCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["branch", "--show-current"], workingDirectory: mirror)
    }

    static func createMainBranchCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["switch", "-c", "main"], workingDirectory: mirror)
    }

    static func addAllCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["add", "--all"], workingDirectory: mirror)
    }

    static func commitCommand(message: String, at mirror: URL) -> GitHubCommand {
        return GitHubCommand(
            arguments: ["-c", "core.hooksPath=/dev/null", "commit", "-m", message],
            workingDirectory: mirror
        )
    }

    static func pushCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["-c", "core.hooksPath=/dev/null", "push", "--quiet", "--set-upstream", "origin", "HEAD"], workingDirectory: mirror)
    }

    static func pullCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["pull", "--ff-only", "--quiet"], workingDirectory: mirror)
    }

    static func fetchCommand(at mirror: URL) -> GitHubCommand {
        GitHubCommand(arguments: ["fetch", "--quiet", "origin"], workingDirectory: mirror)
    }

    static func latestCommitDateCommand(at mirror: URL, reference: String) -> GitHubCommand {
        GitHubCommand(arguments: ["log", "-1", "--format=%ct", reference], workingDirectory: mirror)
    }

    static func mirrorCommand(
        source: URL,
        to mirror: URL,
        includeHiddenFiles: Bool,
        deleteExtraFiles: Bool = true
    ) -> GitHubCommand {
        var arguments = ["-a"]
        if deleteExtraFiles {
            arguments.append("--delete")
        }
        if !includeHiddenFiles {
            arguments.append("--exclude=.*")
        }
        arguments += ["--exclude=/.git/", "--", contentsPath(source), contentsPath(mirror)]
        return GitHubCommand(
            arguments: arguments,
            workingDirectory: source
        )
    }

    private static func contentsPath(_ folder: URL) -> String {
        folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
    }
}

enum GitHubSyncError: LocalizedError, Equatable {
    case invalidRepositoryURL
    case authenticationRequired
    case folderIsNotDirectory(String)
    case mirrorIsNotRepository(String)
    case mirrorIsInsideSource
    case gitNotAvailable
    case rsyncNotAvailable
    case noBranch
    case remoteMismatch
    case remoteAhead
    case commandTimedOut
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL: AppText.githubInvalidRepositoryURL
        case .authenticationRequired: AppText.githubAuthenticationRequired
        case .folderIsNotDirectory(let path): AppText.inputFolderIsNotDirectory(path)
        case .mirrorIsNotRepository(let path): AppText.githubMirrorIsNotRepository(path)
        case .mirrorIsInsideSource: AppText.githubMirrorIsInsideSource
        case .gitNotAvailable: AppText.githubGitNotAvailable
        case .rsyncNotAvailable: AppText.githubRsyncNotAvailable
        case .noBranch: AppText.githubNoBranch
        case .remoteMismatch: AppText.githubRemoteMismatch
        case .remoteAhead: AppText.githubRemoteAhead
        case .commandTimedOut: AppText.githubCommandTimedOut
        case .commandFailed(let output):
            output.isEmpty ? AppText.githubCommandFailed : AppText.githubCommandFailedWithOutput(output)
        }
    }
}

struct GitHubSyncResult: Equatable {
    let changedFileCount: Int
    let didPush: Bool
}

struct GitHubRepositoryStatus: Equatable {
    let isRepository: Bool
    let remoteURL: String?
    let branch: String?
    let changedFileCount: Int
}

actor GitHubSyncService {
    private let gitURL = URL(filePath: "/usr/bin/git")
    private let rsyncURL = URL(filePath: "/usr/bin/rsync")
    private let commandTimeout: TimeInterval = 120

    func status(at mirror: URL) throws -> GitHubRepositoryStatus {
        guard isRepository(at: mirror) else {
            return GitHubRepositoryStatus(isRepository: false, remoteURL: nil, branch: nil, changedFileCount: 0)
        }

        let remoteURL = try? runGit(GitHubCommandBuilder.remoteURLCommand(at: mirror))
        let branch = try? runGit(GitHubCommandBuilder.branchCommand(at: mirror))
        let changes = try runGit(GitHubCommandBuilder.statusCommand(at: mirror))
        return GitHubRepositoryStatus(
            isRepository: true,
            remoteURL: remoteURL?.trimmedNonEmpty,
            branch: branch?.trimmedNonEmpty,
            changedFileCount: changedFileCount(in: changes)
        )
    }

    func sync(
        source: URL,
        configuration: GitHubSyncConfiguration,
        mirror: URL
    ) throws -> GitHubSyncResult {
        try Self.validateRepositoryURL(configuration.repositoryURL)
        try validateFolder(source)
        try validateMirrorRelationship(source: source, mirror: mirror)
        try ensureMirror(at: mirror, repositoryURL: configuration.repositoryURL)
        try runRsync(GitHubCommandBuilder.mirrorCommand(
            source: source,
            to: mirror,
            includeHiddenFiles: configuration.includeHiddenFiles
        ))

        var branch = try runGit(GitHubCommandBuilder.branchCommand(at: mirror)).trimmedNonEmpty
        if branch.isEmpty {
            _ = try runGit(GitHubCommandBuilder.createMainBranchCommand(at: mirror))
            branch = try runGit(GitHubCommandBuilder.branchCommand(at: mirror)).trimmedNonEmpty
        }
        guard !branch.isEmpty else { throw GitHubSyncError.noBranch }
        _ = try runGit(GitHubCommandBuilder.addAllCommand(at: mirror))
        let status = try runGit(GitHubCommandBuilder.statusCommand(at: mirror))
        let changedFileCount = changedFileCount(in: status)
        guard changedFileCount > 0 else {
            return GitHubSyncResult(changedFileCount: 0, didPush: false)
        }

        let message = configuration.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitMessage = message.isEmpty ? "Sync changes from FolderSync" : message
        _ = try runGit(GitHubCommandBuilder.commitCommand(message: commitMessage, at: mirror))
        do {
            _ = try runGit(GitHubCommandBuilder.pushCommand(at: mirror))
        } catch GitHubSyncError.commandFailed(let output) where output.contains("non-fast-forward") || output.contains("rejected") {
            throw GitHubSyncError.remoteAhead
        }
        return GitHubSyncResult(changedFileCount: changedFileCount, didPush: true)
    }

    func pull(
        target: URL,
        configuration: GitHubSyncConfiguration,
        mirror: URL
    ) throws -> GitHubSyncResult {
        try Self.validateRepositoryURL(configuration.repositoryURL)
        try validateFolder(target)
        try validateMirrorRelationship(source: target, mirror: mirror)
        try ensureMirror(at: mirror, repositoryURL: configuration.repositoryURL)
        var branch = try runGit(GitHubCommandBuilder.branchCommand(at: mirror)).trimmedNonEmpty
        if branch.isEmpty {
            _ = try runGit(GitHubCommandBuilder.createMainBranchCommand(at: mirror))
            branch = try runGit(GitHubCommandBuilder.branchCommand(at: mirror)).trimmedNonEmpty
        }
        guard !branch.isEmpty else { throw GitHubSyncError.noBranch }
        _ = try runGit(GitHubCommandBuilder.pullCommand(at: mirror))
        try runRsync(GitHubCommandBuilder.mirrorCommand(
            source: mirror,
            to: target,
            includeHiddenFiles: configuration.includeHiddenFiles,
            deleteExtraFiles: false
        ))
        return GitHubSyncResult(changedFileCount: 0, didPush: false)
    }

    func freshness(
        localFolder: URL,
        mirror: URL,
        since: Date?,
        includeHiddenFiles: Bool
    ) throws -> GitHubFreshness? {
        guard isRepository(at: mirror) else { return nil }

        let branch = try runGit(GitHubCommandBuilder.branchCommand(at: mirror)).trimmedNonEmpty
        guard !branch.isEmpty else { return nil }
        _ = try runGit(GitHubCommandBuilder.fetchCommand(at: mirror))
        guard let githubDate = tryCommitDate(at: mirror, reference: "origin/\(branch)"),
              let localDate = latestFileModificationDate(at: localFolder, includeHiddenFiles: includeHiddenFiles) else {
            return nil
        }

        if let since {
            let localChanged = localDate > since
            let githubChanged = githubDate > since
            guard localChanged != githubChanged else { return nil }
            return localChanged ? .local : .github
        }

        guard localDate != githubDate else { return nil }
        return localDate > githubDate ? .local : .github
    }

    func updateRemoteURL(repositoryURL: String, at mirror: URL) throws {
        guard isRepository(at: mirror) else { return }
        _ = try runGit(GitHubCommandBuilder.remoteURLUpdateCommand(repositoryURL: repositoryURL, at: mirror))
    }

    static func validateRepositoryURL(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              isRepositoryPath(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw GitHubSyncError.invalidRepositoryURL
        }
    }

    private static func isRepositoryPath(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard components.count == 2, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        return !components[1].contains("?")
    }

    static func repositoryIdentity(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://github.com/") {
            return value.hasSuffix(".git") ? value : value + ".git"
        }
        return value
    }

    private func ensureMirror(at mirror: URL, repositoryURL: String) throws {
        if !FileManager.default.fileExists(atPath: mirror.path) {
            try FileManager.default.createDirectory(at: mirror.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try runGit(GitHubCommandBuilder.cloneCommand(repositoryURL: repositoryURL, into: mirror))
            return
        }
        guard isRepository(at: mirror) else {
            throw GitHubSyncError.mirrorIsNotRepository(mirror.path)
        }
        let currentRemote = try runGit(GitHubCommandBuilder.remoteURLCommand(at: mirror)).trimmedNonEmpty
        guard Self.repositoryIdentity(currentRemote) == Self.repositoryIdentity(repositoryURL) else {
            throw GitHubSyncError.remoteMismatch
        }
    }

    private func validateFolder(_ folder: URL) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GitHubSyncError.folderIsNotDirectory(folder.path)
        }
    }

    private func validateMirrorRelationship(source: URL, mirror: URL) throws {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let mirrorPath = mirror.resolvingSymlinksInPath().standardizedFileURL.path
        guard sourcePath != mirrorPath,
              !mirrorPath.hasPrefix(sourcePath + "/"),
              !sourcePath.hasPrefix(mirrorPath + "/") else {
            throw GitHubSyncError.mirrorIsInsideSource
        }
    }

    private func isRepository(at mirror: URL) -> Bool {
        (try? runGit(GitHubCommand(arguments: ["rev-parse", "--is-inside-work-tree"], workingDirectory: mirror)))?.trimmedNonEmpty == "true"
    }

    private func runGit(_ command: GitHubCommand) throws -> String {
        try run(executableURL: gitURL, command: command)
    }

    private func runRsync(_ command: GitHubCommand) throws {
        guard FileManager.default.isExecutableFile(atPath: rsyncURL.path) else {
            throw GitHubSyncError.rsyncNotAvailable
        }
        _ = try run(executableURL: rsyncURL, command: command)
    }

    private func tryCommitDate(at mirror: URL, reference: String) -> Date? {
        guard let output = try? runGit(GitHubCommandBuilder.latestCommitDateCommand(at: mirror, reference: reference)),
              let timestamp = TimeInterval(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func latestFileModificationDate(at folder: URL, includeHiddenFiles: Bool) -> Date? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return nil
        }

        var latestDate: Date?
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate else {
                continue
            }
            if latestDate == nil || modificationDate > latestDate! {
                latestDate = modificationDate
            }
        }
        return latestDate
    }

    private func run(executableURL: URL, command: GitHubCommand) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw executableURL == gitURL ? GitHubSyncError.gitNotAvailable : GitHubSyncError.rsyncNotAvailable
        }
        let process = Process()
        let output = Pipe()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.standardOutput = output
        process.standardError = output
        try GitHubAuthEnvironment.prepareConfigurationDirectory()
        var environment = GitHubAuthEnvironment.processEnvironment(
            from: ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_CONFIG") }
        )
        environment.merge([
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_EDITOR": "/usr/bin/true",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_ASKPASS": "/usr/bin/false",
            "GIT_SSH_COMMAND": "ssh -o BatchMode=yes"
        ]) { _, new in new }
        if let githubCLI = [
            URL(filePath: "/opt/homebrew/bin/gh"),
            URL(filePath: "/usr/local/bin/gh"),
            URL(filePath: "/usr/bin/gh")
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            environment["GIT_CONFIG_COUNT"] = "1"
            environment["GIT_CONFIG_KEY_0"] = "credential.helper"
            environment["GIT_CONFIG_VALUE_0"] = "!\(githubCLI.path) auth git-credential"
        }
        process.environment = environment
        process.terminationHandler = { _ in completion.signal() }
        do {
            try process.run()
        } catch {
            throw GitHubSyncError.commandFailed(error.localizedDescription)
        }
        guard completion.wait(timeout: .now() + commandTimeout) == .success else {
            process.terminate()
            throw GitHubSyncError.commandTimedOut
        }
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw GitHubSyncError.commandFailed(result)
        }
        return result
    }

    private func changedFileCount(in status: String) -> Int {
        status.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }.count
    }
}

private extension String {
    var trimmedNonEmpty: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
