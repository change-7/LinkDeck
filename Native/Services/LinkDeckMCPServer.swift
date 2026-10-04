import Foundation
import Network

struct LinkDeckHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case incomplete
        case rejected(Int)
        case complete(LinkDeckHTTPRequest)
    }

    static func parse(_ data: Data) -> ParseResult {
        guard data.count <= 1_048_576 else { return .rejected(413) }
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16_384 ? .rejected(431) : .incomplete
        }
        guard separator.lowerBound <= 16_384,
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return .rejected(400) }
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3, parts[2] == "HTTP/1.1" else { return .rejected(400) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .rejected(400) }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, headers[key] == nil else { return .rejected(400) }
            headers[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil,
              let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= 1_000_000 else { return .rejected(400) }
        let body = Data(data[separator.upperBound...])
        guard body.count >= length else { return .incomplete }
        guard body.count == length else { return .rejected(400) }
        return .complete(LinkDeckHTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: body))
    }

    func authorizationStatus(token: String) -> Int? {
        guard headers["authorization"] == "Bearer " + token else { return 401 }
        guard headers["origin"] == nil else { return 403 }
        guard let host = headers["host"], host.hasPrefix("127.0.0.1:") else { return 403 }
        guard path == "/mcp" else { return 404 }
        guard method == "POST" else { return 405 }
        guard headers["content-type"]?.lowercased().hasPrefix("application/json") == true else { return 415 }
        if let version = headers["mcp-protocol-version"],
           !["2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"].contains(version) { return 400 }
        return nil
    }
}

@MainActor
final class LinkDeckMCPServer {
    let token = UUID().uuidString + UUID().uuidString
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private var startup: CheckedContinuation<URL, any Error>?
    var handle: ((Data) -> (status: Int, body: Data))?
    var onFailure: (() -> Void)?
    var onRequestRejected: ((String) -> Void)?

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = self.listener?.port,
                           let url = URL(string: "http://127.0.0.1:\(port.rawValue)/mcp") {
                            self.startup?.resume(returning: url)
                            self.startup = nil
                        }
                    case .failed(let error):
                        self.startup?.resume(throwing: error)
                        self.startup = nil
                        self.onFailure?()
                        self.stop()
                    case .cancelled:
                        self.startup?.resume(throwing: CancellationError())
                        self.startup = nil
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        startup?.resume(throwing: CancellationError())
        startup = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        for timeout in timeouts.values { timeout.cancel() }
        timeouts.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, connections.count < 16 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        timeouts[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.close(id)
        }
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var next = buffer
                if let data { next.append(data) }
                switch LinkDeckHTTPRequest.parse(next) {
                case .incomplete:
                    if complete || error != nil { self.close(id) }
                    else { self.receive(connection, id: id, buffer: next) }
                case .rejected(let status):
                    let head = String(decoding: next.prefix(16_384), as: UTF8.self).components(separatedBy: "\r\n\r\n")[0]
                    let framing = head.components(separatedBy: "\r\n").filter {
                        let line = $0.lowercased()
                        return line.hasPrefix("transfer-encoding:") || line.hasPrefix("content-length:")
                    }.joined(separator: ", ")
                    self.onRequestRejected?("HTTP \(status): \(framing)")
                    self.respond(connection, id: id, status: status, body: Data())
                case .complete(let request):
                    if let status = request.authorizationStatus(token: self.token) {
                        self.onRequestRejected?("HTTP \(status), MCP \(request.headers["mcp-protocol-version"] ?? "unspecified")")
                        self.respond(connection, id: id, status: status, body: Data())
                    } else if let handle = self.handle {
                        let response = handle(request.body)
                        self.respond(connection, id: id, status: response.status, body: response.body)
                    } else { self.respond(connection, id: id, status: 503, body: Data()) }
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, id: UUID, status: Int, body: Data) {
        let labels = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 413: "Content Too Large",
                      415: "Unsupported Media Type", 431: "Request Header Fields Too Large", 503: "Service Unavailable"]
        var response = Data("HTTP/1.1 \(status) \(labels[status] ?? "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        timeouts.removeValue(forKey: id)?.cancel()
    }
}
