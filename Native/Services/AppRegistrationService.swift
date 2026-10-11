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
            completion(.success(RegisteredApplication(name: name, bundleIdentifier: bundleIdentifier, iconData: iconData(for: url))))
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

    static func iconData(for appURL: URL) -> Data? {
        guard let tiff = NSWorkspace.shared.icon(forFile: appURL.path).tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return SmartphoneIconData.normalizedPNGData(from: png)
    }
}

struct RegisteredApplication {
    let name: String
    let bundleIdentifier: String
    var iconData: Data? = nil

    func applyIcon(to button: inout SmartphoneButton, isSecondAction: Bool) {
        if isSecondAction {
            button.secondCustomIconData = iconData
            button.secondSymbol = "app"
        } else {
            button.customIconData = iconData
            button.symbol = "app"
            button.usesActionIconForSymbol = true
        }
    }

    func applyIcon(to shortcut: inout SmartphoneFolderShortcut, isSecondAction: Bool) {
        if isSecondAction {
            shortcut.secondCustomIconData = iconData
            shortcut.secondSymbol = "app"
        } else {
            shortcut.customIconData = iconData
            shortcut.symbol = "app"
        }
    }
}

enum AppRegistrationError: LocalizedError {
    case invalidApplication

    var errorDescription: String? { "유효한 macOS 앱을 선택하세요." }
}
