import AppKit
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class AppTerminationTests: XCTestCase {
    func testTerminationRequestIsAllowedWithoutChoosingQuitCompletelyFirst() {
        let delegate = AppDelegate()

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
    }

    func testClosingLastWindowKeepsTheBackgroundAppRunning() {
        let delegate = AppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
