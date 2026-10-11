import AppKit
import UniformTypeIdentifiers

@MainActor
enum AppRegistrationService {
    static func chooseApplication(completion: @escaping (Result<RegisteredApplication, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "실행할 앱 선택"
        panel.prompt = "앱 등록"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else {
                completion(.failure(AppRegistrationError.invalidApplication))
                return
            }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            do {
                if let api = try RegisteredAppAPI.load(appURL: url), !api.approved { api.approve() }
            } catch {
                let alert = NSAlert()
                alert.messageText = "앱 API 안내 파일을 읽지 못했습니다."
                alert.informativeText = error.localizedDescription + "\n앱 실행 버튼은 등록됩니다."
                alert.runModal()
            }
            completion(.success(RegisteredApplication(name: name, bundleIdentifier: bundleIdentifier)))
        }
    }

    static func displayName(for bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func icon(for bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct RegisteredApplication {
    let name: String
    let bundleIdentifier: String
}

enum AppRegistrationError: LocalizedError {
    case invalidApplication

    var errorDescription: String? { "유효한 macOS 앱을 선택하세요." }
}
