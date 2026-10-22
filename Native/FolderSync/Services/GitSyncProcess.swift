import Foundation
import Darwin

struct GitSyncCommandResult: Sendable { let output: String; let status: Int32 }

struct GitSyncProcess: Sendable {
    var executable = URL(fileURLWithPath: "/usr/bin/git")
    var timeout: TimeInterval = 120

    func run(_ arguments: [String], at directory: URL, environment: [String: String] = [:]) async throws -> GitSyncCommandResult {
        let task = Task.detached { () throws -> GitSyncCommandResult in
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: temporary) }
            let outputURL = temporary.appendingPathComponent("output")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            var env = ProcessInfo.processInfo.environment
            for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"] { env.removeValue(forKey: key) }
            env["GIT_TERMINAL_PROMPT"] = "0"
            env["LC_ALL"] = "C"
            env.merge(environment) { _, new in new }
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            try Task.checkCancellation()
            do { try process.run() } catch { throw GitSyncFailure(code: .commandFailed) }
            let deadline = Date().addingTimeInterval(timeout)
            var stopped: GitSyncErrorCode?
            while process.isRunning {
                if Task.isCancelled || Date() >= deadline {
                    stopped = Task.isCancelled ? .cancelled : .timedOut
                    process.terminate()
                    let grace = Date().addingTimeInterval(1)
                    while process.isRunning && Date() < grace { try? await Task.sleep(for: .milliseconds(20)) }
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            while process.isRunning { try? await Task.sleep(for: .milliseconds(20)) }
            if let stopped { throw GitSyncFailure(code: stopped) }
            let data = try Data(contentsOf: outputURL)
            return GitSyncCommandResult(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    static func failure(_ output: String, fallback: GitSyncErrorCode = .commandFailed) -> GitSyncFailure {
        let text = output.lowercased()
        if ["authentication failed", "permission denied", "could not read username", "terminal prompts disabled"].contains(where: text.contains) { return GitSyncFailure(code: .authenticationFailed) }
        if ["could not resolve", "unable to access", "connection refused", "network is unreachable", "connection timed out"].contains(where: text.contains) { return GitSyncFailure(code: .networkFailed) }
        if text.contains("index.lock") || text.contains("cannot lock ref") { return GitSyncFailure(code: .repositoryBusy) }
        return GitSyncFailure(code: fallback)
    }
}
