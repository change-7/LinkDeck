import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class SubtitlePipelineMCPTests: XCTestCase {
    func testTwoSessionsShareBatchAndValidateArguments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("video.mp4")
        try Data([0]).write(to: media)
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), automatic: false) { _, _, _ in [:] }
        let session1 = SubtitlePipelineMCPBridge(manager: manager)
        let session2 = SubtitlePipelineMCPBridge(manager: manager)
        func invoke(_ bridge: SubtitlePipelineMCPBridge, _ name: String, _ args: [String: Any], method: String = "tools/call") async throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": "client", "method": method, "params": ["name": name, "arguments": args]])
            let response = await bridge.response(to: data) {
                (200, try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": "client", "result": ["tools": [["name": "existing_tool"]]]]))
            }
            let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            XCTAssertEqual(reply["id"] as? String, "client")
            return try XCTUnwrap(reply["result"] as? [String: Any])
        }
        func payload(_ result: [String: Any]) throws -> [String: Any] {
            let content = try XCTUnwrap(result["content"] as? [[String: Any]])
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data((content[0]["text"] as! String).utf8)) as? [String: Any])
        }
        let listed = try await invoke(session1, "", [:], method: "tools/list")
        let tools = try XCTUnwrap(listed["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 9)
        XCTAssertTrue(tools.contains { $0["name"] as? String == "existing_tool" })
        let start = try await invoke(session1, "linkdeck_start_subtitle_batch", ["file_paths": [media.path], "request_key": "one", "font_size": 20, "heavy_job_limit": 1])
        XCTAssertEqual(start["isError"] as? Bool, false)
        let batch = try payload(start)
        let id = try XCTUnwrap(batch["id"] as? String)
        let status = try payload(await invoke(session2, "linkdeck_get_subtitle_batch_status", ["batch_id": id]))
        XCTAssertEqual(status["id"] as? String, id)
        XCTAssertEqual(status["heavy_job_limit"] as? Int, 1)
        let duplicate = try payload(await invoke(session2, "linkdeck_start_subtitle_batch", ["file_paths": [media.path], "request_key": "one", "font_size": 20]))
        XCTAssertEqual(duplicate["id"] as? String, id)
        for invalid: [String: Any] in [
            ["file_paths": [media.path], "request_key": "two", "font_size": true],
            ["file_paths": [media.path], "request_key": "two", "font_size": 37],
            ["file_paths": [media.path], "request_key": "two", "extra": "injected"],
            ["file_paths": [media.path], "request_key": "two", "heavy_job_limit": 1.5],
            ["file_paths": [media.path], "request_key": "two"]
        ] {
            let result = try await invoke(session2, "linkdeck_start_subtitle_batch", invalid)
            XCTAssertEqual(result["isError"] as? Bool, true)
        }
        let cancelled = try await invoke(session2, "linkdeck_cancel_subtitle_batch", ["batch_id": id])
        XCTAssertEqual(cancelled["isError"] as? Bool, false)
        XCTAssertEqual(manager.batches[0].jobs[0].state, .cancelled)
        await manager.stop()
    }

    func testStatusDoesNotReturnFullSubtitleText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        var job = SubtitlePipelineJob(id: "file", mediaPath: "/tmp/media.mp4", fontSize: 16)
        job.state = .awaitingTranslation; job.step = .translation
        job.cues = [SubtitlePipelineCue(id: 1, timing: "00:00:00,000 --> 00:00:01,000", text: "full source transcript")]
        job.translations = ["1": "전체 번역문"]
        let batch = SubtitlePipelineBatch(id: "batch", requestKey: "status", createdAt: Date(), jobs: [job])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
        try JSONSerialization.data(withJSONObject: ["version": 1, "sequence": 1, "heavyJobLimit": 2, "batches": [object]]).write(to: storage)
        let manager = try SubtitlePipelineManager(storage: storage, automatic: false) { _, _, _ in [:] }
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "linkdeck_get_subtitle_batch_status", "arguments": ["batch_id": "batch"]]])
        let response = await SubtitlePipelineMCPBridge(manager: manager).response(to: data) { (500, Data()) }
        let text = String(decoding: response.body, as: UTF8.self)
        XCTAssertFalse(text.contains("full source transcript"))
        XCTAssertFalse(text.contains("전체 번역문"))
        XCTAssertTrue(text.contains("total_cues"))
        await manager.stop()
    }
    func testShareStackAsyncPublicationRetainsUUIDOnRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let subtitle = root.appendingPathComponent("translated.srt")
        let video = root.appendingPathComponent("rendered.mp4")
        try Data("subtitle".utf8).write(to: subtitle)
        try Data("video".utf8).write(to: video)
        let results = root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
        var file = SubtitlePipelineJob(id: UUID().uuidString, mediaPath: "/unused.aac", fontSize: 23)
        file.state = .failed; file.step = .publish
        file.subtitlePath = subtitle.path; file.outputPath = video.path
        file.shareStackSource = SubtitlePipelineShareStackSource(fileID: UUID().uuidString, leaseID: UUID().uuidString, sha256: String(repeating: "a", count: 64), resultDirectory: results.path, originalName: "Original AAC.aac")
        let batch = SubtitlePipelineBatch(id: UUID().uuidString, requestKey: "async", createdAt: Date(), jobs: [file])
        let storage = root.appendingPathComponent("state.json")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
        try JSONSerialization.data(withJSONObject: ["version": 1, "heavyJobLimit": 2, "sequence": 1, "batches": [encoded]]).write(to: storage)
        var keys: [String] = []
        let remoteID = UUID().uuidString
        let manager = try SubtitlePipelineManager(storage: storage, pollInterval: .milliseconds(10)) { step, tool, args in
            XCTAssertEqual(step, .publish)
            if tool == "register_processed_media" {
                XCTAssertNil(args["result_path"])
                XCTAssertNotNil(UUID(uuidString: args["requestKey"] as! String))
                XCTAssertTrue(FileManager.default.fileExists(atPath: results.appendingPathComponent(args["filename"] as! String).path))
                if args["mimeType"] as? String == "video/mp4" {
                    keys.append(args["requestKey"] as! String)
                    if keys.count == 1 { throw SubtitlePipelineFailure("retry publication") }
                }
                return ["id": remoteID, "status": "queued"]
            }
            XCTAssertEqual(tool, "get_job")
            return ["id": remoteID, "status": "succeeded", "processedMedia": ["id": UUID().uuidString]]
        }
        try manager.retry(jobID: file.id, step: .publish)
        for _ in 0..<200 {
            if manager.job(file.id)?.state == .failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(manager.job(file.id)?.state, .failed)
        XCTAssertNotNil(manager.job(file.id)?.shareStackSource?.subtitleFileID)
        try manager.retry(jobID: file.id, step: .publish)
        for _ in 0..<200 {
            if manager.job(file.id)?.state == .completed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(manager.job(file.id)?.state, .completed)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys.first, keys.last)
        XCTAssertTrue(FileManager.default.fileExists(atPath: results.appendingPathComponent("Original AAC.mp4").path))
        await manager.stop()
    }

    func testShareStackPreparationPollsUntilLeaseIsReady() async throws {
        let id = UUID().uuidString
        var polls = 0
        let ready = try await SubtitleShareStackJob.wait(["id": id, "status": "queued"]) { jobID in
            XCTAssertEqual(jobID, id)
            polls += 1
            return ["id": id, "status": "succeeded", "mediaLease": ["sourcePath": "/private/source.aac", "resultDirectory": "/private/results"]]
        }
        XCTAssertEqual(polls, 1)
        XCTAssertNotNil(ready["mediaLease"])
        do {
            _ = try await SubtitleShareStackJob.wait(["id": id, "status": "failed"]) { _ in XCTFail("Must not poll a failed job"); return [:] }
            XCTFail("Must reject failed preparation")
        } catch {}
    }

}
