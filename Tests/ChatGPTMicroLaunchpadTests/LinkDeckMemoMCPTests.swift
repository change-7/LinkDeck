import XCTest
@testable import ChatGPTMicroLaunchpad

final class LinkDeckMemoMCPTests: XCTestCase {
    @MainActor
    func testCatalogAndCLIInput() async throws {
        let names = LinkDeckMemoMCP.tools.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["memo_search", "memo_read", "memo_create", "memo_create_folder", "memo_update", "memo_move_note", "memo_move_folder", "memo_append", "memo_add_checklist_item"])
        let response = await LinkDeckMemoMCP.response(to: try call(["path": "소스.md", "section": "소스", "item": "머스타드"]),
                                                     executable: URL(fileURLWithPath: "/bin/cat"))
        let result = try payload(response)
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: String]])
        let json = try XCTUnwrap(content.first?["text"])
        let sent = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        XCTAssertEqual(sent, ["command": "memo_add_checklist_item", "path": "소스.md", "section": "소스", "item": "머스타드"])
    }

    @MainActor
    func testRejectsInvalidArgumentsAndAbnormalChild() async throws {
        let invalid = await LinkDeckMemoMCP.response(to: try call(["command": "/bin/sh"]),
                                                    executable: URL(fileURLWithPath: "/bin/cat"))
        XCTAssertEqual(try payload(invalid)["isError"] as? Bool, true)
        let failed = await LinkDeckMemoMCP.response(to: try call(["path": "a.md", "section": "a", "item": "b"]),
                                                   executable: URL(fileURLWithPath: "/usr/bin/false"))
        XCTAssertEqual(try payload(failed)["isError"] as? Bool, true)
    }

    private func call(_ arguments: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                     "params": ["name": "memo_add_checklist_item", "arguments": arguments]])
    }

    private func payload(_ response: (status: Int, body: Data)?) throws -> [String: Any] {
        let body = try XCTUnwrap(response?.body)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(envelope["result"] as? [String: Any])
    }
}
