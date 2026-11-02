import XCTest
@testable import ChatGPTMicroLaunchpad

final class SmartphonePageManagementTests: XCTestCase {
    func testBlankPageUsesUniquePageScopedIDsAndEmptyButtons() {
        let page = SmartphoneDefaults.blankPage(id: "smartphone_page_\(UUID().uuidString)", name: "PAGE 04")

        XCTAssertEqual(page.buttons.count, SmartphoneDefaults.buttonCount)
        XCTAssertEqual(page.buttons.map(\.id), (0..<16).map { "\(page.id)_button_\($0)" })
        XCTAssertTrue(page.buttons.allSatisfy { $0.title.isEmpty && $0.symbol.isEmpty && $0.action.kind == .none })

        let fallback = SmartphoneDefaults.defaultButton(pageIndex: SmartphoneDefaults.pageCount, buttonIndex: 0)
        XCTAssertEqual(fallback.id, "smartphone_page_3_button_0")
        XCTAssertTrue(fallback.title.isEmpty && fallback.symbol.isEmpty)
    }

    func testPersistedPagesReloadFourPagesFromIsolatedPreferences() throws {
        let domain = "SmartphonePageManagementTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        var savedPages = SmartphoneDefaults.pages()
        savedPages.append(SmartphoneDefaults.blankPage(id: "smartphone_page_\(UUID().uuidString)", name: "PAGE 04"))
        preferences.set(try JSONEncoder().encode(savedPages), forKey: SmartphoneDefaults.storageKey)

        XCTAssertEqual(SmartphoneDefaults.persistedPages(from: preferences), savedPages)
    }

    func testNormalizationKeepsPageAndButtonIDsAndConfigurationsAfterMiddlePageRemoval() {
        var pages = SmartphoneDefaults.pages()
        var retainedPage = pages[2]
        var button = retainedPage.buttons[0]
        button.customIconData = Data([0x01, 0x02])
        button.action = PadAction(kind: .appFolder, value: "com.example.Editor")
        button.longPressAction = PadAction(kind: .shortcut, value: "cmd+shift+p")
        button.secondAction = PadAction(kind: .shortcut, value: "cmd+shift+r")
        button.isSecondActionActive = true
        button.folderShortcuts = [SmartphoneFolderShortcut(
            id: "\(button.id)_folder_0",
            title: "Project",
            action: PadAction(kind: .url, value: "https://example.com"),
            longPressAction: PadAction(kind: .shortcut, value: "cmd+o"),
            secondAction: PadAction(kind: .shortcut, value: "cmd+w"),
            isSecondActionActive: true
        )]
        retainedPage.buttons[0] = button
        pages[2] = retainedPage
        pages.remove(at: 1)

        let normalized = pages.map { SmartphoneDefaults.normalized($0) }

        XCTAssertEqual(normalized.map(\.id), [pages[0].id, retainedPage.id])
        XCTAssertEqual(normalized[1], retainedPage)
        XCTAssertEqual(normalized[1].buttons.map(\.id), retainedPage.buttons.map(\.id))
    }

    func testNormalizationFillsMissingLegacyButtonsFromPageIDAfterReordering() {
        let defaults = SmartphoneDefaults.pages()
        var remainingPages = [defaults[0], defaults[2]]
        remainingPages[1].buttons = [remainingPages[1].buttons[0]]

        let normalized = remainingPages.map { SmartphoneDefaults.normalized($0) }

        XCTAssertEqual(normalized[1].id, defaults[2].id)
        XCTAssertEqual(normalized[1].buttons.count, SmartphoneDefaults.buttonCount)
        XCTAssertEqual(normalized[1].buttons[15], defaults[2].buttons[15])
    }

    func testBackupRoundTripsVariableSmartphonePageCount() throws {
        var smartphonePages = SmartphoneDefaults.pages()
        smartphonePages.append(SmartphoneDefaults.blankPage(id: "smartphone_page_\(UUID().uuidString)", name: "PAGE 04"))
        let backup = LaunchpadBackup(
            launchpadPages: PadDefaults.pages(),
            smartphonePages: smartphonePages,
            motionPresets: [],
            codexMotionPresetIDs: [:],
            codexMotionPresentations: [:],
            codexMotionDisplaySettings: CodexMotionDisplaySettings()
        )

        let decoded = try JSONDecoder().decode(LaunchpadBackup.self, from: JSONEncoder().encode(backup))

        XCTAssertEqual(try decoded.validated().smartphonePages, smartphonePages)
    }
}
