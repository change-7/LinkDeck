import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class AppRegistrationIconTests: XCTestCase {
    func testRegisteringAppReplacesOldIconAndPreservesOtherSide() throws {
        let original = Data([1, 2, 3])
        let replacement = try XCTUnwrap(AppRegistrationService.iconData(for: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        XCTAssertNotNil(NSImage(data: replacement))
        let app = RegisteredApplication(name: "Calculator", bundleIdentifier: "com.apple.calculator", iconData: replacement)
        var button = SmartphoneButton(id: "button", symbol: "", customIconData: original, secondCustomIconData: original, usesActionIconForSymbol: false)
        app.applyIcon(to: &button, isSecondAction: false)
        XCTAssertEqual(button.customIconData, replacement)
        XCTAssertEqual(button.secondCustomIconData, original)
        XCTAssertEqual(button.symbol, "app")
        XCTAssertTrue(button.usesActionIconForSymbol)
        button.customIconData = original
        app.applyIcon(to: &button, isSecondAction: true)
        XCTAssertEqual(button.customIconData, original)
        XCTAssertEqual(button.secondCustomIconData, replacement)
        var shortcut = SmartphoneFolderShortcut(id: "shortcut", customIconData: original, secondCustomIconData: original)
        app.applyIcon(to: &shortcut, isSecondAction: true)
        XCTAssertEqual(shortcut.customIconData, original)
        XCTAssertEqual(shortcut.secondCustomIconData, replacement)
        let restored = try JSONDecoder().decode(SmartphoneButton.self, from: JSONEncoder().encode(button))
        XCTAssertEqual(restored.secondCustomIconData, replacement)
    }
}
