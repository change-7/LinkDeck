# Navigation motion verification — 2026-10-11

## Final revision: horizontal slide restored

User requested the previous motion for left/right swipes. Landscape main navigation restores the 24dp directional slide at 150ms with 100ms fade; portrait button-page changes restore 260ms slide with 180ms fade. Both use the earlier cubic-bezier easing. Landscape vertical page changes and folder entry/return retain the 180ms fade. The original page-wrap direction helper and its regression coverage were restored.

Build and all 64 unit tests passed. APK installed on Galaxy R5CN30Z4RNX. Fresh landscape UI trees confirmed Buttons → Codex → Buttons with left/right swipes. Portrait visual checks, folder checks, and full lint were not repeated for this revision. The videos below document earlier revisions.

## Earlier revision: short fade only

User clarification replaces the earlier slide/scale design below. Final navigation uses simultaneous linear fade-in and fade-out: 100ms for main pages, 180ms for button pages and folders, with no delay, slide, or zoom. The two tests added for the removed direction/scale decision helper were removed along with that helper; existing navigation and content-key tests remain.

Final build and all 63 remaining unit tests passed. Updated APK installed on Galaxy R5CN30Z4RNX. UI trees confirmed Buttons → Codex → Buttons. Intermediate frames inspected at 30fps show changing opacity with stationary content and a fixed header. Final video: `navigation-fade-2026-10-11.mp4`. Full lint, portrait matrix, and folder tests on hardware were not repeated for this final revision; the existing unrelated lint errors recorded below remain.

## Earlier revisions (historical)

Reference mechanisms: [page side-by-side](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-dev/08-page-side-by-side.md) and [modal](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-dev/06-modal.md), adapted to native Compose using the motion tokens in `Android/DESIGN.md`.

Timing correction after user feedback: restore original main-page 150ms slide/100ms fade and button-page/folder 260ms movement/180ms fade in both directions. The video below records the earlier 250ms/150ms timing revision, not the corrected build. The short translation and easing remain unchanged.

Corrected build: `:app:testDebugUnitTest :app:assembleDebug` passed again (65 tests, zero failures/errors). Installed on the same Galaxy and launched successfully. Full lint and the complete navigation/folder/device-matrix checks were not repeated for the timing-only correction.

## Observed on Galaxy R5CN30Z4RNX

- Updated debug APK installed with `adb install -r`; existing app data retained.
- Landscape Buttons → Codex and Codex → Buttons: directional translation and crossfade; the shared header remains fixed. Intermediate video frames inspected at 30fps. Evidence: `navigation-motion-2026-10-11.mp4` beside this report.
- Landscape button pages: selector taps and upward swipes advance through the configured pages; the last page wraps to the first. UI dumps confirmed distinct page contents.
- Portrait button pages: left swipe opens the next button page; right swipe returns. UI dumps confirmed both destinations at rotation 0; settled screenshot inspected.
- Android animator duration scale 0: navigation still reaches the selected page; Compose supplies the system animation policy. No crash-buffer entries appeared during these checks.
- Test rotation controls and animator duration scale were restored to their original values: fixed rotation `default`, accelerometer rotation `1`, user rotation `0`, animator duration scale unset.

## Build and checks

- `:app:testDebugUnitTest :app:assembleDebug`: passed; 65 tests, 0 failures/errors/skips.
- Added coverage for forward/backward page motion, page wrapping, folder entry/return, folder replacement, unchanged content, and page-change priority over folder motion.
- `git diff --check`: passed.
- `:app:lintDebug`: failed with 2 existing errors in unchanged files: `MissingPermission` at `RemoteBridgeClient.kt:673` and `RemoteViewLayout` at `UsageWidgetProvider.kt:57`; 14 warnings. These are outside the navigation motion change.

## Verification limits

The currently configured phone pages contain no folder shortcut, so folder motion was compiled and its transition selection unit-tested, but was not exercised on the physical phone. Other skins and multiple device sizes were not exhaustively checked. This change only animates existing content and does not alter layout, command dispatch, or navigation destinations.
