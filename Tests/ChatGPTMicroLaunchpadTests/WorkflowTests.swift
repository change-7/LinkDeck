import XCTest
@testable import ChatGPTMicroLaunchpad

final class WorkflowTests: XCTestCase {
    func testWorkflowRoundTripAndLegacyAction() throws {
        let legacy = try JSONDecoder().decode(PadAction.self, from: Data(#"{"kind":"url","value":"https://example.com"}"#.utf8))
        XCTAssertTrue(legacy.workflowSteps.isEmpty)
        let workflow = PadAction(kind: .workflow, workflowSteps: [
            WorkflowStep(action: PadAction(kind: .terminalCommand, value: "pwd", showTerminalWindow: false), delayAfter: 0.25),
            WorkflowStep(action: PadAction(kind: .shortcut, value: "cmd+c"))
        ])
        XCTAssertEqual(try JSONDecoder().decode(PadAction.self, from: JSONEncoder().encode(workflow)), workflow)
    }

    @MainActor
    func testExecutionOrderAndDelay() async throws {
        let path = "/private/tmp/linkdeck-workflow-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let workflow = PadAction(kind: .workflow, workflowSteps: [
            WorkflowStep(action: PadAction(kind: .terminalCommand, value: "printf 'first\\n' >> '\(path)'", showTerminalWindow: false), delayAfter: 0.25),
            WorkflowStep(action: PadAction(kind: .terminalCommand, value: "printf 'second\\n' >> '\(path)'", showTerminalWindow: false))
        ])
        let started = Date()
        _ = try await MacActionRunner().executeWorkflow(workflow)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.23)
        for _ in 0..<100 {
            if (try? String(contentsOfFile: path, encoding: .utf8)) == "first\nsecond\n" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "first\nsecond\n")
    }

    @MainActor
    func testFailureStopsRemainingStepsAndInvalidDelaysAreRejected() async throws {
        let path = "/private/tmp/linkdeck-workflow-failure-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let runner = MacActionRunner()
        var workflow = PadAction(kind: .workflow, workflowSteps: [
            WorkflowStep(action: PadAction(kind: .app, value: "com.linkdeck.nonexistent.\(UUID().uuidString)")),
            WorkflowStep(action: PadAction(kind: .terminalCommand, value: "touch '\(path)'", showTerminalWindow: false))
        ])
        do {
            _ = try await runner.executeWorkflow(workflow)
            XCTFail("Missing app should stop the workflow")
        } catch MacActionError.workflowStepFailed(let number, _) {
            XCTAssertEqual(number, 1)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        workflow.workflowSteps[0].delayAfter = -.infinity
        XCTAssertThrowsError(try runner.validateWorkflow(workflow))
        workflow.workflowSteps[0].delayAfter = -1
        XCTAssertThrowsError(try runner.validateWorkflow(workflow))
        workflow.workflowSteps[0].delayAfter = 3601
        XCTAssertThrowsError(try runner.validateWorkflow(workflow))
        workflow.workflowSteps[0].delayAfter = 0
        workflow.workflowSteps[0].action = PadAction(kind: .workflow)
        XCTAssertThrowsError(try runner.validateWorkflow(workflow))
    }
}
