# Subtitle pipeline implementation and verification

Verified on 2026-10-11, Asia/Seoul. Source changes remain local; no push or installed-app replacement was performed.

## Implemented behavior

LinkDeck owns one durable process-wide queue. Each file has its own ID, upstream transcription/render IDs, state, error, progress, accepted translations and output paths. Independent FIFO transcription/render slots permit one job per stage. `heavy_job_limit: 1` serializes heavy work; `2` permits one transcription and one render. Existing single-file Whisper and registered Toolkit starts claim the same reservations before any asynchronous operation. A failed file does not stop other files.

ChatGPT explicitly supplies Korean text. Source pages contain at most 100 original cues with IDs/timing; submissions accept at most 100 entries atomically. Identical duplicates are idempotent, conflicting duplicates are rejected. Source pagination verifies total count and offsets; every cue must be translated before Whisper exports SRT. LinkDeck verifies exported text/timing before queuing the Toolkit renderer. Status/list responses contain counts and paths, not the entire transcript.

Records are atomically saved at `~/Library/Application Support/LinkDeck/subtitle-pipeline/state.json`. Queued jobs and translation waits survive restart. In-flight steps become `interrupted` and require explicit retry. Saved remote IDs are reconciled before replacement work; lost terminal jobs can be cancelled locally. Toolkit's in-memory job history cannot survive process restart, so an interrupted encode is never silently declared complete or automatically repeated. Pending work resumes when LinkDeck discovers the registered apps on a subsequent MCP request.

The original media and subtitles remain intact. Output names use the input stem plus file job ID; the existing Toolkit renderer adds MP4 and renames collisions. Font size uses the existing 10–36 UI scale, default 16. Audio uses the existing black-background rendering feature.

## Changed code

- `Native/Services/SubtitlePipelineManager.swift`: durable state, stage reservations, translation validation, completion/retry/cancellation and recovery.
- `Native/Services/SubtitlePipelineMCPBridge.swift`: seven tools and bounded status/translation responses.
- `Native/Services/SubtitlePipelineRuntime.swift`: shared app connections and adapter to existing API implementations.
- `AppAPIManifest.swift`, `StableWhisperMCPClient.swift`, `ChatGPTTunnelController.swift`, `LinkDeckMCPHandler.swift`: shared clients, legacy admission, render idle tracking, settled connection rotation at Toolkit's 32-job limit, and MCP guidance.
- Companion repository `/Users/pdg/Documents/유튜브 다운로더/Managers/LinkDeckMCPServer.swift`: one global MCP job lock and graceful SIGTERM/SIGINT cleanup. The previous API allowed two processes to encode simultaneously; the regression test reproduced this before the fix. This file was updated only after matching the captured starting file, preserving its pre-existing edits.
- Stable Whisper source was reused without modification. Its existing job-directory lock already excludes competing clients using LinkDeck's shared job directory.

## Public MCP use

Discover tools after starting the updated LinkDeck build. Video Simple Toolkit must be registered as a button and its app API approved through LinkDeck's existing approval flow.

Start with `linkdeck_start_subtitle_batch`:

```json
{
  "file_paths": ["/absolute/file-one.wav", "/absolute/file-two.mp4"],
  "request_key": "unique-request-for-this-batch",
  "font_size": 20,
  "heavy_job_limit": 1
}
```

Keep the returned batch ID and each file ID. Poll `linkdeck_get_subtitle_batch_status`. For `awaiting_translation`, call `linkdeck_get_pending_translation_cues` with file `job_id`, `offset` and `limit`. Follow `next_offset` until `has_more` is false, including empty already-translated pages. Submit Korean text with `linkdeck_submit_translated_cues`, for example `{"job_id":"returned-file-id","translations":{"1":"한국어 번역"}}`. Original timing is never submitted or replaced by the client.

The remaining tools are `linkdeck_list_subtitle_batches`, `linkdeck_cancel_subtitle_batch` (optional file `job_id`) and `linkdeck_retry_subtitle_step` (`step`: `transcription`, `translation`, or `render`). Reusing a request key with the same inputs returns the existing batch. Conflicting inputs or active duplicate canonical paths are rejected. The heavy-job setting is global and applies to future dispatch; reducing it does not kill running jobs.

## Requested scenarios and evidence

| Scenario | Verified surface |
| --- | --- |
| Three files register and transcribe sequentially | `testThreeFilesPipelineOverlapAndDurableTranslations`; real three-file integration |
| File 2 transcribes while file 1 waits for translation | Scheduler test observes first awaiting translation and second started |
| File 2 translates while file 1 renders | Scheduler test observes first rendering and second awaiting translation |
| No two jobs occupy one stage | Stage reservations, legacy-claim regression and actual two-process Toolkit exclusion test |
| Two conversations share one queue | Two MCP bridge request contexts read/reuse the same manager/batch |
| Error/cancellation isolation | `testOneTranscriptionFailureDoesNotBlockOtherFiles`; individual cancellation in the three-file test; actual renderer cancel/error smoke |
| Safe restart | Waiting/queued restoration; interrupted rendering record; lost-job cancellation and replacement-admission regression tests |
| Correct Korean SRT and final MP4 | Actual installed Whisper engine plus updated Toolkit API; SRT text/timing comparison, ffprobe validation, extracted frame visually inspected |

LinkDeck whole suite: **245 tests, 1 opt-in integration test skipped, 0 failures**. The actual-engine integration was run explicitly and passed separately. Stable Whisper whole suite: **49 tests, 0 failures**. Toolkit XCTest: **19 tests passed**. LinkDeck Release build and Toolkit Debug build succeeded.

Commands/logs:

- `swift test`: `/tmp/linkdeck-full-tests-final.log`.
- `swift build -c release`: `/tmp/linkdeck-release-build-final.log`.
- `LINKDECK_PIPELINE_INTEGRATION=1 LINKDECK_TOOLKIT_APP=/tmp/linkdeck-video-build/Build/Products/Debug/VideoSimpleToolkit.app swift test --filter SubtitlePipelineIntegrationTests`: `/tmp/linkdeck-pipeline-integration-final.log`.
- `swift test --package-path '/Users/pdg/Documents/스테이블 위스퍼'`: `/tmp/linkdeck-whisper-tests-standard.log`.
- Toolkit `xcodebuild build/test` using `/tmp/linkdeck-video-pipeline` and `/tmp/linkdeck-video-build`: `/tmp/linkdeck-toolkit-build.log`, `/tmp/linkdeck-toolkit-tests.log`.
- `python3 script/check_subtitle_pipeline_lock.py /tmp/linkdeck-video-build/Build/Products/Debug/VideoSimpleToolkit.app`: `/tmp/linkdeck-toolkit-lock-green.log`.
- Existing Toolkit subtitle/download smoke tests: `/tmp/linkdeck-toolkit-subtitles.log`, `/tmp/linkdeck-toolkit-downloads.log`.

The real-engine fixture generated three distinct WAV paths with system speech and submitted an explicit Korean fixture translation. It completed in 14.642 seconds on the final integration run; this is a smoke-test duration, not a performance benchmark. Three source-preserving MP4 results and SRTs were produced. One frame showed readable Korean text on the expected black background. Font-size smoke tests measured more bright subtitle pixels at size 36 than size 10 (3766 vs 285); collisions, invalid subtitles, cancellation and cleanup also passed.

An isolated Stable Whisper scratch build initially failed its executable handshake test because that existing test directly uses the repository's `.build/debug/StableWhisper`. Re-running with the repository's normal build path passed all 49 tests. Existing Stable Whisper weak-capture compiler warnings were observed; no Whisper source was changed or warnings suppressed.

## Remaining verification limits

Real ChatGPT conversations through the external tunnel were not exercised; shared-session behavior was tested through local MCP request contexts. The fixture supplied explicit Korean text rather than claiming autonomous background ChatGPT translation. Whole LinkDeck process termination/relaunch was represented by persisted-record restoration and client-lifetime tests; actual Toolkit disconnect/SIGTERM cleanup was exercised. Long recordings, sustained peak memory/temperature on an 8GB M1 and manually launched GUI engine jobs were not benchmarked. API locks cover MCP jobs; independent GUI work does not participate in LinkDeck scheduling.

The installed `/Applications` apps and pre-existing workspace `LinkDeck.app` were not replaced. Run/repackage the updated LinkDeck and Toolkit builds to expose the new tools and companion process lock. Existing app API approval remains required; a changed manifest or app location uses the existing reapproval mechanism.
