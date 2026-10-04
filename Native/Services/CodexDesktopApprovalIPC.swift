import Darwin
import Foundation

enum CodexDesktopApprovalKind: Equatable, Sendable {
    case commandExecution
    case fileChange
    case permissions
    case elicitation
    case unsupported

    init?(method: String) {
        switch method {
        case "item/commandExecution/requestApproval": self = .commandExecution
        case "item/fileChange/requestApproval": self = .fileChange
        case "item/permissions/requestApproval": self = .permissions
        case "mcpServer/elicitation/request": self = .elicitation
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

    var kind: CodexDesktopApprovalKind? { CodexDesktopApprovalKind(method: method) }
    var numericRequestID: Int? { Int(requestID.stringValue ?? "") }
    var canRespond: Bool {
        guard kind != .elicitation && kind != .unsupported else { return false }
        guard kind == .permissions else { return true }
        if case .object? = requestedPermissions { return true }
        return false
    }
}

enum CodexDesktopApprovalIPC {
    // Codex Desktop exposes no public attach-to-existing-thread approval API; this follows its private local IPC protocol.
    static func pendingApprovals(
        socketPath: String = NSHomeDirectory() + "/.codex/ipc/ipc.sock",
        globalStateURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/.codex-global-state.json")
    ) throws -> [CodexDesktopPendingApproval] {
        let client = try CodexDesktopIPCClient(socketPath: socketPath)
        return try client.pendingApprovals(globalStateURL: globalStateURL)
    }

    static func respond(
        requestKey: String,
        decision: String,
        socketPath: String = NSHomeDirectory() + "/.codex/ipc/ipc.sock",
        globalStateURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/.codex-global-state.json")
    ) -> (success: Bool, message: String) {
        guard decision == "accept" || decision == "decline" else {
            return (false, "지원하지 않는 승인 응답입니다.")
        }
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
                    return (true, decision == "accept" ? "Codex 승인을 전송했습니다." : "Codex 거부를 전송했습니다.")
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
        let requestID = approval.requestID.foundationValue
        var params: [String: Any] = [
            "conversationId": approval.conversationID,
            "requestId": requestID
        ]
        switch kind {
        case .commandExecution:
            params["decision"] = decision
            return ("thread-follower-command-approval-decision", params)
        case .fileChange:
            params["decision"] = decision
            return ("thread-follower-file-approval-decision", params)
        case .permissions:
            let permissions: Any
            if decision == "accept" {
                guard let requested = approval.requestedPermissions,
                      case .object = requested else { return nil }
                permissions = requested.foundationValue
            } else {
                permissions = [String: Any]()
            }
            params["response"] = ["permissions": permissions, "scope": "turn"]
            return ("thread-follower-permissions-request-approval-response", params)
        case .elicitation, .unsupported:
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
            let detail = [
                params["message"]?.stringValue,
                params["serverName"].map { "MCP 서버: \($0.stringValue ?? $0.description)" },
                params["reason"]?.stringValue,
                params["command"]?.stringValue,
                params["cwd"].map { "위치: \($0.stringValue ?? $0.description)" }
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            let requestIDText = requestID.stringValue ?? requestID.description
            return CodexDesktopPendingApproval(
                conversationID: conversationID,
                requestID: requestID,
                requestKey: "desktop:\(conversationID):\(requestIDText):\(method)",
                method: method,
                title: kind.title,
                detail: detail.isEmpty ? "Codex 데스크톱에서 계속 진행하려면 확인이 필요합니다." : detail,
                requestedPermissions: params["permissions"]
            )
        }
    }
}

private struct CodexDesktopApprovalContext {
    let ownerClientID: String
    let approval: CodexDesktopPendingApproval
}

private final class CodexDesktopIPCClient {
    private let socket: CodexUnixDomainSocket
    private var clientID = UUID().uuidString.lowercased()

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
                snapshot = try followedSnapshot(conversationID: conversationID)
            } catch {
                if followedIDs.contains(conversationID) { throw error }
                continue
            }
            contexts += snapshot.approvals.map {
                CodexDesktopApprovalContext(ownerClientID: snapshot.ownerClientID, approval: $0)
            }
        }
        return contexts
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

    private func followedSnapshot(conversationID: String) throws -> (ownerClientID: String, approvals: [CodexDesktopPendingApproval]) {
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
                  let ownerClientID = message.sourceClientID else { continue }
            let approvals = CodexDesktopApprovalIPC.approvals(
                in: message.params?.change?.conversationState?.requests,
                conversationID: conversationID
            )
            return (ownerClientID, approvals)
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
        let payload = try readExact(count: length, until: deadline)
        return try JSONDecoder().decode(CodexIPCMessage.self, from: payload)
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
            guard remaining > 0 else { throw CodexDesktopIPCError.timeout }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(min(max(1, remaining * 1_000), Double(Int32.max)))
            let ready = Darwin.poll(&pollDescriptor, 1, milliseconds)
            if ready < 0, errno == EINTR { continue }
            if ready == 0 { throw CodexDesktopIPCError.timeout }
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
