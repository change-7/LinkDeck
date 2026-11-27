import Foundation
import Darwin

enum SubtitlePipelineStep: String, Codable { case transcription, translation, render, publish }

enum SubtitlePipelineState: String, Codable {
    case queuedTranscription = "queued_transcription", transcribing
    case awaitingTranslation = "awaiting_translation", savingTranslation = "saving_translation"
    case queuedRender = "queued_render", rendering, publishing, cancelling, cancelled, failed, interrupted, completed

    var terminal: Bool { [.cancelled, .failed, .interrupted, .completed].contains(self) }
}

struct SubtitlePipelineCue: Codable, Equatable {
    let id: Int
    let timing: String
    let text: String
}

struct SubtitlePipelineShareStackSource: Codable, Equatable {
    let fileID: String
    let leaseID: String
    let sha256: String
    var resultDirectory: String? = nil
    var originalName: String? = nil
    var subtitleRequestKey: String? = nil
    var outputRequestKey: String? = nil
    var subtitleFileID: String? = nil
    var outputFileID: String? = nil
}

struct SubtitlePipelineJob: Codable, Identifiable {
    let id: String
    let mediaPath: String
    let fontSize: Double
    var state: SubtitlePipelineState = .queuedTranscription
    var step: SubtitlePipelineStep = .transcription
    var upstreamID: String?
    var transcriptionID: String?
    var renderID: String?
    var progress: Double = 0
    var error: String?
    var cues: [SubtitlePipelineCue] = []
    var translations: [String: String] = [:]
    var subtitlePath: String?
    var outputPath: String?
    var shareStackSource: SubtitlePipelineShareStackSource? = nil
    var bindings: [String: String] = [:]
    var queueOrder = 0
}

struct SubtitlePipelineBatch: Codable, Identifiable {
    let id: String
    let requestKey: String
    let createdAt: Date
    var jobs: [SubtitlePipelineJob]
}

struct SubtitlePipelineFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class SubtitlePipelineManager {
    typealias Call = @MainActor (SubtitlePipelineStep, String, [String: Any]) async throws -> [String: Any]
    private struct Record: Codable {
        var version = 1
        var heavyJobLimit = 2
        var batches: [SubtitlePipelineBatch] = []
        var sequence = 0
    }
    private struct CuePage: Decodable {
        let cues: [SubtitlePipelineCue]
        let total_cues: Int
        let next_offset: Int
        let has_more: Bool
    }
    private let storage: URL
    private let call: Call
    private let pollInterval: Duration
    private var record: Record
    private var workers: [String: Task<Void, Never>] = [:]
    private var reserved: [String: SubtitlePipelineStep] = [:]
    private var timer: Task<Void, Never>?
    private var lockDescriptor: Int32 = -1
    private var stopped = false
    private(set) var storageError: String?
    var externalBusy: (SubtitlePipelineStep) async -> Bool = { _ in false }

    init(storage: URL, pollInterval: Duration = .seconds(1), automatic: Bool = true, call: @escaping Call) throws {
        self.storage = storage
        self.pollInterval = pollInterval
        self.call = call
        try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(storage.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SubtitlePipelineFailure("Cannot open pipeline lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw SubtitlePipelineFailure("Another LinkDeck instance owns the subtitle queue")
        }
        lockDescriptor = fd
        do {
            record = FileManager.default.fileExists(atPath: storage.path)
                ? try JSONDecoder().decode(Record.self, from: Data(contentsOf: storage)) : Record()
            guard record.version == 1, (1...2).contains(record.heavyJobLimit),
                  Set(record.batches.map(\.id)).count == record.batches.count,
                  Set(record.batches.flatMap(\.jobs).map(\.id)).count == record.batches.flatMap(\.jobs).count else {
                throw SubtitlePipelineFailure("Invalid pipeline record; original file preserved")
            }
            for b in record.batches.indices {
                for j in record.batches[b].jobs.indices {
                    if [.transcribing, .rendering, .publishing, .savingTranslation, .cancelling].contains(record.batches[b].jobs[j].state) {
                        record.batches[b].jobs[j].state = .interrupted
                        record.batches[b].jobs[j].error = "LinkDeck stopped during this step. Retry explicitly to reconcile the app job."
                    }
                }
            }
            try JSONEncoder().encode(record).write(to: storage, options: .atomic)
        } catch { close(fd); lockDescriptor = -1; throw error }
        if automatic { resume() }
    }

    deinit { if lockDescriptor >= 0 { close(lockDescriptor) } }

    var batches: [SubtitlePipelineBatch] { record.batches }
    var heavyJobLimit: Int { record.heavyJobLimit }
    func batch(requestKey: String) -> SubtitlePipelineBatch? { record.batches.first { $0.requestKey == requestKey } }

    func busy(_ step: SubtitlePipelineStep) -> Bool {
        reserved.values.contains(step) || reserved.count >= record.heavyJobLimit
    }
    func claimLegacy(_ step: SubtitlePipelineStep) -> String? {
        guard !stopped, storageError == nil, step != .translation, !busy(step) else { return nil }
        let token = "legacy:" + UUID().uuidString
        reserved[token] = step
        return token
    }
    func releaseLegacy(_ token: String) { reserved.removeValue(forKey: token) }
    func job(_ id: String) -> SubtitlePipelineJob? { record.batches.flatMap(\.jobs).first { $0.id == id } }

    func resume() {
        guard timer == nil, !stopped else { return }
        timer = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                await self?.dispatch()
                do { try await Task.sleep(for: pollInterval) } catch { break }
            }
        }
    }

    func stop() async {
        stopped = true
        timer?.cancel()
        timer = nil
        let running = Array(workers.values)
        running.forEach { $0.cancel() }
        for task in running { await task.value }
        if lockDescriptor >= 0 { close(lockDescriptor); lockDescriptor = -1 }
    }

    private func commit(_ next: Record) throws {
        guard !stopped else { throw SubtitlePipelineFailure("Pipeline is stopped") }
        do {
            try JSONEncoder().encode(next).write(to: storage, options: .atomic)
            record = next
            storageError = nil
        } catch { storageError = error.localizedDescription; throw error }
    }

    private func update(_ id: String, _ change: (inout SubtitlePipelineJob) throws -> Void) throws {
        var next = record
        guard let b = next.batches.firstIndex(where: { $0.jobs.contains { $0.id == id } }),
              let j = next.batches[b].jobs.firstIndex(where: { $0.id == id }) else { throw SubtitlePipelineFailure("Unknown file job ID") }
        try change(&next.batches[b].jobs[j])
        if next.batches[b].jobs[j].state != record.batches[b].jobs[j].state,
           [.queuedTranscription, .queuedRender].contains(next.batches[b].jobs[j].state) {
            next.sequence += 1
            next.batches[b].jobs[j].queueOrder = next.sequence
        }
        try commit(next)
    }

    func start(paths: [String], fontSize: Double = 16, requestKey: String, heavyJobLimit: Int? = nil, bindings: [String: String] = [:], shareStackSources: [SubtitlePipelineShareStackSource]? = nil) throws -> SubtitlePipelineBatch {
        guard !paths.isEmpty, paths.count <= 100, !requestKey.isEmpty, requestKey.utf8.count <= 200,
              fontSize.isFinite, (10...36).contains(fontSize), heavyJobLimit == nil || (1...2).contains(heavyJobLimit!),
              shareStackSources == nil || shareStackSources?.count == paths.count,
              shareStackSources?.allSatisfy({ !$0.fileID.isEmpty && !$0.leaseID.isEmpty && $0.sha256.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil }) ?? true,
              Set(shareStackSources?.map(\.fileID) ?? []).count == (shareStackSources?.count ?? 0) else {
            throw SubtitlePipelineFailure("Provide 1–100 files, request_key, font_size 10–36 and heavy_job_limit 1 or 2")
        }
        let canonical = try paths.map { path -> String in
            guard path.hasPrefix("/"), !path.contains("\0") else { throw SubtitlePipelineFailure("Use absolute local media paths") }
            let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard ["mp4", "mov", "mkv", "webm", "m4v", "avi", "mp3", "wav", "m4a", "aac", "flac", "oga", "ogg", "opus", "aiff", "wma", "mpeg", "mpg", "ts"].contains(file.pathExtension.lowercased()),
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  FileManager.default.isReadableFile(atPath: file.path) else { throw SubtitlePipelineFailure("Unreadable or unsupported media: " + path) }
            return file.path
        }
        guard Set(canonical).count == canonical.count else { throw SubtitlePipelineFailure("Duplicate media in batch") }
        if let existing = record.batches.first(where: { $0.requestKey == requestKey }) {
            let requestedIDs: [String?] = shareStackSources?.map { Optional($0.fileID) } ?? Array<String?>(repeating: nil, count: paths.count)
            guard existing.jobs.map(\.mediaPath) == canonical, existing.jobs.allSatisfy({ $0.fontSize == fontSize }),
                  existing.jobs.map({ $0.shareStackSource?.fileID }) == requestedIDs else {
                throw SubtitlePipelineFailure("request_key already belongs to different inputs")
            }
            return existing
        }
        let active = Set(record.batches.flatMap(\.jobs).filter { ![.completed, .cancelled].contains($0.state) }.map(\.mediaPath))
        guard active.isDisjoint(with: canonical) else { throw SubtitlePipelineFailure("A file already has an active pipeline job; inspect existing batches") }
        var next = record
        let jobs = canonical.enumerated().map { index, path in
            next.sequence += 1
            var job = SubtitlePipelineJob(id: UUID().uuidString, mediaPath: path, fontSize: fontSize)
            job.bindings = bindings
            job.shareStackSource = shareStackSources?[index]
            job.queueOrder = next.sequence
            return job
        }
        let batch = SubtitlePipelineBatch(id: UUID().uuidString, requestKey: requestKey, createdAt: Date(), jobs: jobs)
        if let heavyJobLimit { next.heavyJobLimit = heavyJobLimit }
        next.batches.append(batch)
        try commit(next)
        return batch
    }

    func pendingCues(jobID: String, offset: Int = 0, limit: Int = 100) throws -> [SubtitlePipelineCue] {
        guard let job = job(jobID), job.state == .awaitingTranslation,
              offset >= 0, offset <= job.cues.count, (1...100).contains(limit) else { throw SubtitlePipelineFailure("Invalid pagination or job is not awaiting translation") }
        return Array(job.cues.dropFirst(offset).prefix(limit).filter { job.translations[String($0.id)] == nil })
    }

    func submit(jobID: String, translations: [String: String]) throws {
        guard let current = job(jobID), !translations.isEmpty, translations.count <= 100 else { throw SubtitlePipelineFailure("Submit 1–100 translated cues") }
        let allowed = Set(current.cues.map { String($0.id) })
        var validated: [String: String] = [:]
        for (id, raw) in translations {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowed.contains(id), !text.isEmpty, text.utf8.count <= 10_000, !text.contains("\0"),
                  !text.contains("\r"), !text.contains("-->"), text.range(of: "\n[\\t ]*\n", options: .regularExpression) == nil else {
                throw SubtitlePipelineFailure("Invalid translated cue " + id)
            }
            guard current.translations[id] == nil || current.translations[id] == text else { throw SubtitlePipelineFailure("Conflicting duplicate cue " + id) }
            validated[id] = text
        }
        if current.state != .awaitingTranslation {
            guard ![.cancelled, .cancelling].contains(current.state), validated.allSatisfy({ current.translations[$0.key] == $0.value }) else {
                throw SubtitlePipelineFailure("Job is not awaiting translation")
            }
            return
        }
        try update(jobID) { job in
            job.translations.merge(validated) { old, _ in old }
            job.progress = Double(job.translations.count) / Double(job.cues.count)
            if job.translations.count == job.cues.count { job.state = .savingTranslation; job.step = .translation }
        }
    }

    func cancel(batchID: String, jobID: String? = nil) throws {
        guard let batch = record.batches.first(where: { $0.id == batchID }),
              jobID == nil || batch.jobs.contains(where: { $0.id == jobID }) else { throw SubtitlePipelineFailure("Unknown batch or file job ID") }
        var next = record
        let b = next.batches.firstIndex { $0.id == batchID }!
        for j in next.batches[b].jobs.indices where jobID == nil || next.batches[b].jobs[j].id == jobID {
            let id = next.batches[b].jobs[j].id
            if next.batches[b].jobs[j].state != .completed && next.batches[b].jobs[j].state != .cancelled {
                // Interrupted upstream attempts must also be reconciled before a slot is released.
                next.batches[b].jobs[j].state = workers[id] != nil || next.batches[b].jobs[j].upstreamID != nil ? .cancelling : .cancelled
            }
        }
        try commit(next)
    }

    func retry(jobID: String, step: SubtitlePipelineStep) throws {
        guard let current = job(jobID), [.failed, .interrupted].contains(current.state), current.step == step,
              workers[jobID] == nil else { throw SubtitlePipelineFailure("Only the failed or interrupted step can be retried") }
        try update(jobID) { job in
            job.error = nil
            job.progress = 0
            job.state = step == .transcription ? .queuedTranscription : step == .translation ? .savingTranslation : step == .render ? .queuedRender : .publishing
        }
    }

    private func dispatch() async {
        guard !stopped, storageError == nil else { return }
        for current in record.batches.flatMap(\.jobs).sorted(by: { $0.queueOrder < $1.queueOrder }) where workers[current.id] == nil {
            let step: SubtitlePipelineStep
            switch current.state {
            case .queuedTranscription: step = .transcription
            case .queuedRender: step = .render
            case .savingTranslation: step = .translation
            case .publishing: step = .publish
            case .cancelling: step = current.step
            default: continue
            }
            if step == .transcription || step == .render {
                guard !busy(step) else { continue }
                reserved[current.id] = step
                if current.upstreamID == nil {
                    if await externalBusy(step) { reserved.removeValue(forKey: current.id); continue }
                }
                guard !stopped, storageError == nil, job(current.id)?.state == current.state, workers[current.id] == nil else {
                    reserved.removeValue(forKey: current.id)
                    continue
                }
            }
            do {
                try update(current.id) { job in
                    if job.state != .cancelling { job.state = step == .transcription ? .transcribing : step == .render ? .rendering : step == .publish ? .publishing : .savingTranslation }
                    job.step = step
                }
                workers[current.id] = Task { [weak self] in await self?.run(current.id, step: step) }
            } catch { reserved.removeValue(forKey: current.id); return }
        }
    }

    private func invoke(_ id: String, _ step: SubtitlePipelineStep, _ tool: String, _ arguments: [String: Any]) async throws -> [String: Any] {
        var arguments = arguments
        arguments["_pipeline_bindings"] = job(id)?.bindings ?? [:]
        return try await call(step, tool, arguments)
    }

    private func run(_ id: String, step: SubtitlePipelineStep) async {
        defer { workers.removeValue(forKey: id); reserved.removeValue(forKey: id) }
        do {
            guard let initial = job(id) else { return }
            if step == .translation {
                try await exportTranslation(id)
                return
            }
            if step == .publish {
                try await publish(id)
                return
            }
            var upstreamID = initial.upstreamID
            if let existing = upstreamID {
                let result = try await invoke(id, step, statusTool(step), ["job_id": existing])
                let state = remoteState(result)
                if terminalRemote(state), job(id)?.state == .cancelling {
                    try update(id) { $0.state = .cancelled }
                    return
                }
                if state == "completed", initial.state != .cancelling {
                    try await finish(id, step: step, result: result)
                    return
                }
                if terminalRemote(state), initial.state != .cancelling {
                    upstreamID = nil
                    try update(id) { $0.upstreamID = nil }
                    if await externalBusy(step) {
                        try update(id) { job in
                            job.state = job.state == .cancelling ? .cancelled : step == .transcription ? .queuedTranscription : .queuedRender
                        }
                        return
                    }
                }
            }
            if job(id)?.state == .cancelling, upstreamID == nil { try update(id) { $0.state = .cancelled }; return }
            if upstreamID == nil {
                try Task.checkCancellation()
                let result: [String: Any]
                if step == .transcription {
                    result = try await invoke(id, step, "start_transcription", ["file_path": initial.mediaPath])
                } else {
                    guard let subtitle = initial.subtitlePath, FileManager.default.isReadableFile(atPath: subtitle) else { throw SubtitlePipelineFailure("Translated SRT is missing") }
                    let stem = URL(fileURLWithPath: initial.mediaPath).deletingPathExtension().lastPathComponent
                    result = try await invoke(id, step, "burn_subtitles", ["media_path": initial.mediaPath, "subtitle_path": subtitle,
                        "font_size": initial.fontSize, "output_name": initial.shareStackSource?.originalName.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? (stem + "-ko-" + id)])
                }
                guard let remote = (result["job_id"] ?? result["id"]) as? String, !remote.isEmpty else {
                    throw SubtitlePipelineFailure("App start returned no job ID; inspect app before retrying")
                }
                upstreamID = remote
                try update(id) { job in
                    job.upstreamID = remote
                    if step == .transcription { job.transcriptionID = remote } else { job.renderID = remote }
                }
            }
            guard let remote = upstreamID else { throw SubtitlePipelineFailure("Missing app job ID") }
            var cancellationSent = false
            while true {
                try Task.checkCancellation()
                if job(id)?.state == .cancelling && !cancellationSent {
                    _ = try await invoke(id, step, step == .transcription ? "cancel_transcription" : "cancel_subtitle_render", ["job_id": remote])
                    cancellationSent = true
                }
                let status = try await invoke(id, step, statusTool(step), ["job_id": remote])
                let state = remoteState(status)
                if terminalRemote(state) {
                    if job(id)?.state == .cancelling { try update(id) { $0.state = .cancelled }; return }
                    guard state == "completed" else { throw SubtitlePipelineFailure(status["error"] as? String ?? "App job " + state) }
                    try await finish(id, step: step, result: status)
                    return
                }
                if let progress = status["progress"] as? Double, progress.isFinite {
                    try update(id) { $0.progress = min(1, max(0, progress)) }
                }
                try await Task.sleep(for: pollInterval)
            }
        } catch {
            do {
                // A failed call may have stopped the app connection. Never repeat an uncertain start automatically.
                var next = record
                if let b = next.batches.firstIndex(where: { $0.jobs.contains { $0.id == id } }), let j = next.batches[b].jobs.firstIndex(where: { $0.id == id }) {
                    next.batches[b].jobs[j].state = error is CancellationError || stopped ? .interrupted : .failed
                    next.batches[b].jobs[j].error = error.localizedDescription
                    try JSONEncoder().encode(next).write(to: storage, options: .atomic)
                    record = next
                }
            } catch { storageError = error.localizedDescription }
        }
    }

    private func statusTool(_ step: SubtitlePipelineStep) -> String { step == .transcription ? "get_transcription_status" : "get_subtitle_status" }
    private func remoteState(_ result: [String: Any]) -> String { (result["state"] ?? result["phase"]) as? String ?? "unknown" }
    private func terminalRemote(_ state: String) -> Bool { ["completed", "failed", "cancelled", "canceled", "interrupted"].contains(state) }

    private func finish(_ id: String, step: SubtitlePipelineStep, result: [String: Any]) async throws {
        if step == .render {
            guard let output = result["output_path"] as? String, output.hasPrefix("/"), FileManager.default.isReadableFile(atPath: output) else { throw SubtitlePipelineFailure("Renderer completed without a readable MP4") }
            try update(id) { job in
                guard job.state != .cancelling else { job.state = .cancelled; return }
                job.outputPath = output
                job.state = job.shareStackSource == nil ? .completed : .publishing
                job.step = job.shareStackSource == nil ? .render : .publish
                job.progress = job.shareStackSource == nil ? 1 : 0
                job.upstreamID = nil
            }
        } else {
            guard let remote = job(id)?.transcriptionID else { throw SubtitlePipelineFailure("Missing transcription ID") }
            var cues: [SubtitlePipelineCue] = []
            var total: Int?
            while true {
                try Task.checkCancellation()
                let page = try await invoke(id, .transcription, "get_subtitle", ["job_id": remote, "offset": cues.count, "limit": 100])
                let decoded = try JSONDecoder().decode(CuePage.self, from: JSONSerialization.data(withJSONObject: page))
                guard !decoded.cues.isEmpty, decoded.cues.count <= 100,
                      decoded.total_cues > 0, decoded.total_cues <= 1_000_000,
                      total == nil || total == decoded.total_cues,
                      decoded.next_offset == cues.count + decoded.cues.count,
                      decoded.next_offset <= decoded.total_cues,
                      decoded.has_more == (decoded.next_offset < decoded.total_cues) else { throw SubtitlePipelineFailure("Missing or inconsistent subtitle cues") }
                total = decoded.total_cues
                cues.append(contentsOf: decoded.cues)
                if !decoded.has_more { break }
            }
            guard Set(cues.map(\.id)).count == cues.count, cues.allSatisfy({ $0.id > 0 && !$0.text.isEmpty && $0.timing.range(of: #"^\d{2,}:\d{2}:\d{2},\d{3} --> \d{2,}:\d{2}:\d{2},\d{3}$"#, options: .regularExpression) != nil }) else {
                throw SubtitlePipelineFailure("Invalid subtitle IDs or timestamps")
            }
            try update(id) { job in
                guard job.state != .cancelling else { job.state = .cancelled; return }
                job.cues = cues; job.state = .awaitingTranslation; job.step = .translation; job.progress = 0; job.upstreamID = nil
            }
        }
    }

    private func exportTranslation(_ id: String) async throws {
        guard let current = job(id) else { return }
        if current.state == .cancelling { try update(id) { $0.state = .cancelled }; return }
        guard let remote = current.transcriptionID, !current.cues.isEmpty,
              current.cues.allSatisfy({ current.translations[String($0.id)] != nil }) else { throw SubtitlePipelineFailure("Translation is incomplete") }
        var final: [String: Any] = [:]
        for offset in stride(from: 0, to: current.cues.count, by: 100) {
            try Task.checkCancellation()
            if job(id)?.state == .cancelling { try update(id) { $0.state = .cancelled }; return }
            let entries = Dictionary(uniqueKeysWithValues: current.cues.dropFirst(offset).prefix(100).map { (String($0.id), current.translations[String($0.id)]!) })
            final = try await invoke(id, .translation, "save_translated_subtitle", ["job_id": remote, "language": "ko", "translations": entries])
        }
        guard final["complete"] as? Bool == true, let path = final["local_path"] as? String, path.hasPrefix("/") else { throw SubtitlePipelineFailure("Whisper did not export complete Korean SRT") }
        let expected = current.cues.map { "\($0.id)\n\($0.timing)\n\(current.translations[String($0.id)]!)\n" }.joined(separator: "\n")
        let actual = try String(contentsOfFile: path, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        guard actual.trimmingCharacters(in: .whitespacesAndNewlines) == expected.trimmingCharacters(in: .whitespacesAndNewlines) else { throw SubtitlePipelineFailure("Exported SRT differs from accepted translations or timestamps") }
        try update(id) { job in
            guard job.state != .cancelling else { job.state = .cancelled; return }
            job.subtitlePath = path; job.step = .render; job.state = .queuedRender; job.progress = 0
        }
    }

    private func publish(_ id: String) async throws {
        guard let current = job(id), let source = current.shareStackSource,
              let subtitlePath = current.subtitlePath, FileManager.default.isReadableFile(atPath: subtitlePath),
              let outputPath = current.outputPath, FileManager.default.isReadableFile(atPath: outputPath) else {
            throw SubtitlePipelineFailure("ShareStack publish inputs are unavailable")
        }
        let results: [(kind: String, path: String, fileID: String?)] = [
            ("srt", subtitlePath, source.subtitleFileID), ("mp4", outputPath, source.outputFileID)
        ]
        for result in results where result.fileID == nil {
            if job(id)?.state == .cancelling { try update(id) { $0.state = .cancelled }; return }
            guard let directory = source.resultDirectory, let originalName = source.originalName else {
                throw SubtitlePipelineFailure("ShareStack lease must be prepared again")
            }
            let filename = URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent + "." + result.kind
            let destination = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(filename)
            let input = URL(fileURLWithPath: result.path)
            if input.standardizedFileURL != destination.standardizedFileURL {
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard FileManager.default.contentsEqual(atPath: input.path, andPath: destination.path) else {
                        throw SubtitlePipelineFailure("ShareStack result filename already contains different data")
                    }
                } else { try FileManager.default.copyItem(at: input, to: destination) }
            }
            let existingKey = result.kind == "srt" ? job(id)?.shareStackSource?.subtitleRequestKey : job(id)?.shareStackSource?.outputRequestKey
            let requestKey = existingKey ?? UUID().uuidString
            try update(id) { job in
                if result.kind == "srt" { job.shareStackSource?.subtitleRequestKey = requestKey }
                else { job.shareStackSource?.outputRequestKey = requestKey }
            }
            let registration = try await invoke(id, .publish, "register_processed_media", [
                "leaseID": source.leaseID, "filename": filename,
                "mimeType": result.kind == "srt" ? "application/x-subrip" : "video/mp4", "requestKey": requestKey
            ])
            let response = try await SubtitleShareStackJob.wait(registration) { remoteID in
                try await self.invoke(id, .publish, "get_job", ["id": remoteID])
            }
            guard let media = response["processedMedia"] as? [String: Any], let fileID = media["id"] as? String, !fileID.isEmpty else {
                throw SubtitlePipelineFailure("ShareStack did not return the registered file ID")
            }
            try update(id) { job in
                if result.kind == "srt" { job.shareStackSource?.subtitleFileID = fileID }
                else { job.shareStackSource?.outputFileID = fileID }
                let published = [job.shareStackSource?.subtitleFileID, job.shareStackSource?.outputFileID].compactMap { $0 }.count
                job.progress = Double(published) / 2
            }
        }
        try update(id) { job in
            if job.state == .cancelling { job.state = .cancelled; return }
            guard job.shareStackSource?.subtitleFileID != nil, job.shareStackSource?.outputFileID != nil else {
                throw SubtitlePipelineFailure("ShareStack results are not fully registered")
            }
            job.state = .completed; job.progress = 1; job.error = nil
        }
    }
}

@MainActor
enum SubtitleShareStackJob {
    static func wait(_ initial: [String: Any], poll: (String) async throws -> [String: Any]) async throws -> [String: Any] {
        guard let id = initial["id"] as? String, UUID(uuidString: id) != nil else { throw SubtitlePipelineFailure("ShareStack returned no job ID") }
        var current = initial
        while true {
            try Task.checkCancellation()
            let status = current["status"] as? String ?? ""
            if status == "succeeded" { return current }
            guard ["queued", "running", "cancelling"].contains(status) else { throw SubtitlePipelineFailure("ShareStack job failed: " + status) }
            try await Task.sleep(for: .milliseconds(500))
            current = try await poll(id)
        }
    }
}
