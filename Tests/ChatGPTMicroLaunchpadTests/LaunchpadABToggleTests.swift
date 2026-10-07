import XCTest
@testable import ChatGPTMicroLaunchpad

final class LaunchpadABToggleTests: XCTestCase {
    func testLegacySmartphoneConfigurationDefaultsToA() throws {
        let legacyButtonJSON = Data(#"{"id":"button","title":"Legacy","symbol":"play.fill","action":{"kind":"shortcut","value":"cmd+a"},"folderShortcuts":[{"id":"shortcut","title":"Shortcut","action":{"kind":"shortcut","value":"cmd+c"},"longPressAction":{"kind":"none","value":""}}],"longPressAction":{"kind":"none","value":""}}"#.utf8)

        let button = try JSONDecoder().decode(SmartphoneButton.self, from: legacyButtonJSON)
        let encoded = try JSONEncoder().encode(button)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let shortcut = try XCTUnwrap(button.folderShortcuts.first)

        let legacyPadJSON = Data(#"{"id":"pad","title":"Legacy","symbol":"play.fill","idleColor":"off","activeColor":"green","action":{"kind":"shortcut","value":"cmd+p"}}"#.utf8)
        let pad = try JSONDecoder().decode(Pad.self, from: legacyPadJSON)

        XCTAssertEqual(button.action.value, "cmd+a")
        XCTAssertEqual(object["isSecondActionActive"] as? Bool, false)
        XCTAssertNil(object["secondAction"])
        XCTAssertFalse(shortcut.isSecondActionActive)
        XCTAssertNil(shortcut.secondAction)
        XCTAssertFalse(pad.isSecondActionActive)
        XCTAssertNil(pad.secondAction)
    }

    func testToggleFieldsSurviveCodableRoundTrip() throws {
        let buttonJSON = Data(#"{"id":"button","title":"Toggle","symbol":"play.fill","action":{"kind":"shortcut","value":"cmd+a"},"secondAction":{"kind":"url","value":"https://example.com"},"isSecondActionActive":true,"folderShortcuts":[],"longPressAction":{"kind":"none","value":""}}"#.utf8)

        let button = try JSONDecoder().decode(SmartphoneButton.self, from: buttonJSON)
        let encoded = try JSONEncoder().encode(button)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let secondAction = try XCTUnwrap(object["secondAction"] as? [String: Any])

        XCTAssertEqual(secondAction["value"] as? String, "https://example.com")
        XCTAssertEqual(object["isSecondActionActive"] as? Bool, true)
    }

    func testSmartphonePressAlternatesButtonAndFolderActions() throws {
        var pages = [SmartphonePage(
            id: "page",
            name: "Page",
            buttons: [SmartphoneButton(
                id: "button",
                action: PadAction(kind: .shortcut, value: "cmd+a"),
                folderShortcuts: [SmartphoneFolderShortcut(
                    id: "shortcut",
                    action: PadAction(kind: .shortcut, value: "cmd+c"),
                    secondAction: PadAction(kind: .shortcut, value: "cmd+d")
                )],
                secondAction: PadAction(kind: .shortcut, value: "cmd+b")
            )]
        )]

        XCTAssertEqual(SmartphoneDefaults.toggleAction(id: "button", in: &pages)?.value, "cmd+b")
        XCTAssertTrue(pages[0].buttons[0].isSecondActionActive)
        XCTAssertEqual(SmartphoneDefaults.toggleAction(id: "button", in: &pages)?.value, "cmd+a")
        XCTAssertFalse(pages[0].buttons[0].isSecondActionActive)
        XCTAssertEqual(SmartphoneDefaults.toggleAction(id: "shortcut", in: &pages)?.value, "cmd+d")
        XCTAssertTrue(pages[0].buttons[0].folderShortcuts[0].isSecondActionActive)
        XCTAssertEqual(SmartphoneDefaults.toggleAction(id: "shortcut", in: &pages)?.value, "cmd+c")
        XCTAssertFalse(pages[0].buttons[0].folderShortcuts[0].isSecondActionActive)
    }

    func testLongPressDoesNotChangeShortPressToggleState() throws {
        let pages = [SmartphonePage(
            id: "page",
            name: "Page",
            buttons: [SmartphoneButton(
                id: "button",
                action: PadAction(kind: .shortcut, value: "cmd+a"),
                longPressAction: PadAction(kind: .shortcut, value: "cmd+l"),
                secondAction: PadAction(kind: .shortcut, value: "cmd+b")
            )]
        )]

        XCTAssertEqual(SmartphoneDefaults.action(id: "button", in: pages, longPress: true)?.value, "cmd+l")
        XCTAssertFalse(pages[0].buttons[0].isSecondActionActive)
    }

    func testPadAlternatesFromBBackToA() {
        var pad = Pad(
            id: "pad",
            action: PadAction(kind: .shortcut, value: "cmd+a"),
            secondAction: PadAction(kind: .shortcut, value: "cmd+b")
        )

        XCTAssertEqual(pad.actionForNextPress().value, "cmd+b")
        XCTAssertTrue(pad.isSecondActionActive)
        XCTAssertEqual(pad.actionForNextPress().value, "cmd+a")
        XCTAssertFalse(pad.isSecondActionActive)
    }

    @MainActor
    func testMacPadStatePersistsBeforeFailedAction() throws {
        let store = LaunchpadStore()
        let pageIndex = store.selectedPage
        let originalPad = try XCTUnwrap(store.currentPage.pads.first(where: { $0.id == "grid_0_0" }))
        defer { store.update(originalPad) }

        var configuredPad = originalPad
        configuredPad.action = PadAction(kind: .shortcut, value: "cmd+a")
        configuredPad.secondAction = PadAction(kind: .shortcut, value: "")
        configuredPad.isSecondActionActive = false
        store.update(configuredPad)

        let action = try XCTUnwrap(store.actionForNextPress(on: configuredPad.id))

        XCTAssertEqual(action.value, "")
        XCTAssertTrue(store.currentPage.pads.first(where: { $0.id == configuredPad.id })?.isSecondActionActive == true)
        XCTAssertThrowsError(try MacActionRunner().execute(action))
        let relaunchedStore = LaunchpadStore()
        XCTAssertTrue(relaunchedStore.pages[pageIndex].pads.first(where: { $0.id == configuredPad.id })?.isSecondActionActive == true)
    }

    @MainActor
    func testClearingSmartphoneButtonRemovesSecondActionAndResetsA() throws {
        let store = LaunchpadStore()
        let pageIndex = 0
        let buttonIndex = 0
        let originalButton = store.smartphonePages[pageIndex].buttons[buttonIndex]
        defer { store.updateSmartphoneButton(originalButton, at: pageIndex) }

        var configuredButton = originalButton
        configuredButton.secondAction = PadAction(kind: .url, value: "https://example.com")
        configuredButton.isSecondActionActive = true
        store.updateSmartphoneButton(configuredButton, at: pageIndex)
        store.clearSmartphoneButton(pageIndex: pageIndex, buttonIndex: buttonIndex)

        let clearedButton = store.smartphonePages[pageIndex].buttons[buttonIndex]
        XCTAssertNil(clearedButton.secondAction)
        XCTAssertFalse(clearedButton.isSecondActionActive)
    }
}
