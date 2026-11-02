import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class CodexRemoteSyncTests: XCTestCase {
    private func state(_ activity: CodexActivity = .running, pages: [SmartphonePage] = SmartphoneDefaults.pages(),
                       icons: [String: SmartphoneIconAsset] = [:], completion: Int = 0) -> CodexRemoteState {
        CodexRemoteState(macConnected: true, codexConnected: true, activity: activity, message: activity.rawValue,
                         weeklyUsage: nil, fiveHourUsage: nil, smartphonePages: pages, smartphoneIconAssets: icons,
                         completionEventID: completion)
    }

    private func objects(_ sync: CodexRemoteSync, cached: [String: String] = [:]) throws -> [[String: Any]] {
        try sync.frames(cachedRevisions: cached).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any])
        }
    }

    func testColdAndWarmReconnectAlwaysReconcileLatestStateAndAllResourceVersions() throws {
        let sync = CodexRemoteSync()
        let value = state()
        XCTAssertTrue(sync.update(value, completionSound: .builtIn, approvalSound: .builtIn))
        let cold = try objects(sync)
        XCTAssertEqual(cold.first?["type"] as? String, "sync")
        XCTAssertEqual(cold.filter { $0["type"] as? String == "resource" }.count, 4)
        let live = try XCTUnwrap(cold.last)
        XCTAssertNil(live["smartphonePages"])
        XCTAssertNil(live["smartphoneIconAssets"])
        XCTAssertEqual(live["activity"] as? String, "running")
        XCTAssertEqual(live["sequence"] as? Int, 1)
        XCTAssertFalse(sync.update(value, completionSound: .builtIn, approvalSound: .builtIn))
        XCTAssertEqual(sync.sequence, 1)
        let warm = try objects(sync, cached: sync.revisions)
        XCTAssertEqual(warm.count, 2)
        XCTAssertEqual(warm.last?["sessionID"] as? String, sync.sessionID)
        XCTAssertLessThan(CodexRemoteSync.heartbeat.count, 64)
        XCTAssertNotEqual(sync.sessionID, CodexRemoteSync().sessionID)
    }

    func testWorkCompletionErrorAndApprovalStatesAdvanceWithoutWaitingForHeartbeat() throws {
        let sync = CodexRemoteSync()
        sync.update(state(), completionSound: .builtIn, approvalSound: .builtIn)
        let revisions = sync.revisions
        for (index, activity) in [CodexActivity.completed, .failed, .waitingForApproval, .running].enumerated() {
            XCTAssertTrue(sync.update(state(activity, completion: index + 1), completionSound: .builtIn, approvalSound: .builtIn))
            let frames = try objects(sync, cached: revisions)
            XCTAssertEqual(frames.count, 2)
            XCTAssertEqual(frames.last?["activity"] as? String, activity.rawValue)
            XCTAssertEqual(frames.last?["sequence"] as? Int, index + 2)
        }
    }

    func testDeletedButtonsAndIconsReplaceTheCachedCollections() throws {
        let sync = CodexRemoteSync()
        sync.update(state(icons: ["old": SmartphoneIconAsset(data: "old")]), completionSound: .builtIn, approvalSound: .builtIn)
        let revisions = sync.revisions
        sync.update(state(pages: [], icons: [:]), completionSound: .builtIn, approvalSound: .builtIn)
        let frames = try objects(sync, cached: revisions)
        let buttons = try XCTUnwrap(frames.first { $0["name"] as? String == "buttons" }?["payload"] as? [String: Any])
        let icons = try XCTUnwrap(frames.first { $0["name"] as? String == "icons" }?["payload"] as? [String: Any])
        XCTAssertEqual((buttons["smartphonePages"] as? [Any])?.count, 0)
        XCTAssertEqual((icons["assets"] as? [String: Any])?.count, 0)
        XCTAssertEqual(sync.revisions["completionSound"], revisions["completionSound"])
        XCTAssertNotEqual(sync.revisions["buttons"], revisions["buttons"])
    }

    func testSoundContentReplacementWithSameIDInvalidatesOnlyThatResource() throws {
        let sync = CodexRemoteSync()
        let first = CodexRemoteCompletionSound(id: "custom", data: "first")
        let second = CodexRemoteCompletionSound(id: "custom", data: "second")
        sync.update(state(), completionSound: first, approvalSound: .builtIn)
        let revisions = sync.revisions
        sync.update(state(), completionSound: second, approvalSound: .builtIn)
        let frames = try objects(sync, cached: revisions)
        XCTAssertEqual(frames.filter { $0["type"] as? String == "resource" }.compactMap { $0["name"] as? String }, ["completionSound"])
    }

    func testABToggleDoesNotResendUnchangedIconVariants() throws {
        let sync = CodexRemoteSync()
        let a = SmartphoneIconAsset(data: "A")
        let b = SmartphoneIconAsset(data: "B")
        sync.update(state(icons: ["button": a, "button__A": a, "button__B": b]), completionSound: .builtIn, approvalSound: .builtIn)
        let revisions = sync.revisions
        sync.update(state(icons: ["button": b, "button__A": a, "button__B": b]), completionSound: .builtIn, approvalSound: .builtIn)
        XCTAssertEqual(sync.revisions["icons"], revisions["icons"])
        XCTAssertFalse(try objects(sync, cached: revisions).contains { $0["type"] as? String == "resource" })
    }
}
