import AppKit
import CryptoKit

struct AppAPIManifest: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let name: String
    let transport: String
    let arguments: [String]
    let tools: [String]

    var prefix: String { "linkdeck_app_" + id + "__" }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw invalid("파일은 64KB 이하여야 합니다.") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["schemaVersion", "id", "name", "transport", "arguments", "tools"]) else {
            throw invalid("지원하는 필드만 포함하세요: schemaVersion, id, name, transport, arguments, tools.")
        }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        func identifier(_ value: String, limit: Int) -> Bool {
            !value.isEmpty && value.utf8.count <= limit && value.allSatisfy {
                $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_")
            }
        }
        guard manifest.schemaVersion == 1, manifest.transport == "mcp_stdio",
              identifier(manifest.id, limit: 16), !manifest.name.isEmpty, manifest.name.count <= 100,
              manifest.arguments.count <= 32,
              manifest.arguments.allSatisfy({ $0.utf8.count <= 1024 && !$0.contains("\0") }),
              !manifest.tools.isEmpty, manifest.tools.count <= 100,
              Set(manifest.tools).count == manifest.tools.count,
              manifest.tools.allSatisfy({ identifier($0, limit: 32) }) else {
            throw invalid("버전·연결 방식·식별자·인수·도구 목록을 확인하세요.")
        }
        return manifest
    }

    static func invalid(_ message: String) -> NSError {
        NSError(domain: "LinkDeck.AppAPI", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "앱 API 연동: " + message])
    }

    static let authoringInstructions = """
    이 macOS 앱을 LinkDeck의 앱 API 연동 기능과 연결해 주세요.

    1. 빌드 결과의 앱.app/Contents/Resources/linkdeck.json에 아래 형식의 UTF-8 JSON을 포함하세요. 소스 파일만 추가하지 말고 앱 번들의 리소스로 복사하세요.
    2. schemaVersion은 1, transport는 mcp_stdio입니다. 현재 지원하는 방식은 MCP 표준 입출력이며 HTTP/REST는 지원하지 않습니다.
    3. id는 앱마다 고유하고 유지되는 소문자 영문·숫자·밑줄 1~16자, name은 표시 이름입니다.
    4. arguments는 앱 번들 자체의 실행 파일에 전달할 인수 배열입니다. 다른 실행 파일 경로나 셸 명령을 넣지 마세요. LinkDeck은 셸을 거치지 않고 번들의 실행 파일을 실행합니다.
    5. tools에는 공개할 MCP 도구 이름만 넣으세요. 각 이름은 소문자 영문·숫자·밑줄 1~32자이며 실제 tools/list의 이름과 일치해야 합니다.
    6. MCP 모드에서 initialize, notifications/initialized, tools/list, tools/call을 구현하세요. stdin/stdout은 줄 단위 JSON-RPC 2.0에만 사용하고 로그는 stderr로 보내세요. 각 요청은 10초 안에 응답하세요. 긴 작업은 작업 ID를 즉시 반환하고 별도 상태 조회 도구를 제공하세요.
    7. tools/list에 정확한 description, inputSchema와 annotations를 제공하세요. 페이지 분할 시 nextCursor를 지원하세요. LinkDeck은 도구 이름 앞에 linkdeck_app_<id>__를 붙여 ChatGPT에 공개합니다.
    8. 비밀 키·토큰은 JSON에 넣지 마세요. 인증은 해당 앱에서 먼저 설정하고 안전하게 저장하세요. LinkDeck의 OpenAI 키는 전달되지 않습니다.
    9. LinkDeck에서 앱을 버튼에 등록한 뒤 최초 API 연결을 승인하면 사용할 수 있습니다. JSON 내용이나 앱 위치가 바뀌면 다시 승인해야 합니다. 설정 → ChatGPT 연결 → 등록된 앱 API에서 확인하세요. 연결 중 앱을 추가했다면 ChatGPT 도구 목록을 새로고침하세요.

    예시 (도구 이름은 실제 앱에 맞게 바꾸세요):
    {
      "schemaVersion": 1,
      "id": "my_transcriber",
      "name": "My Transcriber",
      "transport": "mcp_stdio",
      "arguments": ["--mcp"],
      "tools": ["start_transcription", "get_transcription_status"]
    }
    """
}

@MainActor
struct RegisteredAppAPI: Identifiable {
    let bundleID: String
    let appURL: URL
    let executable: URL
    let manifest: AppAPIManifest
    let approvalKey: String
    nonisolated var id: String { bundleID }
    var approved: Bool { UserDefaults.standard.string(forKey: "linkdeck.app-api." + bundleID) == approvalKey }

    static func load(appURL: URL) throws -> Self? {
        let file = appURL.appendingPathComponent("Contents/Resources/linkdeck.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard file.resolvingSymlinksInPath().path.hasPrefix(appURL.resolvingSymlinksInPath().path + "/"),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536 else {
            throw AppAPIManifest.invalid("안내 파일은 앱 번들 안에 있는 64KB 이하 파일이어야 합니다.")
        }
        guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path),
              executable.resolvingSymlinksInPath().path.hasPrefix(appURL.resolvingSymlinksInPath().path + "/") else {
            throw AppAPIManifest.invalid("앱 실행 파일이 유효하지 않습니다.")
        }
        let data = try Data(contentsOf: file)
        let manifest = try AppAPIManifest.decode(data)
        let digest = SHA256.hash(data: data + Data(appURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self(bundleID: bundleID, appURL: appURL, executable: executable, manifest: manifest, approvalKey: digest)
    }

    static func discover(buttons: [LinkDeckMCPButton]) -> [Self] {
        let ids = Set(buttons.filter { $0.action.kind == .app || $0.action.kind == .appFolder }.map { $0.action.value })
        return ids.sorted().compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return try? load(appURL: url)
        }
    }

    func approve() {
        let alert = NSAlert()
        alert.messageText = manifest.name + " API를 LinkDeck에 연결할까요?"
        alert.informativeText = "이 앱을 MCP 모드로 실행하고 ChatGPT에 다음 기능을 공개합니다.\n" + manifest.tools.joined(separator: ", ") + "\n앱: " + appURL.path
        alert.addButton(withTitle: "연결 허용")
        alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(approvalKey, forKey: "linkdeck.app-api." + bundleID)
        }
    }
}

@MainActor
final class AppAPIMCPBridge {
    private var clients: [String: StableWhisperMCPClient] = [:]
    private var failures: [String: String] = [:]

    func stop() async {
        for client in clients.values { await client.stop() }
        clients.removeAll()
    }

    func response(to data: Data, apps: [RegisteredAppAPI], fallback: () async -> (status: Int, body: Data)) async -> (status: Int, body: Data) {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = request["id"], let method = request["method"] as? String else { return await fallback() }
        let approved = apps.filter(\.approved)
        let keys = Set(approved.map(\.approvalKey))
        for key in Array(clients.keys) where !keys.contains(key) { await clients.removeValue(forKey: key)?.stop() }
        let params = request["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        guard method == "tools/list" || (method == "tools/call" && name.hasPrefix("linkdeck_app_")) else { return await fallback() }
        func encoded(_ object: [String: Any]) -> (Int, Data) { (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data()) }
        func client(_ app: RegisteredAppAPI) -> StableWhisperMCPClient {
            if let saved = clients[app.approvalKey] { return saved }
            let chatView = app.bundleID == "com.pdg.ChatGPTSplitView" && app.manifest.id == "chat_view"
            let created = StableWhisperMCPClient(idleTimeout: .seconds(chatView ? 600 : 300), chatView: chatView)
            clients[app.approvalKey] = created
            return created
        }
        do {
            if method == "tools/call", name == "linkdeck_app_api_status" {
                guard (params["arguments"] as? [String: Any] ?? [:]).isEmpty else { throw AppAPIManifest.invalid("상태 조회에는 인수가 필요하지 않습니다.") }
                let statuses = apps.map { app -> [String: Any] in
                    ["name": app.manifest.name, "id": app.manifest.id, "approved": app.approved,
                     "error": failures[app.bundleID] ?? "", "tools": app.manifest.tools]
                }
                let text = String(decoding: try JSONSerialization.data(withJSONObject: ["apps": statuses]), as: UTF8.self)
                return encoded(["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": text]]]])
            }
            if method == "tools/list" {
                var local = try JSONSerialization.jsonObject(with: await fallback().body) as? [String: Any] ?? [:]
                var result = local["result"] as? [String: Any] ?? [:]
                var tools = result["tools"] as? [[String: Any]] ?? []
                tools.append(["name": "linkdeck_app_api_status", "description": "Read registered app API approvals and discovery errors. Does not execute app tools.", "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false], "annotations": ["readOnlyHint": true]])
                let counts = Dictionary(grouping: approved, by: { $0.manifest.id }).mapValues(\.count)
                for app in approved {
                    guard counts[app.manifest.id] == 1 else { failures[app.bundleID] = "중복된 앱 API id입니다."; continue }
                    do {
                    var appTools: [[String: Any]] = []
                    var cursor: String?
                    for page in 0..<20 {
                        let upstream = try await client(app).request(JSONSerialization.data(withJSONObject: ["method": "tools/list", "params": cursor.map { ["cursor": $0] } ?? [:]]), executable: app.executable, arguments: app.manifest.arguments)
                        let reply = try JSONSerialization.jsonObject(with: upstream) as? [String: Any]
                        guard let remote = reply?["result"] as? [String: Any], let entries = remote["tools"] as? [[String: Any]] else { throw AppAPIManifest.invalid("\(app.manifest.name)의 도구 목록을 읽지 못했습니다.") }
                        for var tool in entries {
                            guard let remoteName = tool["name"] as? String, app.manifest.tools.contains(remoteName) else { continue }
                            guard let schema = tool["inputSchema"] as? [String: Any], schema["type"] as? String == "object" else {
                                throw AppAPIManifest.invalid("\(remoteName)의 inputSchema는 object여야 합니다.")
                            }
                            tool["name"] = app.manifest.prefix + remoteName
                            tool["description"] = app.manifest.name + " via LinkDeck. " + (tool["description"] as? String ?? "")
                            appTools.append(tool)
                        }
                        cursor = remote["nextCursor"] as? String
                        if cursor == nil { break }
                        if page == 19 { throw AppAPIManifest.invalid("도구 목록은 최대 20페이지까지 지원합니다.") }
                    }
                    guard Set(appTools.compactMap { $0["name"] as? String }) == Set(app.manifest.tools.map { app.manifest.prefix + $0 }) else {
                        throw AppAPIManifest.invalid("JSON에 선언된 도구와 실제 MCP 도구 목록이 일치하지 않습니다.")
                    }
                    tools.append(contentsOf: appTools)
                    failures.removeValue(forKey: app.bundleID)
                    } catch { failures[app.bundleID] = error.localizedDescription }
                }
                result["tools"] = tools
                local["result"] = result
                return encoded(local)
            }
            let matches = approved.filter { name.hasPrefix($0.manifest.prefix) }
            guard matches.count == 1, let app = matches.first,
                  app.manifest.tools.contains(String(name.dropFirst(app.manifest.prefix.count))),
                  params["arguments"] == nil || params["arguments"] is [String: Any] else {
                throw AppAPIManifest.invalid("승인된 앱 도구와 올바른 인수를 사용하세요.")
            }
            let upstream = try await client(app).request(JSONSerialization.data(withJSONObject: ["method": "tools/call", "params": ["name": String(name.dropFirst(app.manifest.prefix.count)), "arguments": params["arguments"] ?? [:]]]), executable: app.executable, arguments: app.manifest.arguments)
            var reply = try JSONSerialization.jsonObject(with: upstream) as? [String: Any] ?? [:]
            reply["id"] = id
            return encoded(reply)
        } catch {
            if method == "tools/list" { return await fallback() }
            return encoded(["jsonrpc": "2.0", "id": id, "result": ["isError": true, "content": [["type": "text", "text": error.localizedDescription]]]])
        }
    }
}
