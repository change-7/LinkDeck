import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexAdaptivePollingTests: XCTestCase {
    @MainActor
    func testApprovalChecksAreFastUntilAllWorkAndApprovalsFinish() {
        XCTAssertEqual(CodexAppServerClient.desktopApprovalPollingInterval(activeSessionCount: 0, activity: .idle, hasPendingApproval: false), 2)
        XCTAssertEqual(CodexAppServerClient.desktopApprovalPollingInterval(activeSessionCount: 1, activity: .completed, hasPendingApproval: false), 0.5)
        XCTAssertEqual(CodexAppServerClient.desktopApprovalPollingInterval(activeSessionCount: 0, activity: .running, hasPendingApproval: false), 0.5)
        XCTAssertEqual(CodexAppServerClient.desktopApprovalPollingInterval(activeSessionCount: 0, activity: .waitingForApproval, hasPendingApproval: true), 0.5)
        XCTAssertEqual(CodexAppServerClient.desktopApprovalPollingInterval(activeSessionCount: 0, activity: .completed, hasPendingApproval: false), 2)
        XCTAssertEqual(CodexAppServerClient.desktopApprovalPollingInterval(activeSessionCount: 0, activity: .failed, hasPendingApproval: false), 2)
    }
}

extension DesktopCodexTaskMonitorTests {
    @MainActor
    func testActivePollingDetectsCompletionWithoutWatcherThenStopsWhenAllTasksFinish() async throws {
        let fixture = try MonitorFixture()
        let transcript = try fixture.writeTranscript(relativePath: "active.jsonl", contents: userMetadata + taskStarted(turnID: "one") + taskStarted(turnID: "two"))
        let started = expectation(description: "work recovered")
        let firstCompleted = expectation(description: "first completion")
        let allCompleted = expectation(description: "last completion")
        let idleScan = expectation(description: "no fast scan while idle")
        idleScan.isInverted = true
        let idle = LockedTestValue(false)
        let monitor = CodexDesktopTaskMonitor(
            sessionsRootURL: fixture.root,
            discoverTranscripts: { _ in
                if idle.get() { idleScan.fulfill() }
                return [transcript]
            },
            schedule: fixture.scheduler.schedule,
            onEvents: { events in
                for event in events {
                    switch event {
                    case .started(let id): if id.turnID == "two" { started.fulfill() }
                    case .completed(let id):
                        if id.turnID == "one" { firstCompleted.fulfill() }
                        if id.turnID == "two" { allCompleted.fulfill() }
                    }
                }
            }
        )
        monitor.start()
        defer { monitor.stop() }
        await fulfillment(of: [started], timeout: 2)
        try fixture.append(taskCompleted(turnID: "one"), to: transcript)
        await fulfillment(of: [firstCompleted], timeout: 2)
        try fixture.append(taskCompleted(turnID: "two"), to: transcript)
        await fulfillment(of: [allCompleted], timeout: 2)
        idle.update { $0 = true }
        await fulfillment(of: [idleScan], timeout: 1.3)
    }
}
