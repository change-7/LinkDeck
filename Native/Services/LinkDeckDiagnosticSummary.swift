import Foundation

struct LinkDeckDiagnosticSummary: Sendable {
    struct Event: Decodable {
        let time: Date
        let event: String
        let request_id: String?
        let method: String?
        let tool: String?
        let outcome: String?
        let elapsed_ms: Int?
        let app: String?
        let task_id: String?
        var code: Int? = nil
    }

    struct Call: Identifiable, Sendable {
        let id: String
        let time: Date
        let tool: String
        let outcome: String
        let elapsedMS: Int?
        let appSteps: [Step]
        let chatViewTask: Bool
        let queueMS: Int?
        let executionMS: Int?
    }

    struct Step: Sendable {
        let label: String
        let outcome: String?
        let code: Int?
        let elapsedMS: Int
    }

    struct Tool: Identifiable, Sendable {
        let id: String
        let count: Int
        let failures: Int
        let p50: Int?
        let p95: Int?
        let maximum: Int?
        let latestSpike: Bool
    }

    let coverage: ClosedRange<Date>?
    let calls: [Call]
    let tools: [Tool]
    let reconnects: Int

    init(events: [Event], now: Date) {
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        // ISO 8601 rounds to milliseconds, so a just-recorded event can round past now.
        let upperBound = now.addingTimeInterval(0.001)
        let recent = events.filter { $0.time >= cutoff && $0.time <= upperBound }
        let dates = recent.map(\.time)
        coverage = dates.min().flatMap { first in dates.max().map { first...$0 } }
        reconnects = recent.filter { $0.event == "tunnel.reconnecting" }.count

        let requestEvents = recent.filter {
            ["request.started", "request.timeout", "request.completed", "response.sent", "app.request.completed", "chat_view.task"].contains($0.event)
        }
        let taskEvents = Dictionary(grouping: recent.filter { $0.task_id != nil }) { $0.task_id }
        let byRequest = Dictionary(grouping: requestEvents) { $0.request_id }
        calls = byRequest.compactMap { id, entries in
            guard let id, let call = entries.first(where: {
                ["request.started", "request.completed"].contains($0.event) && $0.method == "tools/call"
            }),
                  let tool = call.tool else { return nil }
            let completion = entries.last { $0.event == "request.completed" }
            let outcome: String
            if entries.contains(where: { $0.event == "request.timeout" }) {
                outcome = completion?.outcome == "late_response" ? "timeout · late_response" : "timeout"
            } else if entries.contains(where: { $0.event == "response.sent" && $0.outcome == "send_failed" }) {
                outcome = "send_failed"
            } else {
                outcome = completion.map { $0.outcome ?? "unknown" } ?? "unknown"
            }
            let steps = entries.compactMap { entry -> Step? in
                guard entry.event == "app.request.completed", let elapsed = entry.elapsed_ms else { return nil }
                let label = [entry.app, entry.tool ?? entry.method].compactMap { $0 }.joined(separator: " · ")
                return Step(label: label, outcome: entry.outcome, code: entry.code, elapsedMS: elapsed)
            }
            let taskID = entries.first { $0.event == "chat_view.task" }?.task_id
            let stages = taskID.flatMap { taskEvents[$0] } ?? []
            return Call(id: id, time: call.time, tool: tool, outcome: outcome, elapsedMS: completion?.elapsed_ms,
                        appSteps: steps, chatViewTask: taskID != nil,
                        queueMS: stages.last { $0.event == "chat_view.queue" }?.elapsed_ms,
                        executionMS: stages.last { $0.event == "chat_view.execution" }?.elapsed_ms)
        }.sorted {
            $0.time == $1.time ? $0.id < $1.id : $0.time > $1.time
        }

        let completed = calls.filter { $0.outcome != "unknown" }
        tools = Dictionary(grouping: completed, by: \.tool).map { name, rows in
            let times = rows.compactMap(\.elapsedMS)
            let baseline = Array(times.dropFirst().prefix(20))
            let baselineP95 = Self.percentile(baseline, 0.95) ?? 0
            let latestSpike = baseline.count >= 5 && baselineP95 > 0
                && Double(times.first ?? 0) >= 2 * Double(baselineP95)
            let failures = rows.filter { $0.outcome != "success" && $0.outcome != "accepted" }.count
            return Tool(id: name, count: rows.count, failures: failures, p50: Self.percentile(times, 0.50),
                        p95: Self.percentile(times, 0.95), maximum: times.max(), latestSpike: latestSpike)
        }.sorted { $0.id < $1.id }
    }

    struct Comparison: Identifiable {
        let id: String
        let beforeCount: Int
        let afterCount: Int
        let beforeP95: Int?
        let afterP95: Int?
    }

    func compare(at change: Date) -> [Comparison] {
        let day: TimeInterval = 86_400
        let window = change.addingTimeInterval(-day)..<change.addingTimeInterval(day)
        let samples = calls.filter { window.contains($0.time) && $0.outcome == "success" }
        return Dictionary(grouping: samples, by: \.tool).map { tool, rows in
            let before = rows.filter { $0.time < change }.compactMap(\.elapsedMS)
            let after = rows.filter { $0.time >= change }.compactMap(\.elapsedMS)
            return Comparison(id: tool, beforeCount: before.count, afterCount: after.count,
                              beforeP95: Self.percentile(before, 0.95), afterP95: Self.percentile(after, 0.95))
        }.sorted { $0.id < $1.id }
    }

    private static func percentile(_ times: [Int], _ fraction: Double) -> Int? {
        guard !times.isEmpty else { return nil }
        return times.sorted()[Int(ceil(Double(times.count) * fraction)) - 1]
    }

}
