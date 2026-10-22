# LinkDeck subtitle pipeline design

## Goal and existing integration

Implement the requested multi-file pipeline in change-7/LinkDeck. LinkDeck owns scheduling and durable records; Stable Whisper owns transcription and subtitle export; Video Simple Toolkit owns rendering, including audio-to-black-background MP4. ChatGPT supplies Korean translations explicitly. No new engine or translation service.

The local origin is https://github.com/change-7/LinkDeck.git. Existing integrations are Native/Services/StableWhisperMCPClient.swift, AppAPIManifest.swift and ChatGPTTunnelController.swift. WhisperMCPJobs.swift in the Stable Whisper repository already queues transcription and saves paginated translations. Video Simple Toolkit's Managers/LinkDeckMCPServer.swift supplies burn_subtitles, get_subtitle_status and cancel_subtitle_render. Its jobs are currently scoped to a stdio connection, limited to one active job and 32 lifetime jobs, and cancelled on disconnect. Neither app's per-process limit establishes a global limit across separate API processes.

## Ownership and scheduling

Add a process-wide SubtitlePipelineManager with serialized state transitions and an injectable app transport. The manager outlives individual MCP requests and tunnel reconnections. All ChatGPT conversations use this same manager. Persist batches, file job IDs, submission order, step state, remote job IDs, progress, errors, source cue metadata, accepted translations and output paths atomically before acknowledging mutations.

Use independent FIFO transcription and rendering queues. Translation is an external waiting state, not a background worker. Reserve a stage slot before awaiting any API call. Release it only after remote terminal status, acknowledged cancellation or confirmed remote termination. Default limits are one transcription and one render, with a global heavy-job limit of two; a persisted setting of one serializes both stages on constrained hardware. Translation submissions never consume heavy-job slots.

Keep existing single-file APIs. Route pipeline and legacy calls through shared app clients and admission control so they cannot bypass LinkDeck's stage limits. Inspect app process lifetime and locking before deciding whether minimal app-side cross-process exclusion is needed. Do not claim control over independent GUI work unless exclusion actually covers it.

## Public tools and input validation

Expose start_subtitle_batch, get_subtitle_batch_status, list_subtitle_batches, get_pending_translation_cues, submit_translated_cues, cancel_subtitle_batch and retry_subtitle_step using the LinkDeck naming prefix. Start accepts readable absolute media paths, optional font_size (10–36, default 16), and a caller request key for idempotent retries. Validate every file before registration. Reject duplicate canonical paths in one request and attach or report existing active jobs rather than starting duplicate work. Batch status includes per-file IDs, stage progress, errors, upstream IDs and result paths. Cancellation accepts a batch ID and optional file job ID.

Return at most 100 untranslated cues per page with stable cue IDs and original timing. Submit 1–100 cue translations for one file job. Validate all entries before changing state; identical resubmissions are idempotent, conflicting resubmissions fail without overwriting. Never accept client-supplied timing. Keep durable accepted cue text in LinkDeck and reuse Whisper's save_translated_subtitle API for SRT export. Verify all expected cues and the exported readable SRT before enqueueing rendering. Treat cue text as untrusted content. A disconnected ChatGPT leaves awaiting_translation intact indefinitely.

## Results, errors and recovery

Use an input stem plus file job ID for output_name, stripping the media extension before the renderer adds .mp4. Preserve source media and subtitles. Record only the renderer's actual terminal output path; verify it exists before declaring completion. App errors affect only their file job.

Persist cancellation intent before invoking upstream cancellation. Do not let late completion callbacks advance cancelled jobs. Retry only failed/interrupted stages, preserving successful prior stages and translations. Use a per-attempt identity to reject stale callbacks.

On restart, restore FIFO pending work and translation drafts. Reconcile saved remote IDs where the app API supports it. A lost Video Simple Toolkit connection cannot recover in-memory rendering IDs: mark that attempt interrupted, retain its inputs and require explicit retry rather than silently creating a second encode. An uncertain start response likewise requires reconciliation or an interrupted state, not automatic duplicate execution. Keep active client connections alive during polling; safely rotate Toolkit connections only when settled to handle its 32-job limit. Handle persistence failures explicitly and stop new dispatch rather than acknowledging unrecorded work.

## Validation and limits of evidence

Use a fake app transport and deterministic scheduling tests for three-file FIFO, overlapping independent stages, shared conversations, admission limits, duplicate registration, cancellation isolation, stale callbacks, failure/retry, restart, persistence errors, paginated cue submission and conflicting duplicates. Verify MCP schemas and existing single-file regression tests. Build LinkDeck and any modified app repositories.

Use available local engines and ffmpeg for an integration fixture through the actual app APIs, including audio background rendering, SRT timing/content and MP4 probing. If a runtime, approved connection or engine model is unavailable, report that exact missing prerequisite and distinguish integration coverage from simulated scheduler coverage. No real-media end-to-end result is implied by a mock test or successful build.

## Scope

No broad refactoring, new paid API, new translation model, automatic background ChatGPT work, new encoding engine or source-file deletion. Existing unrelated local edits are preserved. Any required companion-app edits remain small and are reported separately.
