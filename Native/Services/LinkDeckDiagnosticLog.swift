import Foundation
import Darwin
import OSLog

enum LinkDeckRequestContext {
    @TaskLocal static var id: String?
}

// The writer queue serializes local writes. A file lock also protects rotation across processes.
final class LinkDeckDiagnosticLog: @unchecked Sendable {
    static let enabledKey = "linkdeck.diagnostics.enabled"
    static let shared = LinkDeckDiagnosticLog {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
    let directory: URL
    private let tunnelLock = NSLock()
    private let writer = DispatchQueue(label: "com.pdg.linkdeck.diagnostics", qos: .utility)
    private let pendingWrites = DispatchSemaphore(value: 1_024)
    private let isEnabled: @Sendable () -> Bool
    private let fileLimit: Int
    private let recordLimit: Int
    private let byteLimit: Int
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()
    private let legacyTimestampFormatter = ISO8601DateFormatter()
    private static let timingEnabled = ProcessInfo.processInfo.environment["LINKDECK_MCP_TIMING"] == "1"
    private struct LogFileIdentity: Equatable {
        let inode: UInt64
        let size: Int
        let modificationDate: Date

        init?(_ url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let inode = attributes[.systemFileNumber] as? NSNumber,
                  let size = attributes[.size] as? NSNumber,
                  let modificationDate = attributes[.modificationDate] as? Date else { return nil }
            self.inode = inode.uint64Value
            self.size = size.intValue
            self.modificationDate = modificationDate
        }
    }

    private var cachedRecords: (file: LogFileIdentity, count: Int)?
    private var tunnelBuffer = Data()
    private var droppingTunnelLine = false
    private let fallback = Logger(subsystem: "com.pdg.linkdeck", category: "diagnostics")

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LinkDeck"),
         fileLimit: Int = 5, recordLimit: Int = 2_000, byteLimit: Int = 1_048_576,
         isEnabled: @escaping @Sendable () -> Bool = { true }) {
        precondition(fileLimit > 0 && recordLimit > 0 && byteLimit >= 512)
        self.isEnabled = isEnabled
        self.directory = directory
        self.fileLimit = fileLimit
        self.recordLimit = recordLimit
        self.byteLimit = byteLimit
    }

    private func file(_ index: Int) -> URL {
        directory.appendingPathComponent(index == 0 ? "events.jsonl" : "events.\(index).jsonl")
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    func record(_ event: String, requestID: String? = LinkDeckRequestContext.id,
                method: String? = nil, tool: String? = nil, app: String? = nil,
                taskID: String? = nil, outcome: String? = nil, code: Int? = nil, elapsedMS: Int? = nil, elapsedUS: Int? = nil) {
        guard isEnabled(), pendingWrites.wait(timeout: .now()) == .success else { return }
        let time = Date()
        let requestID = Self.identifier(requestID)
        let method = Self.identifier(method)
        let tool = Self.identifier(tool)
        let app = Self.identifier(app)
        let taskID = Self.identifier(taskID)
        let outcome = Self.identifier(outcome)
        writer.async {
            defer { self.pendingWrites.signal() }
            self.append(event, time: time, requestID: requestID, method: method, tool: tool,
                        app: app, taskID: taskID, outcome: outcome, code: code, elapsedMS: elapsedMS, elapsedUS: elapsedUS)
        }
    }

    func recordChatViewTask(_ result: [String: Any], tool: String) {
        let isStart = ["chat_view_start_task", "chat_view_start_image_task"].contains(tool)
        guard isStart || ["chat_view_task_status", "chat_view_image_task_status"].contains(tool),
              let rawID = result["taskId"] as? String, let taskID = UUID(uuidString: rawID)?.uuidString else { return }
        if isStart { record("chat_view.task", taskID: taskID) }

        func duration(from start: String, to end: String) -> Int? {
            guard let start = result[start] as? Double, let end = result[end] as? Double else { return nil }
            let milliseconds = ((end - start) * 1_000).rounded()
            guard milliseconds.isFinite, milliseconds >= 0 else { return nil }
            return Int(exactly: milliseconds)
        }

        if let elapsed = duration(from: "createdAt", to: "startedAt") {
            record("chat_view.queue", taskID: taskID, elapsedMS: elapsed)
        }
        if let elapsed = duration(from: "startedAt", to: "completedAt") {
            record("chat_view.execution", taskID: taskID, elapsedMS: elapsed)
        }
    }

    func recordTiming(_ event: String, since start: ContinuousClock.Instant,
                      requestID: String? = LinkDeckRequestContext.id, app: String? = nil) {
        guard Self.timingEnabled else { return }
        let duration = start.duration(to: .now).components
        record(event, requestID: requestID, app: app,
               elapsedUS: Int(duration.seconds * 1_000_000 + duration.attoseconds / 1_000_000_000_000))
    }

    // Only bounded identifiers and fixed outcomes; never arguments, responses, headers or raw errors.
    private static func identifier(_ value: String?) -> String? {
        value.map { String($0.prefix(160).map { $0.isASCII && ($0.isLetter || $0.isNumber || "_./-".contains($0)) ? $0 : "_" }) }
    }

    private func append(_ event: String, time: Date, requestID: String?,
                        method: String?, tool: String?, app: String?,
                        taskID: String?, outcome: String?, code: Int?, elapsedMS: Int?, elapsedUS: Int?) {
        var entry: [String: Any] = ["time": timestampFormatter.string(from: time), "event": Self.identifier(event) ?? "unknown"]
        entry["request_id"] = requestID
        entry["method"] = method
        entry["tool"] = tool
        entry["app"] = app
        entry["task_id"] = taskID
        entry["outcome"] = outcome
        entry["code"] = code
        entry["elapsed_ms"] = elapsedMS
        entry["elapsed_us"] = elapsedUS
        do {
            let line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) + Data([10])
            guard line.count <= byteLimit else { return }
            try prepare()
            // Development and production apps can write concurrently; rotation needs a process-wide lock too.
            let descriptor = open(directory.appendingPathComponent(".writer.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { flock(descriptor, LOCK_UN) }
            let manager = FileManager.default
            let active = file(0)
            let identity = LogFileIdentity(active)
            let size = identity?.size ?? 0
            var records: Int
            if let cachedRecords, cachedRecords.file == identity {
                records = cachedRecords.count
            } else if size <= byteLimit {
                records = (try? Data(contentsOf: active))?.reduce(0) { $0 + ($1 == 10 ? 1 : 0) } ?? 0
            } else {
                records = recordLimit
            }
            if size + line.count > byteLimit || records >= recordLimit {
                records = 0
                cachedRecords = nil
                if manager.fileExists(atPath: file(fileLimit - 1).path) { try manager.removeItem(at: file(fileLimit - 1)) }
                if fileLimit > 1 {
                    for index in stride(from: fileLimit - 2, through: 0, by: -1) {
                        if manager.fileExists(atPath: file(index).path) { try manager.moveItem(at: file(index), to: file(index + 1)) }
                    }
                }
            }
            if !manager.fileExists(atPath: file(0).path) {
                try Data().write(to: file(0), options: .atomic)
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(0).path)
            let handle = try FileHandle(forWritingTo: file(0))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            cachedRecords = LogFileIdentity(active).map { ($0, records + 1) }
        } catch {
            fallback.error("Diagnostic log write failed (code: \((error as NSError).code))")
        }
    }

    func consumeTunnelOutput(_ data: Data) {
        tunnelLock.lock()
        defer { tunnelLock.unlock() }
        for byte in data {
            if byte == 10 {
                if !droppingTunnelLine, !tunnelBuffer.isEmpty {
                    let text = String(decoding: tunnelBuffer, as: UTF8.self).lowercased()
                    let category: String
                    if text.contains("401") || text.contains("token_invalidated") { category = "authentication" }
                    else if text.contains("403") { category = "permission" }
                    else if text.contains("timeout") || text.contains("deadline") { category = "timeout" }
                    else if text.contains("poll failed") || text.contains("connection refused") { category = "connection" }
                    else if text.contains("error") || text.contains("warn") { category = "upstream_error" }
                    else { category = "activity" }
                    // Classify and discard raw output; it may contain credentials or user content.
                    if category != "activity" { record("tunnel.output", outcome: category) }
                }
                tunnelBuffer.removeAll(keepingCapacity: true)
                droppingTunnelLine = false
            } else if !droppingTunnelLine {
                if tunnelBuffer.count < 65_536 { tunnelBuffer.append(byte) }
                else {
                    tunnelBuffer.removeAll(keepingCapacity: true)
                    droppingTunnelLine = true
                    record("tunnel.output", outcome: "oversized_line")
                }
            }
        }
    }

    func finishTunnelOutput() {
        consumeTunnelOutput(Data([10]))
    }

    func waitForPendingWrites() {
        writer.sync {}
    }

    func summary(now: Date = Date()) async throws -> LinkDeckDiagnosticSummary {
        try await withCheckedThrowingContinuation { continuation in
            writer.async {
                continuation.resume(with: Result { try self.readSummary(now: now) })
            }
        }
    }

    private func readSummary(now: Date) throws -> LinkDeckDiagnosticSummary {
        let descriptor = open(directory.appendingPathComponent(".writer.lock").path, O_RDONLY | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return LinkDeckDiagnosticSummary(events: [], now: now) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let data: [Data] = try {
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_SH) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return try (0..<fileLimit).reversed().compactMap { index in
                do { return try Data(contentsOf: file(index)) }
                catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                    return nil
                }
            }
        }()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let text = try value.decode(String.self)
            guard let date = self.timestampFormatter.date(from: text) ?? self.legacyTimestampFormatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid diagnostic timestamp")
            }
            return date
        }
        let events = data.flatMap { file in
            file.split(separator: 10).compactMap { try? decoder.decode(LinkDeckDiagnosticSummary.Event.self, from: Data($0)) }
        }
        return LinkDeckDiagnosticSummary(events: events, now: now)
    }

    static func responseOutcome(_ body: Data, httpStatus: Int = 200) -> String {
        if httpStatus == 202 && body.isEmpty { return "accepted" }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "invalid_response" }
        if object["error"] != nil || (object["result"] as? [String: Any])?["isError"] as? Bool == true { return "tool_error" }
        return "success"
    }
}
