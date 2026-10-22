import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class SubtitlePipelineTests: XCTestCase {
    private final class Flags {
        var transcriptionDone = false
        var renderingDone = false
        var fail = true
        var externalBusy = true
    }
    func testThreeFilesPipelineOverlapAndDurableTranslations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try (1...3).map { number in
            let file = root.appendingPathComponent("file\(number).mp4")
            try Data([0]).write(to: file)
            return file.path
        }
        var starts: [String] = []
        var completed: Set<String> = []
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), pollInterval: .milliseconds(10)) { app, tool, args in
            let id = args["job_id"] as? String ?? ""
            if tool == "start_transcription" {
                let path = args["file_path"] as! String
                starts.append(path)
                return ["id": path, "state": "transcribing"]
            }
            if tool == "get_transcription_status" { return ["state": completed.contains("cancelled:" + id) ? "cancelled" : completed.contains(id) ? "completed" : "transcribing"] }
            if tool == "cancel_transcription" { completed.insert("cancelled:" + id); return ["state": "cancelling"] }
            if tool == "get_subtitle" { return ["cues": [["id": 1, "timing": "00:00:00,000 --> 00:00:01,000", "text": "Hello"]], "total_cues": 1, "next_offset": 1, "has_more": false] }
            if tool == "save_translated_subtitle" {
                let output = root.appendingPathComponent(UUID().uuidString + ".srt")
                try "1\n00:00:00,000 --> 00:00:01,000\n안녕하세요\n".write(to: output, atomically: true, encoding: .utf8)
                return ["complete": true, "local_path": output.path]
            }
            if tool == "burn_subtitles" { return ["job_id": "render", "phase": "rendering"] }
            if tool == "get_subtitle_status" { return ["phase": "rendering", "progress": 0.5] }
            return [:]
        }
        let batch = try manager.start(paths: paths, requestKey: "session-1")
        try await eventually { starts.count == 1 }
        completed.insert(paths[0])
        try await eventually { manager.job(batch.jobs[0].id)?.state == .awaitingTranslation && starts.count == 2 }
        XCTAssertEqual(starts, Array(paths.prefix(2)))
        let cues = try manager.pendingCues(jobID: batch.jobs[0].id, offset: 0, limit: 100)
        XCTAssertEqual(cues.count, 1)
        try manager.submit(jobID: batch.jobs[0].id, translations: ["1": "안녕하세요"])
        try await eventually { manager.job(batch.jobs[0].id)?.state == .rendering }
        completed.insert(paths[1])
        try await eventually { manager.job(batch.jobs[1].id)?.state == .awaitingTranslation && starts.count == 3 }
        XCTAssertEqual(manager.job(batch.jobs[0].id)?.state, .rendering)
        XCTAssertThrowsError(try manager.submit(jobID: batch.jobs[0].id, translations: ["1": "다른 번역"]))
        try manager.submit(jobID: batch.jobs[0].id, translations: ["1": "안녕하세요"])
        XCTAssertEqual(try manager.start(paths: paths, requestKey: "session-1").id, batch.id)
        XCTAssertThrowsError(try manager.start(paths: [paths[0]], requestKey: "session-2"))
        try manager.cancel(batchID: batch.id, jobID: batch.jobs[2].id)
        try await eventually { manager.job(batch.jobs[2].id)?.state == .cancelled }
        XCTAssertEqual(manager.job(batch.jobs[0].id)?.state, .rendering)
        await manager.stop()
        let restored = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), automatic: false) { _, _, _ in [:] }
        XCTAssertEqual(restored.job(batch.jobs[1].id)?.state, .awaitingTranslation)
        XCTAssertEqual(restored.job(batch.jobs[0].id)?.translations["1"], "안녕하세요")
        XCTAssertEqual(restored.job(batch.jobs[0].id)?.state, .interrupted)
        await restored.stop()
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    func testPaginationAtomicSubmissionsAndSingleHeavySlot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try (1...2).map { number in
            let file = root.appendingPathComponent("input\(number).mp3")
            try Data([0]).write(to: file); return file.path
        }
        var starts = 0
        let flags = Flags()
        var cancellation = false
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), pollInterval: .milliseconds(10)) { _, tool, args in
            switch tool {
            case "start_transcription": starts += 1; return ["id": "trans-\(starts)"]
            case "get_transcription_status": return ["state": cancellation ? "cancelled" : flags.transcriptionDone ? "completed" : "transcribing"]
            case "get_subtitle":
                let offset = args["offset"] as! Int
                let all = (1...101).map { ["id": $0, "timing": "00:00:00,000 --> 00:00:01,000", "text": "Source \($0)"] as [String: Any] }
                return ["cues": Array(all.dropFirst(offset).prefix(100)), "total_cues": 101, "next_offset": min(101, offset + 100), "has_more": offset == 0]
            case "save_translated_subtitle":
                let file = root.appendingPathComponent("ko.srt")
                try (1...101).map { "\($0)\n00:00:00,000 --> 00:00:01,000\n번역 \($0)\n" }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
                return ["complete": true, "local_path": file.path]
            case "burn_subtitles": return ["job_id": "render"]
            case "get_subtitle_status":
                let file = root.appendingPathComponent("result.mp4")
                try Data([1]).write(to: file)
                return ["phase": flags.renderingDone ? "completed" : "rendering", "output_path": file.path]
            case "cancel_transcription": cancellation = true; return ["state": "cancelled"]
            default: return [:]
            }
        }
        let first = try manager.start(paths: [paths[0]], requestKey: "first", heavyJobLimit: 1)
        let id = first.jobs[0].id
        try await eventually { starts == 1 }
        flags.transcriptionDone = true
        try await eventually { manager.job(id)?.state == .awaitingTranslation }
        XCTAssertEqual(try manager.pendingCues(jobID: id, limit: 100).count, 100)
        XCTAssertEqual(try manager.pendingCues(jobID: id, offset: 100).first?.id, 101)
        XCTAssertThrowsError(try manager.pendingCues(jobID: id, limit: 101))
        XCTAssertThrowsError(try manager.submit(jobID: id, translations: ["1": "번역 1", "999": "알 수 없음"]))
        XCTAssertTrue(manager.job(id)!.translations.isEmpty)
        try manager.submit(jobID: id, translations: Dictionary(uniqueKeysWithValues: (1...100).map { (String($0), "번역 \($0)") }))
        XCTAssertEqual(manager.job(id)?.state, .awaitingTranslation)
        try manager.submit(jobID: id, translations: ["101": "번역 101"])
        try await eventually { manager.job(id)?.state == .rendering }
        let second = try manager.start(paths: [paths[1]], requestKey: "second")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(starts, 1)
        flags.renderingDone = true
        try await eventually { manager.job(id)?.state == .completed && starts == 2 }
        XCTAssertNotNil(manager.job(id)?.outputPath)
        try manager.cancel(batchID: second.id)
        await manager.stop()
    }

    func testFailureRetryCorruptRecordAndExclusiveOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("input.wav")
        try Data([0]).write(to: media)
        let storage = root.appendingPathComponent("state.json")
        let flags = Flags()
        var starts = 0
        let manager = try SubtitlePipelineManager(storage: storage, pollInterval: .milliseconds(10)) { _, tool, _ in
            if tool == "start_transcription" { starts += 1; if flags.fail { throw SubtitlePipelineFailure("fixture engine error") }; return ["id": "retry"] }
            return ["state": "transcribing"]
        }
        XCTAssertThrowsError(try SubtitlePipelineManager(storage: storage, automatic: false) { _, _, _ in [:] })
        let batch = try manager.start(paths: [media.path], requestKey: "retry")
        let id = batch.jobs[0].id
        try await eventually { manager.job(id)?.state == .failed }
        XCTAssertEqual(manager.job(id)?.error, "fixture engine error")
        XCTAssertThrowsError(try manager.retry(jobID: id, step: .render))
        flags.fail = false
        try manager.retry(jobID: id, step: .transcription)
        try await eventually { starts == 2 && manager.job(id)?.state == .transcribing }
        XCTAssertThrowsError(try manager.retry(jobID: id, step: .transcription))
        await manager.stop()
        try Data("corrupt".utf8).write(to: storage)
        XCTAssertThrowsError(try SubtitlePipelineManager(storage: storage, automatic: false) { _, _, _ in [:] })
        XCTAssertEqual(try String(contentsOf: storage, encoding: .utf8), "corrupt")
    }

    func testPersistenceFailureDoesNotRegisterOrDispatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        let media = root.appendingPathComponent("input.wav")
        try Data([0]).write(to: media)
        var starts = 0
        let manager = try SubtitlePipelineManager(storage: storage, pollInterval: .milliseconds(10)) { _, _, _ in starts += 1; return [:] }
        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: false)
        XCTAssertThrowsError(try manager.start(paths: [media.path], requestKey: "write-failure"))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(manager.batches.isEmpty)
        XCTAssertEqual(starts, 0)
        XCTAssertNotNil(manager.storageError)
        await manager.stop()
    }

    func testCancelRestoredLostRenderDoesNotCallUnknownCancel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        var job = SubtitlePipelineJob(id: "file", mediaPath: "/tmp/input.mp4", fontSize: 16)
        job.state = .interrupted; job.step = .render; job.upstreamID = "lost-render"
        let batch = SubtitlePipelineBatch(id: "batch", requestKey: "restore", createdAt: Date(), jobs: [job])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
        try JSONSerialization.data(withJSONObject: ["version": 1, "sequence": 1, "heavyJobLimit": 2, "batches": [encoded]]).write(to: storage)
        var cancels = 0
        let manager = try SubtitlePipelineManager(storage: storage, pollInterval: .milliseconds(10)) { _, tool, _ in
            if tool == "get_subtitle_status" { return ["state": "interrupted"] }
            cancels += 1
            throw SubtitlePipelineFailure("Unknown subtitle job_id")
        }
        try manager.cancel(batchID: "batch", jobID: "file")
        try await eventually { manager.job("file")?.state == .cancelled }
        XCTAssertEqual(cancels, 0)
        await manager.stop()
    }

    func testRetryLostRenderRechecksSingleHeavySlot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let subtitle = root.appendingPathComponent("ko.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\n번역\n".write(to: subtitle, atomically: true, encoding: .utf8)
        var job = SubtitlePipelineJob(id: "file", mediaPath: "/tmp/input.mp4", fontSize: 16)
        job.state = .interrupted; job.step = .render; job.upstreamID = "lost-render"; job.subtitlePath = subtitle.path
        let batch = SubtitlePipelineBatch(id: "batch", requestKey: "restore", createdAt: Date(), jobs: [job])
        let storage = root.appendingPathComponent("state.json")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
        try JSONSerialization.data(withJSONObject: ["version": 1, "sequence": 1, "heavyJobLimit": 1, "batches": [encoded]]).write(to: storage)
        let flags = Flags()
        var starts = 0
        let manager = try SubtitlePipelineManager(storage: storage, pollInterval: .milliseconds(10)) { _, tool, args in
            if tool == "get_subtitle_status" { return ["state": args["job_id"] as? String == "lost-render" ? "interrupted" : "rendering"] }
            if tool == "burn_subtitles" { starts += 1; return ["job_id": "new-render"] }
            return [:]
        }
        manager.externalBusy = { _ in flags.externalBusy }
        try manager.retry(jobID: "file", step: .render)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(manager.job("file")?.state, .queuedRender)
        flags.externalBusy = false
        try await eventually { starts == 1 && manager.job("file")?.state == .rendering }
        await manager.stop()
    }

    func testMissingSourceCuesFailBeforeTranslation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("input.mp4")
        try Data([0]).write(to: media)
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), pollInterval: .milliseconds(10)) { _, tool, _ in
            if tool == "start_transcription" { return ["id": "trans"] }
            if tool == "get_transcription_status" { return ["state": "completed"] }
            return ["cues": [["id": 1, "timing": "00:00:00,000 --> 00:00:01,000", "text": "Hello"]], "total_cues": 3, "next_offset": 1, "has_more": false]
        }
        let batch = try manager.start(paths: [media.path], requestKey: "missing-cues")
        try await eventually { manager.job(batch.jobs[0].id)?.state == .failed }
        XCTAssertEqual(manager.job(batch.jobs[0].id)?.step, .transcription)
        await manager.stop()
    }

    func testLegacyClaimsUseSameGlobalStageReservations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), automatic: false) { _, _, _ in [:] }
        let transcription = try XCTUnwrap(manager.claimLegacy(.transcription))
        XCTAssertNil(manager.claimLegacy(.transcription))
        let render = try XCTUnwrap(manager.claimLegacy(.render))
        XCTAssertTrue(manager.busy(.render))
        manager.releaseLegacy(transcription)
        manager.releaseLegacy(render)
        let media = root.appendingPathComponent("input.wav")
        try Data([0]).write(to: media)
        _ = try manager.start(paths: [media.path], requestKey: "limit-one", heavyJobLimit: 1)
        let single = try XCTUnwrap(manager.claimLegacy(.transcription))
        XCTAssertNil(manager.claimLegacy(.render))
        manager.releaseLegacy(single)
        XCTAssertNotNil(manager.claimLegacy(.render))
        await manager.stop()
    }

    func testOneTranscriptionFailureDoesNotBlockOtherFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try (1...3).map { index in
            let path = root.appendingPathComponent("\(index).wav")
            try Data([0]).write(to: path); return path.path
        }
        var starts: [String] = []
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), pollInterval: .milliseconds(10)) { _, tool, args in
            if tool == "start_transcription" { let path = args["file_path"] as! String; starts.append(path); return ["id": path] }
            if tool == "get_transcription_status" { return ["state": args["job_id"] as? String == paths[0] ? "failed" : "completed", "error": "first file error"] }
            return ["cues": [["id": 1, "timing": "00:00:00,000 --> 00:00:01,000", "text": "Hello"]], "total_cues": 1, "next_offset": 1, "has_more": false]
        }
        let batch = try manager.start(paths: paths, requestKey: "failure-isolation")
        try await eventually { manager.job(batch.jobs[2].id)?.state == .awaitingTranslation }
        XCTAssertEqual(starts, paths)
        XCTAssertEqual(manager.job(batch.jobs[0].id)?.state, .failed)
        XCTAssertEqual(manager.job(batch.jobs[1].id)?.state, .awaitingTranslation)
        await manager.stop()
    }

    func testRestartResumesQueuedFileAndPreservesTranslationWait() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        var waiting = SubtitlePipelineJob(id: "waiting", mediaPath: "/tmp/first.wav", fontSize: 16)
        waiting.state = .awaitingTranslation; waiting.step = .translation; waiting.transcriptionID = "original-transcription"
        waiting.cues = [SubtitlePipelineCue(id: 1, timing: "00:00:00,000 --> 00:00:01,000", text: "Hello")]
        let queued = SubtitlePipelineJob(id: "queued", mediaPath: "/tmp/second.wav", fontSize: 16)
        let batch = SubtitlePipelineBatch(id: "batch", requestKey: "restart", createdAt: Date(), jobs: [waiting, queued])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
        try JSONSerialization.data(withJSONObject: ["version": 1, "sequence": 1, "heavyJobLimit": 2, "batches": [encoded]]).write(to: storage)
        var starts: [String] = []
        let manager = try SubtitlePipelineManager(storage: storage, pollInterval: .milliseconds(10)) { _, tool, args in
            if tool == "start_transcription" { starts.append(args["file_path"] as! String); return ["id": "resumed"] }
            return ["state": "transcribing"]
        }
        try await eventually { manager.job("queued")?.state == .transcribing }
        XCTAssertEqual(starts, ["/tmp/second.wav"])
        XCTAssertEqual(manager.job("waiting")?.state, .awaitingTranslation)
        XCTAssertEqual(manager.job("waiting")?.transcriptionID, "original-transcription")
        XCTAssertEqual(try manager.pendingCues(jobID: "waiting").first?.text, "Hello")
        await manager.stop()
    }
}
