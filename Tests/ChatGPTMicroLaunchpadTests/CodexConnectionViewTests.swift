import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexConnectionViewTests: XCTestCase {
    func testSettingsSurface_includesApprovalSoundSettings() {
        XCTAssertEqual(CodexConnectionView.availableTabTitles, [
            "연결 설정", "등록된 앱 API", "표시 설정", "휴대폰 스킨", "완료 사운드", "승인 사운드"
        ])
    }

    func testMainScreens_includePhoneButtonsAndAPIAppsOnly() {
        XCTAssertEqual(MainScreen.allCases, [.smartphoneButtons, .apiApps])
        XCTAssertNil(MainScreen(rawValue: "launchpadMini"))
    }

    func testApprovalSoundSettings_offerOnlyMacAndPhoneOutputTargets() {
        XCTAssertEqual(
            CodexApprovalSoundOutputTarget.allCases.map(\.title),
            ["휴대폰", "Mac"]
        )
        XCTAssertFalse(CodexApprovalSoundOutputTarget.phone.playsOnMac)
        XCTAssertFalse(CodexApprovalSoundOutputTarget.mac.playsOnPhone)
        XCTAssertTrue(CodexApprovalSoundOutputTarget.mac.playsOnMac)
        XCTAssertTrue(CodexApprovalSoundOutputTarget.phone.playsOnPhone)
    }
}
