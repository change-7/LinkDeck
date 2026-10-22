import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexPhoneThemeTests: XCTestCase {
    func testDeleteSelectedSkinPersistsAndFallsBackToClassic() throws {
        let suite = "CodexPhoneThemeTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = LaunchpadStore(preferences: preferences)
        store.setCodexPhoneTheme(.dotConsole)
        store.deleteCodexPhoneTheme(.dotConsole)
        XCTAssertEqual(store.codexPhoneTheme, .classic)
        XCTAssertFalse(store.availableCodexPhoneThemes.contains(.dotConsole))
        let restored = LaunchpadStore(preferences: preferences)
        XCTAssertEqual(restored.codexPhoneTheme, .classic)
        XCTAssertFalse(restored.availableCodexPhoneThemes.contains(.dotConsole))
        restored.setCodexPhoneTheme(.dotConsole)
        XCTAssertEqual(restored.codexPhoneTheme, .classic)
        restored.restoreCodexPhoneThemes()
        restored.setCodexPhoneTheme(.dotConsole)
        XCTAssertEqual(restored.codexPhoneTheme, .dotConsole)
        XCTAssertTrue(LaunchpadStore(preferences: preferences).availableCodexPhoneThemes.contains(.dotConsole))
    }

    func testDeleteInactiveSkinPreservesSelectionAndClassicCannotBeDeleted() throws {
        let suite = "CodexPhoneThemeTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = LaunchpadStore(preferences: preferences)
        store.setCodexPhoneTheme(.dotConsole)
        store.deleteCodexPhoneTheme(.pixelQuest)
        store.deleteCodexPhoneTheme(.classic)
        XCTAssertEqual(store.codexPhoneTheme, .dotConsole)
        XCTAssertFalse(store.availableCodexPhoneThemes.contains(.pixelQuest))
        XCTAssertTrue(store.availableCodexPhoneThemes.contains(.classic))
    }

    func testDotConsoleThemeSurvivesWireEncoding() throws {
        let encoded = try JSONEncoder().encode(CodexPhoneTheme.dotConsole)
        XCTAssertEqual(try JSONDecoder().decode(CodexPhoneTheme.self, from: encoded), .dotConsole)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"dotConsole\"")
    }
}
