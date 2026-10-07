# A/B Toggle Actions for Launchpad Buttons

## Goal

Let one Mac Launchpad pad or smartphone Launchpad button alternate between two configured actions. The initial state is A. Each press switches to the other state and runs the newly active action, so the first press from A runs B. The state survives app restarts and phone reconnects.

## Scope

- Add optional A/B actions to Mac Launchpad pads and smartphone buttons, including folder shortcuts.
- Keep the current action as A for existing configurations. A button without B remains unchanged.
- Keep smartphone long-press actions independent from the A/B short-press toggle.
- Show the active A/B state in the Mac and smartphone interfaces. On physical Launchpad hardware, use the pad's configured colors to distinguish the two states.
- Remove Clipboard Text from all button action selectors, including the Mac pad inspector, smartphone button editor, and folder shortcut editor.
- Keep the legacy `clipboardText` model case and runner path so previously saved configurations remain readable and continue to work. Do not migrate or erase their saved text. New settings will not offer this action.

## State and execution

Store the optional B action and the current A/B state with each button's existing configuration. Mac pad state follows the saved Mac page. Smartphone button and folder shortcut state follows the shared smartphone-page configuration, which is the source used by the Mac bridge and sent to Android.

A press updates the saved state before executing the action selected by the new state. The state changes even if execution reports an error. A phone press remains a single remote button command: the Mac toggles the saved state, executes that action, and republishes the updated smartphone pages for the phone indicator.

Disabling A/B mode or removing B resets the button to A and restores the existing single-action behavior. Changing either configured action does not change the current state.

## Compatibility

The new fields decode with defaults when reading older saved pages. Existing single-action buttons continue running A without a state change. Existing saved Clipboard Text actions remain intact and executable, but the action is omitted from all button action menus going forward.

## Validation

- Build the macOS app and Android app.
- Exercise A-to-B-to-A on a Mac hardware/virtual pad, a smartphone button, and a folder shortcut.
- Confirm each state survives a restart or reconnect and is reflected on the phone after a remote press.
- Confirm legacy button configurations still decode and Clipboard Text is absent from every button action selector.
