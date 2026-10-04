import AppKit

enum BrowserURLError: LocalizedError {
    case unsupportedBrowser
    case navigationFailed
    case automationDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedBrowser:
            "현재 탭 열기는 Safari, Chrome, Whale, Edge, Brave, Chromium에서 지원합니다. 기본 브라우저를 확인하세요."
        case .navigationFailed:
            "브라우저의 현재 탭에서 웹페이지를 열지 못했습니다."
        case .automationDenied:
            "시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 LinkDeck의 브라우저 제어를 허용하세요."
        }
    }
}

@MainActor
enum BrowserURLRunner {
    static func openInCurrentTab(_ url: URL) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier,
              let source = currentTabScript(url: url, browserBundleID: bundleID) else {
            throw BrowserURLError.unsupportedBrowser
        }
        guard let script = NSAppleScript(source: source) else {
            throw BrowserURLError.navigationFailed
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                throw BrowserURLError.automationDenied
            }
            throw BrowserURLError.navigationFailed
        }
    }

    static func currentTabScript(url: URL, browserBundleID: String) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let address = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        if browserBundleID == "com.apple.Safari" {
            return """
            tell application id "com.apple.Safari"
                if (count of windows) = 0 then make new document
                set URL of current tab of front window to "\(address)"
                activate
            end tell
            """
        }
        guard [
            "com.google.Chrome", "com.naver.Whale", "com.microsoft.edgemac",
            "com.brave.Browser", "org.chromium.Chromium"
        ].contains(browserBundleID) else { return nil }
        return """
        tell application id "\(browserBundleID)"
            if (count of windows) = 0 then make new window
            set URL of active tab of front window to "\(address)"
            activate
        end tell
        """
    }
}
