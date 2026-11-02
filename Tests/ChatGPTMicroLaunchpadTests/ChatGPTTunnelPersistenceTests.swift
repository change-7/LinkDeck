import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class ChatGPTTunnelPersistenceTests: XCTestCase {
    func testUnexpectedExitRetriesWithCappedBackoffAndKeepsOneOwner() async throws {
        let controller = makeController()
        var attempts = 0
        var delays: [Duration] = []
        controller.connect(run: {
            XCTAssertTrue(controller.isActive)
            attempts += 1
            if attempts == 8 { controller.autoConnect = false }
        }, retrySleep: { delay in
            XCTAssertTrue(controller.isActive)
            XCTAssertFalse(controller.isReady)
            delays.append(delay)
            controller.connect(run: { XCTFail("A retry must retain connection ownership") })
        })
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 8)
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30].map { .seconds($0) })
    }

    func testUnexpectedExitDoesNotRetryWhenAutoConnectIsDisabled() async throws {
        let controller = makeController()
        controller.autoConnect = false
        var attempts = 0
        controller.connect(run: { attempts += 1 }, retrySleep: { _ in XCTFail("Retry is disabled") })
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(controller.isReady)
    }

    func testApplicationTerminationDisconnectCancelsBackoffAndAllowsLaterManualConnect() async throws {
        let controller = makeController()
        var attempts = 0
        var sleeping = false
        controller.connect(run: { attempts += 1 }, retrySleep: { _ in
            sleeping = true
            try await Task.sleep(for: .seconds(60))
        })
        try await waitUntil { sleeping }
        controller.disconnect()
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(controller.autoConnect)
        XCTAssertFalse(controller.isReady)
        XCTAssertEqual(controller.message, "연결 안 됨")

        controller.autoConnect = false
        controller.connect(run: { attempts += 1 })
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 2, "Completed cancellation must release task ownership")
    }

    func testUserDisconnectCancelsBackoffAndDisablesAutoConnect() async throws {
        let controller = makeController()
        var attempts = 0
        var sleeping = false
        controller.connect(run: { attempts += 1 }, retrySleep: { _ in
            sleeping = true
            try await Task.sleep(for: .seconds(60))
        })
        try await waitUntil { sleeping }
        controller.disconnect(disableAutoConnect: true)
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(controller.autoConnect)
    }

    func testDisconnectDuringAttemptRetainsOwnershipUntilCleanupCompletes() async throws {
        let controller = makeController()
        var finishAttempt: CheckedContinuation<Void, Never>?
        var attempts = 0
        controller.connect(run: {
            attempts += 1
            await withCheckedContinuation { finishAttempt = $0 }
            XCTAssertTrue(Task.isCancelled)
        }, retrySleep: { _ in XCTFail("Cancelled attempts must not retry") })
        try await waitUntil { finishAttempt != nil }
        controller.disconnect()
        XCTAssertTrue(controller.isActive)
        controller.connect(run: { XCTFail("Cleanup still owns the connection") })
        finishAttempt?.resume()
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(controller.autoConnect)
    }

    func testDisconnectBeforeTaskStartsNeverRunsAnAttempt() async throws {
        let controller = makeController()
        controller.connect(run: { XCTFail("Disconnected before the task started") })
        controller.disconnect()
        try await waitUntil { !controller.isActive }
        XCTAssertTrue(controller.autoConnect)
    }

    func testDisablingAutoConnectDuringBackoffPreventsNextAttempt() async throws {
        let controller = makeController()
        var attempts = 0
        controller.connect(run: { attempts += 1 }, retrySleep: { _ in controller.autoConnect = false })
        try await waitUntil { !controller.isActive }
        XCTAssertEqual(attempts, 1)
    }

    private func makeController() -> ChatGPTTunnelController {
        let suite = "LinkDeckTunnelTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ChatGPTTunnelController(preferences: defaults,
            readCredential: { "test-secret" }, saveCredential: { _ in }, deleteCredential: {})
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Tunnel lifecycle did not settle")
    }

    func testTunnelSupervisorExitsWhenOwningAppExits() async throws {
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/bin/sleep")
        owner.arguments = ["60"]
        try owner.run()
        defer { if owner.isRunning { owner.terminate() } }
        let supervisor = Process()
        supervisor.executableURL = URL(fileURLWithPath: "/bin/sh")
        supervisor.arguments = LinkDeckTunnelLaunch.supervisedArguments(executable: "/bin/sleep", arguments: ["60"], ownerPID: owner.processIdentifier)
        try supervisor.run()
        defer { if supervisor.isRunning { supervisor.terminate() } }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(supervisor.isRunning)
        owner.terminate()
        owner.waitUntilExit()
        for _ in 0..<40 {
            if !supervisor.isRunning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(supervisor.isRunning, "The tunnel must not survive its owning app")
    }

    func testRelaunchRestoresKeyAndAutoConnectWithoutSavingSecretInPreferences() throws {
        let suite = "LinkDeckTunnelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var credential: String?
        let first = ChatGPTTunnelController(preferences: defaults,
            readCredential: { credential }, saveCredential: { credential = $0 }, deleteCredential: { credential = nil })
        first.tunnelID = " tunnel_test "
        first.apiKey = " test-secret "
        let saved = try first.savedConfiguration()
        XCTAssertEqual(saved.id, "tunnel_test")
        XCTAssertEqual(credential, "test-secret")
        XCTAssertTrue(first.apiKey.isEmpty)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String)?.contains("test-secret") == true })

        let reopened = ChatGPTTunnelController(preferences: defaults,
            readCredential: { credential }, saveCredential: { _ in XCTFail("Do not rewrite a saved key") }, deleteCredential: { credential = nil })
        XCTAssertTrue(reopened.autoConnect)
        XCTAssertEqual(reopened.tunnelID, "tunnel_test")
        XCTAssertEqual(try reopened.savedConfiguration().key, "test-secret")
        reopened.disconnect()
        XCTAssertTrue(reopened.autoConnect)
        reopened.disconnect(disableAutoConnect: true)
        XCTAssertFalse(defaults.bool(forKey: "linkdeck.chatgpt-auto-connect"))
        reopened.autoConnect = true
        reopened.forgetCredential()
        XCTAssertNil(credential)
        XCTAssertFalse(reopened.autoConnect)
        XCTAssertThrowsError(try reopened.savedConfiguration())
    }

    func testKeychainFailureDoesNotPersistPartialConfigurationOrClearEnteredKey() throws {
        let suite = "LinkDeckTunnelTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = ChatGPTTunnelController(preferences: defaults,
            readCredential: { throw CocoaError(.fileReadNoPermission) },
            saveCredential: { _ in throw CocoaError(.fileWriteNoPermission) }, deleteCredential: {})
        controller.tunnelID = "tunnel_test"
        XCTAssertThrowsError(try controller.savedConfiguration())
        controller.apiKey = "test-secret"
        XCTAssertThrowsError(try controller.savedConfiguration())
        XCTAssertEqual(controller.apiKey, "test-secret")
        XCTAssertNil(defaults.string(forKey: "linkdeck.chatgpt-tunnel-id"))
        controller.tunnelID = "invalid"
        XCTAssertThrowsError(try controller.savedConfiguration())
    }
}
