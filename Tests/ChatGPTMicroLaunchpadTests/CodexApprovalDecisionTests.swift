import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexApprovalDecisionTests: XCTestCase {
    private let commandMethod = "item/commandExecution/requestApproval"

    func testExplicitChoicesPreserveOrderAndPersistentNetworkScope() throws {
        let rule: CodexIPCJSONValue = .object(["action": .string("allow"), "host": .string("example.com")])
        let persistent: CodexIPCJSONValue = .object(["applyNetworkPolicyAmendment": .object(["network_policy_amendment": rule])])
        let choices = CodexApprovalDecision.options(method: commandMethod, params: [
            "availableDecisions": .array([persistent, .string("decline"), .string("acceptForSession")])
        ])
        XCTAssertEqual(choices.map(\.option.title), ["항상 허용", "거부", "이 대화에서만 허용"])
        XCTAssertEqual(choices[0].option.detail, "호스트: example.com")
        let approval = approval(decisions: choices)
        let route = try XCTUnwrap(CodexDesktopApprovalIPC.route(for: approval, decision: choices[0].option.id))
        let encoded = try JSONSerialization.data(withJSONObject: route.params["decision"] as Any)
        XCTAssertEqual(try JSONDecoder().decode(CodexIPCJSONValue.self, from: encoded), persistent)
        XCTAssertEqual(route.params["requestId"] as? Int, 42)
        XCTAssertEqual(route.params["conversationId"] as? String, "thread-42")
        XCTAssertNil(CodexDesktopApprovalIPC.route(for: approval, decision: "accept"))
        XCTAssertNil(CodexDesktopApprovalIPC.route(for: approval, decision: "alwaysAllowEverything"))
    }

    func testSessionResponseAndDenialRemainDistinct() throws {
        let choices = CodexApprovalDecision.options(method: commandMethod, params: [
            "availableDecisions": .array([.string("acceptForSession"), .string("decline")])
        ])
        for decision in ["acceptForSession", "decline"] {
            let route = try XCTUnwrap(CodexDesktopApprovalIPC.route(for: approval(decisions: choices), decision: decision))
            XCTAssertEqual(route.params["decision"] as? String, decision)
        }
    }

    func testPersistentCommandRuleUsesOnlyProposedPrefix() throws {
        let prefix: CodexIPCJSONValue = .array([.string("git"), .string("fetch")])
        let choices = CodexApprovalDecision.options(method: commandMethod, params: ["proposedExecpolicyAmendment": prefix])
        let persistent = try XCTUnwrap(choices.first { $0.option.title == "항상 허용" })
        XCTAssertEqual(persistent.value, .object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": prefix])]))
        XCTAssertTrue(persistent.option.detail.contains("git fetch"))
        let basic = CodexApprovalDecision.options(method: commandMethod, params: [:])
        XCTAssertFalse(basic.contains { $0.option.title == "항상 허용" })
        XCTAssertTrue(CodexApprovalDecision.options(method: commandMethod, params: ["availableDecisions": .array([])]).isEmpty)
        XCTAssertTrue(CodexApprovalDecision.options(method: commandMethod, params: ["availableDecisions": .string("invalid")]).isEmpty)
    }

    func testSessionPermissionsPreserveRequestedPermissions() throws {
        let permissions: CodexIPCJSONValue = .object(["network": .object(["enabled": .bool(true)])])
        let approval = CodexDesktopPendingApproval(
            conversationID: "thread", requestID: .integer(1), requestKey: "key",
            method: "item/permissions/requestApproval", title: "", detail: "", requestedPermissions: permissions
        )
        let route = try XCTUnwrap(CodexDesktopApprovalIPC.route(for: approval, decision: "acceptForSession"))
        let response = try XCTUnwrap(route.params["response"] as? [String: Any])
        XCTAssertEqual(response["scope"] as? String, "session")
        let data = try JSONSerialization.data(withJSONObject: response["permissions"] as Any)
        XCTAssertEqual(try JSONDecoder().decode(CodexIPCJSONValue.self, from: data), permissions)
        let denied = try XCTUnwrap(CodexDesktopApprovalIPC.route(for: approval, decision: "decline"))
        let deniedResponse = try XCTUnwrap(denied.params["response"] as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(deniedResponse["permissions"] as? [String: Any]).isEmpty)
    }

    @MainActor
    func testAppServerAndPhonePayloadCarryTheSameChoicesWithoutPolicyPayloads() throws {
        let choices = CodexAppServerClient.remoteApprovalDecisions(method: commandMethod, params: [
            "availableDecisions": ["acceptForSession", "decline"]
        ])
        let remote = CodexRemoteApproval(title: "", detail: "", requestKey: "key", options: choices.map(\.option))
        let encoded = try JSONEncoder().encode(remote)
        XCTAssertEqual(try JSONDecoder().decode(CodexRemoteApproval.self, from: encoded).options, choices.map(\.option))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("execpolicy_amendment"))
    }

    private func approval(decisions: [CodexApprovalDecision]) -> CodexDesktopPendingApproval {
        CodexDesktopPendingApproval(
            conversationID: "thread-42", requestID: .integer(42), requestKey: "key-42",
            method: commandMethod, title: "", detail: "", requestedPermissions: nil, decisions: decisions
        )
    }
}
