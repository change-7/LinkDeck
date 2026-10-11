import XCTest
@testable import ChatGPTMicroLaunchpad

final class FolderSyncLocalizationTests: XCTestCase {
    func testFolderSyncUsesKoreanLabels() {
        XCTAssertEqual(AppText.syncList, "동기화 목록")
        XCTAssertEqual(AppText.appSettings, "앱 전체 설정")
        XCTAssertEqual(AppText.done, "완료")
        XCTAssertEqual(AppText.close, "닫기")
    }
}
