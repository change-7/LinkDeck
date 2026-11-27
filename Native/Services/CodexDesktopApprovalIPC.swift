import Darwin
import Foundation

enum CodexDesktopApprovalKind: Equatable, Sendable {
    case commandExecution
    case fileChange
    case permissions
    case elicitation
    case userInput
    case unsupported

    init?(method: String) {
        switch method {
        case "item/commandExecution/requestApproval": self = .commandExecution
        case "item/fileChange/requestApproval": self = .fileChange
        case "item/permissions/requestApproval": self = .permissions
        case "mcpServer/elicitation/request": self = .elicitation
        case "item/tool/requestUserInput": self = .userInput
        default:
            let normalized = method.lowercased()
            guard normalized.contains("requestapproval")
                    || normalized.contains("confirmation")
                    || normalized.contains("elicitation/request") else { return nil }
            self = .unsupported
        }
    }

    var title: String {
        switch self {
        case .commandExecution: "명령 실행 승인 필요"
        case .fileChange: "파일 변경 승인 필요"
        case .permissions: "권한 승인 필요"
        case .elicitation: "Codex 확인 필요"
        case .userInput: "Codex 답변 필요"
        case .unsupported: "Codex 확인 필요"
        }
    }
}

struct CodexDesktopPendingApproval: Equatable, Sendable {
    let conversationID: String
    let requestID: CodexIPCJSONValue
    let requestKey: String
    let method: String
    let title: String
    let detail: String
    let requestedPermissions: CodexIPCJSONValue?
    var decisions: [CodexApprovalDecision]? = nil

    var availableDecisions: [CodexApprovalDecision] {
        decisions ?? CodexApprovalDecision.options(method: method, params: requestedPermissions.map { ["permissions": $0] } ?? [:])
    }

    var kind: CodexDesktopApprovalKind? { CodexDesktopApprovalKind(method: method) }
    var numericRequestID: Int? { Int(requestID.stringValue ?? "") }
    var canRespond: Bool {
        guard kind != .userInput else { return false }
        if let decisions { return !decisions.isEmpty }
        guard kind != .elicitation && kind != .unsupported else { return false }
        guard kind == .permissions else { return true }
        if case .object? = requestedPermissions { return true }
        return false
    }
}

enum CodexDesktopApprovalIPC {
    // The read-only monitor owns its connection for the lifetime of one bridge run.
    actor Monitor {
        private let socketPath: String
        private let globalStateURL: URL
        private var client: CodexDesktopIPCClient?

        init(
            socketPath: String = NSHomeDirectory() + "/.codex/ipc/ipc.sock",
            globalStateURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/.codex-global-state.json")
        ) {
            self.socketPath = socketPath
            self.globalStateURL = globalStateURL
        }

        func pendingApprovals() throws -> [CodexDesktopPendingApproval] {
            do {
                let connection = try client ?? CodexDesktopIPCClient(socketPath: socketPath)
                let approvals = try connection.pendingApprovals(globalStateURL: globalStateURL)
                client = connection.canReuseConnection ? connection : nil
                return approvals
            } catch {
                client = nil
                throw error
            }
        }
    }

    static func respond(
        requestKey: String,
        decision: String,
        socketPath: String = NSHomeDirectory() + "/.codex/ipc/ipc.sock",
        globalStateURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/.codex-global-state.json")
    ) -> (success: Bool, message: String) {
        do {
            let client = try CodexDesktopIPCClient(socketPath: socketPath)
            let contexts = try client.approvalContexts(globalStateURL: globalStateURL)
            let matches = contexts.filter { $0.approval.requestKey == requestKey }
            guard contexts.count == 1, let context = matches.first else {
                return (false, "Codex 데스크톱의 승인 요청이 바뀌었거나 여러 건 대기 중입니다.")
            }
            guard let route = Self.route(for: context.approval, decision: decision) else {
                return (false, "현재 승인 요청 형식은 LinkDeck에서 처리할 수 없습니다.")
            }
            do {
                try client.sendFollowerRequest(
                    method: route.method,
                    params: route.params,
                    targetClientID: context.ownerClientID
                )
            } catch {
                return (false, "Codex가 승인 응답을 받지 못했습니다: \(error.localizedDescription)")
            }

            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
                let latest = try client.approvalContexts(globalStateURL: globalStateURL)
                if !latest.contains(where: { $0.approval.requestKey == requestKey }) {
                    return (true, decision == "decline" || decision == "cancel" ? "Codex 거부를 전송했습니다." : "Codex 승인을 전송했습니다.")
                }
            }
            return (false, "Codex 응답은 전송됐지만 승인 대기 상태가 해제됐는지 확인하지 못했습니다.")
        } catch {
            return (false, "Codex 데스크톱 승인 상태를 읽지 못했습니다: \(error.localizedDescription)")
        }
    }

    static func route(
        for approval: CodexDesktopPendingApproval,
        decision: String
    ) -> (method: String, params: [String: Any])? {
        guard let kind = approval.kind else { return nil }
        guard approval.canRespond else { return nil }
        guard let selected = approval.availableDecisions.first(where: { $0.option.id == decision }) else { return nil }
        let requestID = approval.requestID.foundationValue
        var params: [String: Any] = [
            "conversationId": approval.conversationID,
            "requestId": requestID
        ]
        switch kind {
        case .commandExecution:
            params["decision"] = selected.value.foundationValue
            return ("thread-follower-command-approval-decision", params)
        case .fileChange:
            params["decision"] = selected.value.foundationValue
            return ("thread-follower-file-approval-decision", params)
        case .permissions:
            let permissions: Any
            if decision == "accept" || decision == "acceptForSession" {
                guard let requested = approval.requestedPermissions,
                      case .object = requested else { return nil }
                permissions = requested.foundationValue
            } else {
                permissions = [String: Any]()
            }
            params["response"] = ["permissions": permissions, "scope": decision == "acceptForSession" ? "session" : "turn"]
            return ("thread-follower-permissions-request-approval-response", params)
        case .elicitation, .userInput, .unsupported:
            return nil
        }
    }

    static func approvals(
        in value: CodexIPCJSONValue?,
        conversationID: String
    ) -> [CodexDesktopPendingApproval] {
        guard case let .array(requests) = value else { return [] }
        return requests.compactMap { request in
            guard case let .object(fields) = request,
                  case let .string(method)? = fields["method"],
                  let kind = CodexDesktopApprovalKind(method: method),
                  let requestID = fields["id"] else { return nil }
            let params: [String: CodexIPCJSONValue]
            if case let .object(values)? = fields["params"] { params = values }
            else { params = [:] }
            let questions: [String]
            if kind == .userInput, case let .array(items)? = params["questions"] {
                questions = items.compactMap { item in
                    guard case let .object(fields) = item else { return nil }
                    return fields["question"]?.stringValue
                }
            } else {
                questions = []
            }
            let detail = (questions + [
                params["message"]?.stringValue,
                params["serverName"].map { "MCP 서버: \($0.stringValue ?? $0.description)" },
                params["reason"]?.stringValue,
                params["command"]?.stringValue,
                params["cwd"].map { "위치: \($0.stringValue ?? $0.description)" }
            ].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: "\n")
            let requestIDText = requestID.stringValue ?? requestID.description
            return CodexDesktopPendingApproval(
                conversationID: conversationID,
                requestID: requestID,
                requestKey: "desktop:\(conversationID):\(requestIDText):\(method)",
                method: method,
                title: kind.title,
                detail: detail.isEmpty ? "Codex 데스크톱에서 계속 진행하려면 확인이 필요합니다." : detail,
                requestedPermissions: params["permissions"],
                decisions: CodexApprovalDecision.options(method: method, params: params)
            )
        }
    }

    static func asyncQuestions(
        in turns: [CodexIPCJSONValue],
        conversationID: String
    ) -> [CodexDesktopPendingApproval] {
        var seen = Set<String>()
        return turns.compactMap { turn in
            guard case let .object(fields) = turn,
                  fields["status"] == .string("inProgress"),
                  case let .array(items)? = fields["items"] else { return nil }
            for item in items.reversed() {
                guard case let .object(message) = item else { continue }
                if message["type"] == .string("userMessage") ||
                    message["phase"] == .string("finalAnswer") { break }
                guard message["type"] == .string("agentMessage"),
                      message["delivery"] == .string("async"),
                      let id = message["id"]?.stringValue,
                      case let .array(questions)? = message["questions"] else { continue }
                let titles = questions.compactMap { question -> String? in
                    guard case let .object(fields) = question,
                          let title = fields["title"]?.stringValue, !title.isEmpty else { return nil }
                    return title
                }
                guard !titles.isEmpty, seen.insert(id).inserted else { break }
                return CodexDesktopPendingApproval(
                    conversationID: conversationID,
                    requestID: .string(id),
                    requestKey: "desktop:\(conversationID):async-question:\(id)",
                    method: "item/tool/requestUserInput",
                    title: CodexDesktopApprovalKind.userInput.title,
                    detail: titles.joined(separator: "\n"),
                    requestedPermissions: nil,
                    decisions: []
                )
            }
            return nil
        }
    }

    static func answeredAsyncQuestionIDs(in transcript: URL, pendingIDs: Set<String>) -> Set<String> {
        guard !pendingIDs.isEmpty, let file = try? FileHandle(forReadingFrom: transcript) else { return [] }
        defer { try? file.close() }
        let openTag = "<send_user_message_question_reply>"
        let closeTag = "</send_user_message_question_reply>"
        let replyMarker = Data(openTag.utf8)
        let questionMarker = Data("\"AgentMessage\"".utf8)
        var remaining = pendingIDs
        var answered = Set<String>()
        var offset = (try? file.seekToEnd()) ?? 0
        var partial = Data()

        // Read backwards only as far as the original question messages.
        while offset > 0 && !remaining.isEmpty {
            let count = min(offset, 64 * 1024)
            offset -= count
            guard (try? file.seek(toOffset: offset)) != nil,
                  var data = try? file.read(upToCount: Int(count)), data.count == Int(count) else { break }
            data.append(partial)
            let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
            partial = offset > 0 ? Data(lines[0]) : Data()
            for line in (offset > 0 ? lines.dropFirst() : lines[...]).reversed() {
                guard line.range(of: replyMarker) != nil || line.range(of: questionMarker) != nil,
                      let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      record["type"] as? String == "event_msg",
                      let payload = record["payload"] as? [String: Any],
                      payload["type"] as? String == "item_completed",
                      let item = payload["item"] as? [String: Any] else { continue }
                if item["type"] as? String == "AgentMessage",
                   item["delivery"] as? String == "async",
                   let id = item["id"] as? String {
                    remaining.remove(id)
                }
                if item["type"] as? String == "UserMessage",
                   let content = item["content"] as? [[String: Any]] {
                    for entry in content {
                        guard let rawText = entry["text"] as? String else { continue }
                        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard
                              text.hasPrefix(openTag), text.hasSuffix(closeTag),
                              let replies = try? JSONSerialization.jsonObject(with: Data(
                                text.dropFirst(openTag.count).dropLast(closeTag.count).utf8
                              )) as? [[String: Any]] else { continue }
                        for reply in replies {
                            guard let itemID = reply["questionItemId"] as? String,
                                  let parts = try? JSONSerialization.jsonObject(with: Data(itemID.utf8)) as? [Any],
                                  parts.count == 3, parts[0] as? String == "request_user_input_async",
                                  let id = parts[1] as? String, remaining.remove(id) != nil else { continue }
                            answered.insert(id)
                        }
                    }
                }
                if remaining.isEmpty { return answered }
            }
        }
        return answered
    }
}

private struct CodexDesktopApprovalContext {
    let ownerClientID: String
    let approval: CodexDesktopPendingApproval
}

private final class CodexDesktopIPCClient {
    private let socket: CodexUnixDomainSocket
    private var clientID = UUID().uuidString.lowercased()
    private(set) var canReuseConnection = true

    init(socketPath: String) throws {
        socket = try CodexUnixDomainSocket(path: socketPath)
        try initialize()
    }

    func pendingApprovals(globalStateURL: URL) throws -> [CodexDesktopPendingApproval] {
        try approvalContexts(globalStateURL: globalStateURL).map(\.approval)
    }

    func approvalContexts(globalStateURL: URL) throws -> [CodexDesktopApprovalContext] {
        let followedIDs = try followingConversationIDs()
        let pinnedIDs = Self.pinnedThreadIDs(from: globalStateURL)
        var seen = Set<String>()
        let conversationIDs = (followedIDs + pinnedIDs)
            .filter { seen.insert($0).inserted }
            .prefix(12)

        var contexts = [CodexDesktopApprovalContext]()
        for conversationID in conversationIDs {
            let snapshot: (ownerClientID: String, approvals: [CodexDesktopPendingApproval])
            do {
                snapshot = try followedSnapshot(
                    conversationID: conversationID,
                    sessionsRoot: globalStateURL.deletingLastPathComponent().appending(path: "sessions")
                )
            } catch {
                if followedIDs.contains(conversationID) { throw error }
                // A late response to an optional pinned thread can arrive in the next poll.
                canReuseConnection = false
                continue
            }
            contexts += snapshot.approvals.map {
                CodexDesktopApprovalContext(ownerClientID: snapshot.ownerClientID, approval: $0)
            }
        }
        let approvals = contexts.filter { $0.approval.kind != .userInput }
        return approvals.isEmpty ? contexts : approvals
    }

    func sendFollowerRequest(method: String, params: [String: Any], targetClientID: String) throws {
        let requestID = UUID().uuidString.lowercased()
        try socket.write([
            "type": "request",
            "requestId": requestID,
            "sourceClientId": clientID,
            "version": 1,
            "method": method,
            "params": params,
            "targetClientId": targetClientID,
            "timeoutMs": 5_000
        ])
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let message = try socket.readMessage(until: deadline)
            try answerDiscoveryIfNeeded(message)
            guard message.requestId == requestID else { continue }
            guard message.resultType == "success" else {
                throw CodexDesktopIPCError.requestFailed(message.error ?? "Codex IPC 요청이 거부되었습니다.")
            }
            return
        }
        throw CodexDesktopIPCError.timeout
    }

    private func initialize() throws {
        let requestID = UUID().uuidString.lowercased()
        try socket.write([
            "type": "request",
            "requestId": requestID,
            "sourceClientId": clientID,
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "linkdeck-approval-monitor"]
        ])
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let message = try socket.readMessage(until: deadline)
            try answerDiscoveryIfNeeded(message)
            guard message.requestId == requestID else { continue }
            guard message.resultType == "success" else {
                throw CodexDesktopIPCError.requestFailed(message.error ?? "Codex IPC 초기화가 거부되었습니다.")
            }
            clientID = message.result?.clientID ?? clientID
            return
        }
        throw CodexDesktopIPCError.timeout
    }

    private func followingConversationIDs() throws -> [String] {
        try socket.write([
            "type": "broadcast",
            "method": "thread-stream-following-status-requested",
            "sourceClientId": clientID,
            "version": 1,
            "params": [String: Any]()
        ])
        let deadline = Date().addingTimeInterval(0.6)
        var quietDeadline: Date?
        var sawStatus = false
        var followed = Set<String>()
        while Date() < (quietDeadline ?? deadline) {
            let readUntil = min(deadline, quietDeadline ?? deadline)
            let message: CodexIPCMessage
            do {
                message = try socket.readMessage(until: readUntil)
            } catch CodexDesktopIPCError.timeout {
                if sawStatus { break }
                throw CodexDesktopIPCError.timeout
            }
            try answerDiscoveryIfNeeded(message)
            guard message.type == "broadcast",
                  message.method == "thread-stream-following-changed",
                  message.params?.hostID == "local",
                  let conversationID = message.params?.conversationID,
                  let isFollowing = message.params?.following else { continue }
            sawStatus = true
            quietDeadline = Date().addingTimeInterval(0.075)
            if isFollowing { followed.insert(conversationID) }
            else { followed.remove(conversationID) }
        }
        return followed.sorted()
    }

    private func followedSnapshot(
        conversationID: String, sessionsRoot: URL
    ) throws -> (ownerClientID: String, approvals: [CodexDesktopPendingApproval]) {
        try sendFollowing(conversationID: conversationID, following: true)
        defer { try? sendFollowing(conversationID: conversationID, following: false) }
        let deadline = Date().addingTimeInterval(0.7)
        while Date() < deadline {
            let message = try socket.readMessage(until: deadline)
            try answerDiscoveryIfNeeded(message)
            guard message.type == "broadcast",
                  message.method == "thread-stream-state-changed",
                  message.params?.conversationID == conversationID,
                  message.params?.hostID == "local",
                  message.params?.change?.type == "snapshot",
                  let ownerClientID = message.sourceClientID,
                  let state = message.params?.change?.conversationState else { continue }
            let questions = CodexDesktopApprovalIPC.asyncQuestions(
                in: (state.turnHistory?.history?.entitiesByKey?.values.map { $0 } ?? []) + (state.turns ?? []),
                conversationID: conversationID
            )
            var answered = Set<String>()
            if !questions.isEmpty, let path = state.rolloutPath, path.hasPrefix("/") {
                let transcript = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                if transcript.pathExtension == "jsonl",
                   transcript.path.hasPrefix(sessionsRoot.resolvingSymlinksInPath().path + "/") {
                    answered = CodexDesktopApprovalIPC.answeredAsyncQuestionIDs(
                        in: transcript, pendingIDs: Set(questions.compactMap { $0.requestID.stringValue })
                    )
                }
            }
            return (ownerClientID, CodexDesktopApprovalIPC.approvals(
                in: state.requests, conversationID: conversationID
            ) + questions.filter { !answered.contains($0.requestID.stringValue ?? "") })
        }
        throw CodexDesktopIPCError.timeout
    }

    private func sendFollowing(conversationID: String, following: Bool) throws {
        try socket.write([
            "type": "broadcast",
            "method": "thread-stream-following-changed",
            "sourceClientId": clientID,
            "version": 1,
            "params": [
                "conversationId": conversationID,
                "hostId": "local",
                "following": following
            ]
        ])
    }

    private func answerDiscoveryIfNeeded(_ message: CodexIPCMessage) throws {
        guard message.type == "client-discovery-request", let requestID = message.requestId else { return }
        try socket.write([
            "type": "client-discovery-response",
            "requestId": requestID,
            "response": ["canHandle": false]
        ])
    }

    private static func pinnedThreadIDs(from url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = state["pinned-thread-ids"] as? [String] else { return [] }
        return ids
    }

}

private struct CodexIPCMessage: Decodable {
    let type: String?
    let requestId: String?
    let sourceClientID: String?
    let method: String?
    let resultType: String?
    let result: ResultPayload?
    let error: String?
    let params: Params?

    enum CodingKeys: String, CodingKey {
        case type, requestId, method, resultType, result, error, params
        case sourceClientID = "sourceClientId"
    }

    struct ResultPayload: Decodable {
        let clientID: String?
        enum CodingKeys: String, CodingKey { case clientID = "clientId" }
    }

    struct Params: Decodable {
        let conversationID: String?
        let hostID: String?
        let following: Bool?
        let change: Change?
        enum CodingKeys: String, CodingKey {
            case following, change
            case conversationID = "conversationId"
            case hostID = "hostId"
        }
    }

    struct Change: Decodable {
        let type: String?
        let conversationState: ConversationState?
    }

    struct ConversationState: Decodable {
        let requests: CodexIPCJSONValue?
        let rolloutPath: String?
        let turns: [CodexIPCJSONValue]?
        let turnHistory: TurnHistory?
    }

    struct TurnHistory: Decodable {
        let history: History?
    }

    struct History: Decodable {
        let entitiesByKey: [String: CodexIPCJSONValue]?
    }
}

enum CodexIPCJSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case object([String: CodexIPCJSONValue])
    case array([CodexIPCJSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    var stringValue: String? {
        if case let .string(value) = self { return value }
        if case let .integer(value) = self { return String(value) }
        return nil
    }

    var description: String { stringValue ?? "요청" }

    var foundationValue: Any {
        switch self {
        case let .object(values): values.mapValues(\.foundationValue)
        case let .array(values): values.map(\.foundationValue)
        case let .string(value): value
        case let .integer(value): value
        case let .number(value): value
        case let .bool(value): value
        case .null: NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values = [String: CodexIPCJSONValue]()
            for key in keyed.allKeys { values[key.stringValue] = try keyed.decode(CodexIPCJSONValue.self, forKey: key) }
            self = .object(values)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values = [CodexIPCJSONValue]()
            while !unkeyed.isAtEnd { values.append(try unkeyed.decode(CodexIPCJSONValue.self)) }
            self = .array(values)
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let int = try? value.decode(Int.self) { self = .integer(int) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported IPC JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .object(values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values { try container.encode(value, forKey: DynamicCodingKey(key)) }
        case let .array(values):
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        case let .string(value): var container = encoder.singleValueContainer(); try container.encode(value)
        case let .integer(value): var container = encoder.singleValueContainer(); try container.encode(value)
        case let .number(value): var container = encoder.singleValueContainer(); try container.encode(value)
        case let .bool(value): var container = encoder.singleValueContainer(); try container.encode(value)
        case .null: var container = encoder.singleValueContainer(); try container.encodeNil()
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
}

private enum CodexDesktopIPCError: Error, LocalizedError {
    case timeout
    case closed
    case invalidFrame
    case requestFailed(String)
    case socket(String)

    var errorDescription: String? {
        switch self {
        case .timeout: "Codex IPC 응답 시간이 초과되었습니다."
        case .closed: "Codex IPC 연결이 종료되었습니다."
        case .invalidFrame: "Codex IPC 데이터 형식이 올바르지 않습니다."
        case let .requestFailed(message), let .socket(message): message
        }
    }
}

private final class CodexUnixDomainSocket {
    private var descriptor: Int32 = -1
    private static let maximumFrameBytes = 256 * 1024 * 1024

    init(path: String) throws {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw CodexDesktopIPCError.socket(Self.errorText()) }
        descriptor = socket
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else {
            _ = Darwin.close(socket)
            descriptor = -1
            throw CodexDesktopIPCError.socket("Codex IPC 경로가 너무 깁니다.")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            pathPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                pathBytes.withUnsafeBufferPointer { source in
                    destination.update(from: source.baseAddress!, count: source.count)
                }
            }
        }
        let pathLength = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, pathLength)
            }
        }
        guard result == 0 else {
            let error = Self.errorText()
            _ = Darwin.close(socket)
            descriptor = -1
            throw CodexDesktopIPCError.socket(error)
        }
    }

    deinit {
        if descriptor >= 0 { _ = Darwin.close(descriptor) }
    }

    func write(_ object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        guard !payload.isEmpty, payload.count <= Self.maximumFrameBytes else {
            throw CodexDesktopIPCError.invalidFrame
        }
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        try writeAll(frame)
    }

    func readMessage(until deadline: Date) throws -> CodexIPCMessage {
        let header = try readExact(count: MemoryLayout<UInt32>.size, until: deadline)
        let rawLength = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let length = Int(UInt32(littleEndian: rawLength))
        guard length > 0, length <= Self.maximumFrameBytes else { throw CodexDesktopIPCError.invalidFrame }
        do {
            let payload = try readExact(count: length, until: deadline)
            return try JSONDecoder().decode(CodexIPCMessage.self, from: payload)
        } catch CodexDesktopIPCError.timeout {
            throw CodexDesktopIPCError.invalidFrame
        }
    }

    private func writeAll(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes in
                Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), data.count - offset, 0)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw CodexDesktopIPCError.socket(Self.errorText()) }
            offset += count
        }
    }

    private func readExact(count: Int, until deadline: Date) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw offset == 0 ? CodexDesktopIPCError.timeout : .invalidFrame }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(min(max(1, remaining * 1_000), Double(Int32.max)))
            let ready = Darwin.poll(&pollDescriptor, 1, milliseconds)
            if ready < 0, errno == EINTR { continue }
            if ready == 0 { throw offset == 0 ? CodexDesktopIPCError.timeout : .invalidFrame }
            guard ready > 0 else { throw CodexDesktopIPCError.socket(Self.errorText()) }
            let received = data.withUnsafeMutableBytes { bytes in
                Darwin.recv(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            if received < 0, errno == EINTR { continue }
            if received == 0 { throw CodexDesktopIPCError.closed }
            guard received > 0 else { throw CodexDesktopIPCError.socket(Self.errorText()) }
            offset += received
        }
        return data
    }

    private static func errorText() -> String { String(cString: strerror(errno)) }
}
