import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class SubtitlePipelineIntegrationTests: XCTestCase {
    func testRealAppsThreeAudioFilesProduceKoreanSRTAndMP4() async throws {
        guard ProcessInfo.processInfo.environment["LINKDECK_PIPELINE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set LINKDECK_PIPELINE_INTEGRATION=1 to run installed app engines")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("linkdeck-integration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let media = root.appendingPathComponent("speech.aiff")
        try run("/usr/bin/say", ["-v", "Samantha", "-o", media.path, "Hello. This is a short subtitle pipeline test."])
        let paths = try (1...3).map { number in
            let file = root.appendingPathComponent("speech-\(number).wav")
            try run("/opt/homebrew/bin/ffmpeg", ["-v", "error", "-i", media.path, "-ar", "16000", "-ac", "1", file.path])
            return file.path
        }
        let whisper = StableWhisperMCPClient(jobsDirectory: root.appendingPathComponent("whisper-jobs"))
        let renderer = StableWhisperMCPClient()
        let toolkitApp = ProcessInfo.processInfo.environment["LINKDECK_TOOLKIT_APP"] ?? "/Applications/Video Simple Toolkit.app"
        let toolkitExecutable = try XCTUnwrap(Bundle(path: toolkitApp)?.executableURL)
        let whisperExecutable = try XCTUnwrap(Bundle(path: "/Applications/StableWhisper.app")?.executableURL)
        let manager = try SubtitlePipelineManager(storage: root.appendingPathComponent("state.json"), pollInterval: .milliseconds(100)) { step, tool, original in
            var args = original
            args.removeValue(forKey: "_pipeline_bindings")
            let client = step == .render ? renderer : whisper
            let executable = step == .render ? toolkitExecutable : whisperExecutable
            let arguments = step == .render ? ["--mcp", "-settings.ffmpeg.path", "/opt/homebrew/bin/ffmpeg", "-settings.output.directory", output.path] : ["--mcp"]
            let data = try await client.request(JSONSerialization.data(withJSONObject: ["method": "tools/call", "params": ["name": tool, "arguments": args]]), executable: executable, arguments: arguments)
            let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try XCTUnwrap(reply["result"] as? [String: Any])
            let content = try XCTUnwrap(result["content"] as? [[String: Any]])
            let text = try XCTUnwrap(content.first?["text"] as? String)
            guard result["isError"] as? Bool != true else { throw SubtitlePipelineFailure(text) }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        do {
            let batch = try manager.start(paths: paths, fontSize: 20, requestKey: "integration")
            let deadline = Date().addingTimeInterval(240)
            while Date() < deadline {
                for job in manager.batches[0].jobs {
                    if job.state == .awaitingTranslation {
                        let page = try manager.pendingCues(jobID: job.id)
                        try manager.submit(jobID: job.id, translations: Dictionary(uniqueKeysWithValues: page.map { (String($0.id), "안녕하세요. 자막 파이프라인 테스트입니다.") }))
                    }
                    if [.failed, .interrupted].contains(job.state) { throw SubtitlePipelineFailure(job.error ?? "Integration job failed") }
                }
                if manager.batches[0].jobs.allSatisfy({ $0.state == .completed }) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let finished = manager.batches.first { $0.id == batch.id }!
            XCTAssertTrue(finished.jobs.allSatisfy { $0.state == .completed }, String(describing: finished.jobs))
            XCTAssertEqual(Set(finished.jobs.compactMap(\.outputPath)).count, 3)
            for job in finished.jobs {
                let srt = try String(contentsOfFile: XCTUnwrap(job.subtitlePath), encoding: .utf8)
                XCTAssertTrue(srt.contains("안녕하세요"))
                XCTAssertTrue(srt.contains(job.cues[0].timing))
                let video = try XCTUnwrap(job.outputPath)
                XCTAssertFalse(video.hasSuffix(".mp4.mp4"))
                try run("/opt/homebrew/bin/ffprobe", ["-v", "error", "-show_entries", "stream=codec_type", "-of", "json", video])
                XCTAssertTrue(FileManager.default.fileExists(atPath: job.mediaPath))
            }
            print("PIPELINE_INTEGRATION_OUTPUT: " + root.path)
            await manager.stop()
            await whisper.stop()
            await renderer.stop()
        } catch {
            await manager.stop()
            await whisper.stop()
            await renderer.stop()
            throw error
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SubtitlePipelineFailure("Fixture tool failed: " + errorText) }
    }
}
