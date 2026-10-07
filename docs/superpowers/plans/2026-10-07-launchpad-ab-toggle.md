# Launchpad A/B Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persisted A/B action toggles to Mac pads, smartphone buttons, and folder shortcuts, and remove Clipboard Text from all action settings.

**Architecture:** Store optional B actions and the active state beside each existing A action. Execute the newly active action after persisting the state; the Mac bridge remains the authority for phone presses and republishes the updated smartphone page. Render A/B state in Mac and Android button surfaces and use the pad's configured idle/pressed colors for hardware state.

**Tech Stack:** Swift, SwiftUI, CoreMIDI, Kotlin, Jetpack Compose, UserDefaults, JSON bridge.

**Spec:** `docs/superpowers/specs/2026-10-07-toggle-actions-design.md`

## Global Constraints

- Existing configurations treat their current action as A and start in state A.
- Buttons without B keep their current single-action behavior.
- Smartphone long-press actions remain independent from the A/B short-press toggle.
- Persist smartphone state in shared smartphone-page configuration; persist Mac pad state with the Mac page.
- Preserve the legacy `clipboardText` model case, runner path, and saved values; omit Clipboard Text from every button action selector.
- Disabling A/B or removing B resets the state to A; changing either action does not change the active state.
- Do not create Git commits unless the user asks.

## Review Focus

- Old saved JSON missing toggle fields must decode as a single A action in state A; verify loading and re-saving an existing backup.
- The first and second presses must run B then A, with state saved before execution; exercise a configured pair and an action that reports an error.
- A phone long press must continue to run its own configured action without changing short-press A/B state; exercise a button with both kinds configured.
- A phone short press must persist through reconnect/relaunch and update the displayed badge from the Mac-published state; exercise button and folder shortcut presses.
- Removing B must return to A, while legacy Clipboard Text remains executable and absent from all selectors; inspect the three settings editors and invoke a legacy saved action.

---

### Task 1: Persist A/B Configuration and Resolve Smartphone Presses

**Files:**
- Modify: `Native/Models/LaunchpadModels.swift`
- Modify: `Native/Support/SmartphoneDefaults.swift`
- Modify: `Native/Stores/LaunchpadStore.swift`
- Modify: `Native/App/ChatGPTMicroLaunchpadApp.swift`
- Modify: `Native/Services/CodexAppServerClient.swift`
- Modify: `Native/Views/ContentView.swift`
- Test: `Tests/ChatGPTMicroLaunchpadTests/LaunchpadABToggleTests.swift`

**Interfaces:**
- `Pad`, `SmartphoneButton`, and `SmartphoneFolderShortcut` expose `secondAction: PadAction?` and `isSecondActionActive: Bool`.
- `SmartphoneDefaults.toggleAction(id:in:)` mutates the matching button or folder shortcut state in `inout [SmartphonePage]` and returns the action selected for this press. With no B action it returns A without toggling.
- `CodexAppServerClient` notifies the in-memory `LaunchpadStore` when a remote press changes smartphone pages, so the Mac editor updates alongside the republished phone state.
- Remote short presses persist the mutated pages through `SmartphoneDefaults.persist(_:to:)`; long presses continue through `SmartphoneDefaults.action(id:in:longPress:)`.

- [ ] Add failing tests `testLegacySmartphoneConfigurationDefaultsToA`, `testSmartphonePressAlternatesButtonAndFolderActions`, and `testToggleFieldsSurviveCodableRoundTrip`; run `swift test --filter LaunchpadABToggleTests` and confirm the behavior assertions fail.
- [ ] Add optional B action and default-A state to the three Codable models; decode absent state fields as false so existing stored pages remain compatible, and preserve the fields in configuration-copy helpers.
- [ ] Add an in-place smartphone button/folder shortcut resolver that flips state before returning the newly active action; run `swift test --filter LaunchpadABToggleTests` and confirm it passes.
- [ ] In the remote command handler, use the resolver for short presses, persist the pages before execution, notify the in-memory page store, and call `publishRemoteState()` before executing; keep long-press lookup independent.
- [ ] Build the macOS app and load a pre-toggle saved configuration to confirm missing fields default to A.

### Task 2: Add Mac Pad Editing, Execution, and State Display

**Files:**
- Modify: `Native/Views/InspectorView.swift`
- Modify: `Native/Views/PadButton.swift`
- Modify: `Native/Views/LaunchpadView.swift`
- Modify: `Native/Views/ContentView.swift`
- Modify: `Native/Services/LaunchpadMIDIManager.swift`
- Modify: `Native/Services/VirtualMotionPlayer.swift`
- Test: `Tests/ChatGPTMicroLaunchpadTests/LaunchpadABToggleTests.swift`

**Interfaces:**
- Mac pad action editing selects A or B while preserving the existing action editor controls.
- `LaunchpadStore.actionForNextPress(on:)` persists the toggled pad state before returning the newly selected action; `ContentView.run(_:)` executes that result.
- `PadButton` displays the active A/B state when B is configured; Launchpad MIDI idle color uses `idleColor` for A and `activeColor` for B.

- [ ] Add failing test `testMacPadStatePersistsBeforeFailedAction`; run `swift test --filter LaunchpadABToggleTests` and confirm the new store method is missing.
- [ ] Implement `LaunchpadStore.actionForNextPress(on:)` and use it from `ContentView.run(_:)` so the state saves before execution; refresh LEDs and flash the hardware pad after the state update.
- [ ] Add A/B enable and selection controls to the pad inspector; creating B initializes it with an empty action and disabling it clears B and resets state A.
- [ ] Remove Clipboard Text from the Mac pad action selector while retaining the model and runner compatibility path.
- [ ] Display A or B in virtual Mac pads and derive physical Launchpad and motion-restore LEDs from the active state.
- [ ] Run `swift test --filter LaunchpadABToggleTests`; exercise A-to-B-to-A, action failure, state persistence after relaunch, and physical/virtual state indicators.

### Task 3: Edit Smartphone A/B Actions and Remove Clipboard Text Choices

**Files:**
- Modify: `Native/Views/SmartphoneSettingsView.swift`
- Modify: `Native/Views/SmartphoneFolderEditorView.swift`
- Test: `Tests/ChatGPTMicroLaunchpadTests/LaunchpadABToggleTests.swift`

**Interfaces:**
- Smartphone main-button and folder-shortcut editors expose optional B action configuration alongside the existing short/long-press controls.
- Existing `LaunchpadStore.updateSmartphoneButton(_:at:)` persists each edit and shares the result with the remote bridge.

- [ ] Run `testLongPressDoesNotChangeShortPressToggleState` before changing the phone editor and again after the editor change.
- [ ] Add A/B enable and action-selection controls to the smartphone button editor without changing its long-press editor; disabling B resets the state to A.
- [ ] Add the same A/B controls to folder shortcut editing and reset behavior.
- [ ] Remove Clipboard Text from smartphone button and folder shortcut selectors, leaving legacy action values untouched.
- [ ] Exercise editor persistence across app relaunch and verify long-press editing does not alter A/B state.

### Task 4: Render Smartphone State and Verify End-to-End Toggle Behavior

**Files:**
- Modify: `Android/app/src/main/java/com/pdg/galaxymicrolaunchpad/SmartphoneRemoteConfiguration.kt`
- Modify: `Android/app/src/main/java/com/pdg/galaxymicrolaunchpad/MainActivity.kt`
- Modify: `Native/Services/CodexRemoteBridge.swift`
- Test: `Android/app/src/test/java/com/pdg/galaxymicrolaunchpad/SmartphoneABToggleTest.kt`
- Test: `Tests/ChatGPTMicroLaunchpadTests/CodexRemoteStateTests.swift`

**Interfaces:**
- Android `ControlAction` carries whether B is configured and `isSecondActionActive` from each JSON button and folder shortcut; Android does not need to cache B's payload because Mac executes phone presses from the persisted shared configuration.
- `ActionTile` presents the active A/B state for configured toggle actions, including folder shortcuts.

- [ ] Add parser tests `testButtonCarriesToggleState`, `testFolderShortcutCarriesToggleState`, and `testLegacyButtonDefaultsToStateA`; add a bridge test for Clipboard Text in B actions; run the Android and Swift focused suites and confirm the new behavior assertions fail.
- [ ] Parse optional B action/state fields with defaults for older remote payloads, including nested folder shortcuts; rerun the Android unit test and confirm it passes.
- [ ] Render a visible A/B indicator and accessibility state on smartphone buttons and folder shortcuts when B is configured.
- [ ] Ensure remote bridge sanitization also strips any legacy Clipboard Text value nested inside an optional B action.
- [ ] Build the Android app; exercise smartphone A-to-B-to-A, reconnect/relaunch persistence, folder shortcut toggling, and remote badge updates. Run `swift test` for the full suite.
- [ ] Confirm all three action selectors omit Clipboard Text and an existing saved Clipboard Text action still executes.
