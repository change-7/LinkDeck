import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class AppAPIManifestTests: XCTestCase {
    private func manifest(id: String = "fixture", tools: [String] = ["echo"]) -> AppAPIManifest {
        AppAPIManifest(schemaVersion: 1, id: id, name: "Fixture", transport: "mcp_stdio", arguments: ["--mcp"], tools: tools)
    }

    func testManifestValidatesVersionTransportNamesAndBounds() throws {
        XCTAssertEqual(try AppAPIManifest.decode(JSONEncoder().encode(manifest())), manifest())
        for value in [manifest(id: "../escape"), manifest(id: ""), manifest(tools: ["echo", "echo"]), manifest(tools: [])] {
            XCTAssertThrowsError(try AppAPIManifest.decode(JSONEncoder().encode(value)))
        }
        XCTAssertThrowsError(try AppAPIManifest.decode(Data(repeating: 32, count: 65_537)))
        let unsupported = AppAPIManifest(schemaVersion: 2, id: "test", name: "Test", transport: "http", arguments: [], tools: ["echo"])
        XCTAssertThrowsError(try AppAPIManifest.decode(JSONEncoder().encode(unsupported)))
        var unknown = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest())) as? [String: Any])
        unknown["apiKey"] = "do-not-store-secrets"
        XCTAssertThrowsError(try AppAPIManifest.decode(JSONSerialization.data(withJSONObject: unknown)))
    }

    func testBundleManifestDetectionAndChangedManifestRequiresApproval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("api-fixture-\(UUID()).app")
        let resources = directory.appendingPathComponent("Contents/Resources")
        let executable = directory.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleID = "test.linkdeck.\(UUID().uuidString)"
        let preference = "linkdeck.app-api." + bundleID
        defer { UserDefaults.standard.removeObject(forKey: preference) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"], format: .xml, options: 0).write(to: directory.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/cat"), to: executable)
        XCTAssertNil(try RegisteredAppAPI.load(appURL: directory))
        let file = resources.appendingPathComponent("linkdeck.json")
        try JSONEncoder().encode(manifest()).write(to: file)
        let app = try XCTUnwrap(RegisteredAppAPI.load(appURL: directory))
        XCTAssertFalse(app.approved)
        UserDefaults.standard.set(app.approvalKey, forKey: preference)
        XCTAssertTrue(app.approved)
        try JSONEncoder().encode(manifest(tools: ["other"])).write(to: file)
        XCTAssertFalse(try XCTUnwrap(RegisteredAppAPI.load(appURL: directory)).approved)
        try Data("invalid".utf8).write(to: file)
        XCTAssertThrowsError(try RegisteredAppAPI.load(appURL: directory))
    }

    func testBridgeDiscoversPagesForwardsAllowedToolsAndRevokesAccess() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/app_api_mcp.py")
        let configuration = AppAPIManifest(schemaVersion: 1, id: "fixture", name: "Fixture", transport: "mcp_stdio", arguments: [fixture.path], tools: ["echo"])
        let app = RegisteredAppAPI(bundleID: "test.\(UUID())", appURL: fixture, executable: URL(fileURLWithPath: "/usr/bin/python3"), manifest: configuration, approvalKey: UUID().uuidString)
        let preference = "linkdeck.app-api." + app.bundleID
        defer { UserDefaults.standard.removeObject(forKey: preference) }
        let bridge = AppAPIMCPBridge()
        func invoke(_ method: String, _ params: [String: Any] = [:], apps: [RegisteredAppAPI]? = nil) async throws -> [String: Any] {
            let request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": "original", "method": method, "params": params])
            let response = await bridge.response(to: request, apps: apps ?? [app]) {
                LinkDeckMCPHandler.response(to: request, buttons: []) { _ in XCTFail("Must not execute"); return "" }
            }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        }
        func toolNames(_ reply: [String: Any]) -> [String] { ((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } }
        let unapproved = try await invoke("tools/list")
        XCTAssertFalse(toolNames(unapproved).contains(configuration.prefix + "echo"))
        UserDefaults.standard.set(app.approvalKey, forKey: preference)
        let listed = try await invoke("tools/list")
        XCTAssertTrue(toolNames(listed).contains(configuration.prefix + "echo"))
        XCTAssertFalse(toolNames(listed).contains(configuration.prefix + "hidden"))
        let called = try await invoke("tools/call", ["name": configuration.prefix + "echo", "arguments": ["text": "hello"]])
        XCTAssertEqual(called["id"] as? String, "original")
        XCTAssertTrue(String(describing: called).contains("hello"))
        let denied = try await invoke("tools/call", ["name": configuration.prefix + "hidden", "arguments": [:]])
        XCTAssertEqual((denied["result"] as? [String: Any])?["isError"] as? Bool, true)
        let duplicate = RegisteredAppAPI(bundleID: "test.\(UUID())", appURL: fixture, executable: app.executable, manifest: configuration, approvalKey: UUID().uuidString)
        let duplicatePreference = "linkdeck.app-api." + duplicate.bundleID
        UserDefaults.standard.set(duplicate.approvalKey, forKey: duplicatePreference)
        defer { UserDefaults.standard.removeObject(forKey: duplicatePreference) }
        let conflicts = try await invoke("tools/list", apps: [app, duplicate])
        XCTAssertFalse(toolNames(conflicts).contains(configuration.prefix + "echo"))
        XCTAssertTrue(toolNames(conflicts).contains("linkdeck_list_buttons"))
        let status = try await invoke("tools/call", ["name": "linkdeck_app_api_status", "arguments": [:]], apps: [app, duplicate])
        let statusResult = try XCTUnwrap(status["result"] as? [String: Any])
        let content = try XCTUnwrap(statusResult["content"] as? [[String: Any]])
        let statusText = try XCTUnwrap(content.first?["text"] as? String)
        let statusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(statusText.utf8)) as? [String: Any])
        let statuses = try XCTUnwrap(statusObject["apps"] as? [[String: Any]])
        XCTAssertTrue(statuses.allSatisfy { ($0["error"] as? String ?? "").contains("중복") })
        UserDefaults.standard.removeObject(forKey: preference)
        let revoked = try await invoke("tools/call", ["name": configuration.prefix + "echo", "arguments": [:]])
        XCTAssertEqual((revoked["result"] as? [String: Any])?["isError"] as? Bool, true)
        await bridge.stop()
    }
}
