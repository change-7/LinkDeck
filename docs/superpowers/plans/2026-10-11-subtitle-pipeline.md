# Subtitle Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user selects delegated execution. Steps use checkbox syntax for tracking.

**Goal:** Process multiple media files through transcription, explicit ChatGPT Korean translation and subtitle rendering with durable shared scheduling.

**Architecture:** A process-wide main-actor manager owns persisted file jobs and stage reservations. Existing app MCP clients perform transcription, subtitle export and rendering; a pipeline MCP bridge validates requests and exposes the manager. App connections outlive tunnel reconnects, while interrupted remote attempts require reconciliation before retry.

**Tech Stack:** Swift 6, Foundation, existing MCP stdio clients, XCTest; existing Stable Whisper and Video Simple Toolkit engines.

**Spec:** docs/subtitle-pipeline-design.md

## Global Constraints

- One transcription and one render at a time, with configurable heavy-job limit of one or two.
- Translation remains explicit ChatGPT work; cue pages and submissions contain at most 100 entries.
- Font size 10–36, default 16, matching Video Simple Toolkit.
- Preserve source media, subtitles and unrelated local edits; add no engine or translation dependency.
- All conversations share the manager. Existing single-file APIs remain available.
- Durable mutations precede acknowledgements; uncertain upstream starts are not automatically repeated.

## Review Focus

- Tunnel reconnect during rendering must retain the upstream connection and job mapping.
- A cancellation racing with a completion must not enqueue the next step.
- Conflicting duplicate translation submissions must leave the accepted draft intact.
- Lost start replies and corrupt persistence must not create duplicate heavy jobs.
- App registration/approval changes must not route a job to a different executable silently.

### Task 1: Durable manager and independent scheduling

**Files:** Create Native/Services/SubtitlePipelineManager.swift and Tests/ChatGPTMicroLaunchpadTests/SubtitlePipelineTests.swift.

**Interfaces:** Produce main-actor `SubtitlePipelineManager`, Codable batch/file/step records, an injectable `SubtitlePipelineTransport` for upstream calls, and methods `start`, `status`, `list`, `cancel`, `retry`, `pendingCues`, `submit`. Transport consumes approved app identities and returns typed upstream job/status/cue/export results. The manager receives a storage URL and heavy-job limit for deterministic tests.

- [ ] Write tests for three-file FIFO, independent transcription/render reservations, translation waiting, limit one, failure isolation and shared callers; run `swift test --filter SubtitlePipelineTests` and observe missing implementation failure.
- [ ] Implement durable state and per-attempt identities, reserving a stage before any suspension. Restore queued and waiting work in original order; reconcile running records or mark interrupted.
- [ ] Add tests for cancel/completion races, stale callbacks, lost start replies, atomic-write failures, corrupt records and restart with translation drafts; prove no duplicate dispatch and no acknowledgement of unpersisted mutations.
- [ ] Run `swift test --filter SubtitlePipelineTests`; require all tests pass before proceeding.

### Task 2: Translation validation and existing SRT export

**Files:** Modify SubtitlePipelineManager.swift and SubtitlePipelineTests.swift.

**Interfaces:** Consume Task 1 job records and transport. `pendingCues` returns original IDs/timing with a stable pagination cursor. `submit` accepts cue IDs/text for exactly one file job and returns accepted/total counts plus stage state.

- [ ] Test 101+ cues over pages of at most 100, partial submissions, identical duplicates, conflicting duplicates, unknown IDs, empty/malformed text and persistence failure before acknowledgement.
- [ ] Implement full-submission validation before mutation. Preserve timing; keep drafts durable. Reuse `save_translated_subtitle` with target language `ko` and validate all expected cues plus actual exported SRT before render enqueue.
- [ ] Test SRT export failure/retry, incomplete subtitles, late submissions after cancellation and identical resubmission after completion. No test may infer completion solely from a returned start ID.
- [ ] Run `swift test --filter SubtitlePipelineTests`; require all tests pass.

### Task 3: Shared app transport and legacy admission control

**Files:** Create Native/Services/SubtitlePipelineAppTransport.swift. Modify Native/Services/AppAPIManifest.swift, StableWhisperMCPClient.swift and ChatGPTTunnelController.swift. Add Tests/ChatGPTMicroLaunchpadTests/SubtitlePipelineTransportTests.swift and extend AppAPIIdleTests.swift fixtures.

**Interfaces:** Implement Task 1 transport via existing clients and approved registrations. AppAPIMCPBridge exposes internal typed tool invocation and shares clients with the pipeline. Legacy whisper and registered-app starts use the same reservations. Pipeline ownership is outside `ChatGPTTunnelController.run`.

- [ ] Test a render surviving idle timeout and tunnel disconnect; include `burn_subtitles` in existing client job tracking using `get_subtitle_status`.
- [ ] Test both legacy whisper routes and pipeline jobs sharing admission control; reject or defer conflicting starts without changing existing response formats.
- [ ] Test registration removal, executable/approval changes, upstream disconnect, remote cancellation acknowledgement and Toolkit's 32-job connection limit. Rotate only settled connections.
- [ ] Inspect upstream cross-process startup behavior. If existing APIs cannot enforce exclusion, add the smallest app-side process lock and tests in isolated companion checkouts; do not silently claim global control over uncovered GUI work.
- [ ] Run `swift test --filter 'SubtitlePipeline|AppAPIIdle|AppAPIManifest|LinkDeckMCP'`; require passing regression and transport tests.

### Task 4: Pipeline MCP tools

**Files:** Create Native/Services/SubtitlePipelineMCPBridge.swift and Tests/ChatGPTMicroLaunchpadTests/SubtitlePipelineMCPTests.swift. Modify ChatGPTTunnelController.swift and LinkDeckMCPHandler.swift.

**Interfaces:** Bridge `response(to:fallback:)` appends seven prefixed tool schemas to tools/list and routes tools/call to the single manager. All existing fallback tools remain discoverable.

- [ ] Test schema discovery, strict argument validation, start request idempotency, canonical duplicate paths, invalid font sizes, pagination, batch and individual cancellation, failed-step retry, and shared status from two request contexts.
- [ ] Implement `linkdeck_start_subtitle_batch`, `linkdeck_get_subtitle_batch_status`, `linkdeck_list_subtitle_batches`, `linkdeck_get_pending_translation_cues`, `linkdeck_submit_translated_cues`, `linkdeck_cancel_subtitle_batch`, `linkdeck_retry_subtitle_step`.
- [ ] Document polling and explicit translation in MCP instructions. Expose the persisted global resource setting through batch start configuration with validation; changes apply globally and never interrupt active work.
- [ ] Run `swift test --filter 'SubtitlePipeline|LinkDeckMCP'`; require passing tests and unchanged legacy schemas.

### Task 5: Integration, build and evidence

**Files:** Add docs/subtitle-pipeline-validation.md and an integration fixture using existing test conventions. Companion changes, if needed, are separately identified.

**Interfaces:** Consume the public MCP tools through the same app transport used in production.

- [ ] Run three small fixtures through actual app APIs when installed engines/approved apps are available. Submit explicit Korean fixture text, check original cue timing, readable SRT and final MP4 with ffprobe; include audio black-background output and output-name collision/extension cases.
- [ ] Run LinkDeck `swift test` and `swift build`. Build/test modified companion repositories with their documented commands. Record exact errors and prerequisites if any check cannot run.
- [ ] Review the final diff against every design requirement and regression evidence. Use a fresh reviewer only if selected/authorized; correct actionable findings and rerun affected tests.
- [ ] Record the eight requested scenarios with test names and separate simulated coverage from actual app/media integration. Report remaining limitations, without deploying or replacing installed apps automatically.

## Execution result (2026-10-11)

The implementation and validation are complete. The checklist above is the original planning record; the observed evidence and verification limits are recorded in `../../subtitle-pipeline-validation.md`. Runtime ownership was consolidated in `SubtitlePipelineRuntime` rather than adding separate adapter classes. Video Simple Toolkit needed a minimal cross-process lock and shutdown cleanup; Stable Whisper source needed no changes. Final LinkDeck validation passed 245 tests (one opt-in integration skipped in the whole suite), with the actual three-file integration passing separately. Stable Whisper passed 49 tests, Toolkit passed 19 tests, and both builds succeeded. The final LinkDeck Release build completed in 44.82 seconds. Fresh review approved the implementation after two regression fixes; see `.omo/evidence/subtitle-pipeline-code-review.md` from the repository root. Installed app bundles were not replaced.
