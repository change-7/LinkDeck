import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexStatusBarIndicatorTests: XCTestCase {
    func testLEDBubbleMenuItemVisibility_defaultsToHiddenAndFollowsPreference() {
        let suite = "LEDBubbleMenuItemTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let menu = NSMenu()
        let item = NSMenuItem(title: "LED 말풍선 표시", action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(AppDelegate.ledBubbleMenuItemPreferenceKey)
        menu.addItem(item)

        AppDelegate.updateLEDBubbleMenuItemVisibility(in: menu, preferences: preferences)
        XCTAssertTrue(item.isHidden)
        preferences.set(false, forKey: AppDelegate.ledBubbleMenuItemPreferenceKey)
        AppDelegate.updateLEDBubbleMenuItemVisibility(in: menu, preferences: preferences)
        XCTAssertTrue(item.isHidden)
        preferences.set(true, forKey: AppDelegate.ledBubbleMenuItemPreferenceKey)
        AppDelegate.updateLEDBubbleMenuItemVisibility(in: menu, preferences: preferences)
        XCTAssertFalse(item.isHidden)
    }

    func testAnimationStates_includeWorkAndAttentionStatesOnly() {
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.connecting))
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.running))
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.waitingForApproval))
        XCTAssertTrue(CodexStatusBarIndicator.isAnimatedActivity(.failed))
        XCTAssertFalse(CodexStatusBarIndicator.isAnimatedActivity(.idle))
        XCTAssertFalse(CodexStatusBarIndicator.isAnimatedActivity(.completed))
    }
}
