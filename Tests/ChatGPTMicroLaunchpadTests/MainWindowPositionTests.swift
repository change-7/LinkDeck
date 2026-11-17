import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class MainWindowPositionTests: XCTestCase {
    private let primary = NSRect(x: 0, y: 0, width: 1440, height: 880)
    private let secondary = NSRect(x: -1200, y: 0, width: 1200, height: 900)
    private let size = NSSize(width: 360, height: 300)

    func testRestoresPositionOnSecondaryDisplay() {
        let frame = AppDelegate.restoredMainWindowFrame(
            size: size, topLeft: NSPoint(x: -800, y: 790), defaultScreen: primary, screens: [primary, secondary]
        )
        XCTAssertEqual(frame, NSRect(x: -800, y: 490, width: 360, height: 300))
    }

    func testClampsPositionToVisibleArea() {
        let frame = AppDelegate.restoredMainWindowFrame(
            size: size, topLeft: NSPoint(x: 1300, y: 930), defaultScreen: primary, screens: [primary]
        )
        XCTAssertEqual(frame, NSRect(x: 1080, y: 580, width: 360, height: 300))
    }

    func testCentersWindowWhenSavedDisplayIsDisconnected() {
        let frame = AppDelegate.restoredMainWindowFrame(
            size: size, topLeft: NSPoint(x: -800, y: 790), defaultScreen: primary, screens: [primary]
        )
        XCTAssertEqual(frame, NSRect(x: 540, y: 290, width: 360, height: 300))
    }
}
