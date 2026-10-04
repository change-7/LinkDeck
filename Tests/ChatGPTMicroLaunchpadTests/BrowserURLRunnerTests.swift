import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

final class BrowserURLRunnerTests: XCTestCase {
    func testLegacyURLAction_defaultsToNewTabAndRoundTripsCurrentTab() throws {
        var action = try JSONDecoder().decode(PadAction.self,
            from: Data(#"{"kind":"url","value":"https://example.com"}"#.utf8))
        XCTAssertFalse(action.openURLInCurrentTab)
        action.openURLInCurrentTab = true
        XCTAssertEqual(try JSONDecoder().decode(PadAction.self,
            from: JSONEncoder().encode(action)), action)
    }

    @MainActor
    func testSafariScript_changesCurrentTabAndCreatesWindowOnlyWhenNeeded() throws {
        let script = try XCTUnwrap(BrowserURLRunner.currentTabScript(
            url: URL(string: "https://example.com")!, browserBundleID: "com.apple.Safari"))
        XCTAssertTrue(script.contains("set URL of current tab of front window"))
        XCTAssertTrue(script.contains("if (count of windows) = 0 then make new document"))
        var error: NSDictionary?
        XCTAssertTrue(NSAppleScript(source: script)!.compileAndReturnError(&error), "\(String(describing: error))")
    }

    @MainActor
    func testWhaleScript_changesActiveTabAndEscapesURL() throws {
        let script = try XCTUnwrap(BrowserURLRunner.currentTabScript(
            url: URL(string: "https://example.com/?q=%22test%22")!, browserBundleID: "com.naver.Whale"))
        XCTAssertTrue(script.contains("set URL of active tab of front window"))
        XCTAssertTrue(script.contains("if (count of windows) = 0 then make new window"))
        XCTAssertTrue(script.contains("?q=%22test%22"))
        var error: NSDictionary?
        XCTAssertTrue(NSAppleScript(source: script)!.compileAndReturnError(&error), "\(String(describing: error))")
    }

    @MainActor
    func testUnsupportedBrowserAndNonWebScheme_doNotGenerateScript() {
        XCTAssertNil(BrowserURLRunner.currentTabScript(url: URL(string: "https://example.com")!,
            browserBundleID: "org.mozilla.firefox"))
        XCTAssertNil(BrowserURLRunner.currentTabScript(url: URL(string: "file:///tmp/test")!,
            browserBundleID: "com.apple.Safari"))
    }
}
