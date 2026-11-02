import Foundation

@MainActor
final class LinkDeckInstructionsGate {
    private var currentRevision: UUID?
    private var receipts: Set<String> = []
    private let readers = ["linkdeck_get_custom_instructions", "linkdeck_list_buttons"]

    func response(to data: Data, instructions: CustomInstructions, revision: UUID,
                  forward: (Data) async -> (status: Int, body: Data)) async -> (status: Int, body: Data) {
        if currentRevision != revision {
            currentRevision = revision
            receipts.removeAll()
        }
        guard var request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else { return invalidRequest() }
        if request["id"] == nil, method.hasPrefix("notifications/") { return (202, Data()) }
        guard let id = request["id"], id is String || id is NSNumber else { return invalidRequest() }
        var params = request["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        var forwarded = data
        if method == "tools/call", !readers.contains(name) {
            guard var arguments = params["arguments"] as? [String: Any],
                  let receipt = arguments.removeValue(forKey: "instructions_receipt") as? String,
                  receipts.remove(receipt) != nil else {
                let text = "실행하지 않았습니다. 먼저 linkdeck_get_custom_instructions 또는 linkdeck_list_buttons로 최신 사용자 지정 지침을 읽고, 응답의 instructions_receipt를 이번 호출의 인수로 전달하세요. 확인값은 한 번만 사용할 수 있습니다. 인수가 보이지 않으면 연결 도구 목록을 새로고침하세요."
                return (200, encode(["jsonrpc": "2.0", "id": id, "result": ["isError": true,
                    "content": [["type": "text", "text": text]]]]))
            }
            params["arguments"] = arguments
            request["params"] = params
            forwarded = encode(request)
        }
        let response = await forward(forwarded)
        guard response.status == 200,
              var object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              var result = object["result"] as? [String: Any] else { return response }
        if method == "initialize" {
            result["instructions"] = "Before EVERY tool call, read linkdeck_get_custom_instructions or linkdeck_list_buttons and pass the returned single-use instructions_receipt argument. Calls without a fresh receipt are blocked. Saved changes invalidate outstanding receipts. " + (result["instructions"] as? String ?? "")
        } else if method == "tools/list", let tools = result["tools"] as? [[String: Any]] {
            result["tools"] = tools.map { definition in
                var tool = definition
                let toolName = tool["name"] as? String ?? ""
                if readers.contains(toolName) { return tool }
                var schema = tool["inputSchema"] as? [String: Any] ?? ["type": "object"]
                var properties = schema["properties"] as? [String: Any] ?? [:]
                properties["instructions_receipt"] = ["type": "string", "description": "Required single-use receipt from a fresh LinkDeck custom-instructions or button-list read. Read and follow those preferences before this call."]
                schema["properties"] = properties
                schema["required"] = (schema["required"] as? [String] ?? []).filter { $0 != "instructions_receipt" } + ["instructions_receipt"]
                tool["inputSchema"] = schema
                tool["description"] = "First read LinkDeck custom instructions or list buttons; pass the returned single-use instructions_receipt. " + (tool["description"] as? String ?? "")
                return tool
            }
        } else if method == "tools/call", readers.contains(name), currentRevision == revision,
                  (params["arguments"] == nil || (params["arguments"] as? [String: Any])?.isEmpty == true),
                  result["isError"] as? Bool != true,
                  var content = result["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String,
                  var payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            // Bound outstanding reads without letting one client unlock another client's calls.
            if receipts.count >= 256 { receipts.removeAll() }
            let receipt = UUID().uuidString + UUID().uuidString
            receipts.insert(receipt)
            var preferences = instructions.payload
            preferences["instructions_receipt"] = receipt
            preferences["receipt_usage"] = "Read these preferences before each tool call. Pass instructions_receipt as an argument once; saved changes and server restarts invalidate it. Permissions and approvals still apply."
            if name == "linkdeck_list_buttons" { payload["custom_instructions"] = preferences }
            else { payload = preferences }
            content[0]["text"] = String(decoding: encode(payload), as: UTF8.self)
            result["content"] = content
        }
        object["result"] = result
        return (response.status, encode(object))
    }

    private func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func invalidRequest() -> (status: Int, body: Data) {
        (200, encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid Request"]]))
    }
}
