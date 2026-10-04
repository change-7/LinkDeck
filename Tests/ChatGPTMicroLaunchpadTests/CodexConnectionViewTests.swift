import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexConnectionViewTests: XCTestCase {
    func testSettingsSurface_includesApprovalSoundSettings() {
        XCTAssertEqual(CodexConnectionView.availableTabTitles, [
            "표시 설정", "상태별 모션", "모션 프리셋", "휴대폰 스킨", "완료 사운드", "승인 사운드", "ChatGPT 연결"
        ])
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
