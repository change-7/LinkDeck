import Foundation
import Security

enum LinkDeckTunnelKeychain {
    private static var query: [String: Any] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.pdg.chatgpt-micro-launchpad"
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: bundleID + ".chatgpt-tunnel",
                kSecAttrAccount as String: "runtime-api-key"]
    }

    static func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "LinkDeck.Keychain", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "저장된 API 키를 읽을 수 없습니다. 키를 다시 입력하세요."])
        }
        return key
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: "LinkDeck.Keychain", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "키체인 접근 실패 (\(status)). macOS 권한 안내를 확인하세요."])
        }
    }
}
