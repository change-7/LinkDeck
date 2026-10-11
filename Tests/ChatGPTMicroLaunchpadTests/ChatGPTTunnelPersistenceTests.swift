import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class ChatGPTTunnelPersistenceTests: XCTestCase {
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
