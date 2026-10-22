import XCTest
@testable import ChatGPTMicroLaunchpad

final class AppQuitTests: XCTestCase {
    func testTerminationPermissionDefaultsOffAndRoundTrips() throws {
        let legacy = Data(#"{"kind":"app","value":"test.app"}"#.utf8)
        var action = try JSONDecoder().decode(PadAction.self, from: legacy)
        XCTAssertFalse(action.canQuitApp)
        action.allowsAppTermination = true
        XCTAssertTrue(action.canQuitApp)
        XCTAssertEqual(try JSONDecoder().decode(PadAction.self, from: JSONEncoder().encode(action)), action)
        action.value = "test.other"
        XCTAssertFalse(action.allowsAppTermination)
        action.allowsAppTermination = true
        action.kind = .shortcut
        XCTAssertFalse(action.allowsAppTermination)
        XCTAssertFalse(action.canQuitApp)
    }

    func testOnlyCheckedAppActionsAuthorizeTermination() {
        let actions = [
            PadAction(kind: .app, value: "test.enabled", allowsAppTermination: true),
            PadAction(kind: .app, value: "test.disabled"),
            PadAction(kind: .appFolder, value: "test.folder", allowsAppTermination: true),
            PadAction(kind: .appQuit, value: "test.quit", allowsAppTermination: true),
            PadAction(kind: .shortcut, value: "cmd+c", targetAppBundleIdentifier: "test.shortcut", allowsAppTermination: true)
        ]
        XCTAssertEqual(RegisteredButtonApps.identifiers(actions: actions, terminationAllowedOnly: true), ["test.enabled", "test.folder"])
        XCTAssertTrue(RegisteredButtonApps.identifiers(actions: [actions[1]], terminationAllowedOnly: true).isEmpty)
    }

    func testRegisteredAppsIncludeBothDevicesAndAlternateActionsButNotQuitTargets() {
        var pages = PadDefaults.pages()
        for index in pages.indices { pages[index].pads = [] }
        pages[0].pads = [Pad(id: "mac", action: PadAction(kind: .app, value: "test.mac"),
                             secondAction: PadAction(kind: .appFolder, value: "test.alternate"))]
        let workflow = PadAction(kind: .workflow, workflowSteps: [
            WorkflowStep(action: PadAction(kind: .app, value: "test.workflow"))
        ])
        let phone = SmartphoneButton(
            id: "phone", action: PadAction(kind: .app, value: "test.phone"),
            folderShortcuts: [SmartphoneFolderShortcut(
                id: "folder", action: workflow,
                longPressAction: PadAction(kind: .shortcut, value: "cmd+c", targetAppBundleIdentifier: "test.target")
            )],
            longPressAction: PadAction(kind: .app, value: "test.long"),
            secondAction: PadAction(kind: .appQuit, value: "test.unregistered")
        )
        let actual = RegisteredButtonApps.identifiers(macPages: pages, phonePages: [SmartphonePage(id: "phone", name: "", buttons: [phone])])
        XCTAssertEqual(actual, ["test.mac", "test.alternate", "test.workflow", "test.phone", "test.target", "test.long"])
    }

    @MainActor
    func testUnregisteredQuitIsRejectedBeforeLookingForRunningApps() {
        let runner = MacActionRunner(registeredApps: { [] })
        XCTAssertThrowsError(try runner.execute(PadAction(kind: .appQuit, value: "com.apple.finder"))) { error in
            guard case MacActionError.appNotRegistered = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertThrowsError(try runner.execute(PadAction(kind: .appQuit)))
    }

    @MainActor
    func testRemovingRegistrationRevokesExistingQuitAction() throws {
        let id = "test.linkdeck.not-running.\(UUID().uuidString)"
        var registered: Set<String> = [id]
        let runner = MacActionRunner(registeredApps: { registered })
        let action = PadAction(kind: .appQuit, value: id)
        XCTAssertEqual(try runner.execute(action), "선택한 앱이 실행 중이 아닙니다.")
        registered.remove(id)
        XCTAssertThrowsError(try runner.execute(action))
    }

    func testQuitActionSurvivesBackupEncoding() throws {
        let action = PadAction(kind: .appQuit, value: "test.registered")
        XCTAssertEqual(try JSONDecoder().decode(PadAction.self, from: JSONEncoder().encode(action)), action)
    }
}
