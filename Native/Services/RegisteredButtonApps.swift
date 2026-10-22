import Foundation

enum RegisteredButtonApps {
    static func identifiers(macPages: [LaunchPage], phonePages: [SmartphonePage], terminationAllowedOnly: Bool = false) -> Set<String> {
        var actions: [PadAction] = []
        func collect(_ action: PadAction) { actions.append(action) }
        for page in macPages {
            for pad in page.pads {
                collect(pad.action)
                if let second = pad.secondAction { collect(second) }
            }
        }
        for page in phonePages {
            for button in page.buttons {
                collect(button.action)
                collect(button.longPressAction)
                if let second = button.secondAction { collect(second) }
                for shortcut in button.folderShortcuts {
                    collect(shortcut.action)
                    collect(shortcut.longPressAction)
                    if let second = shortcut.secondAction { collect(second) }
                }
            }
        }
        return identifiers(actions: actions, terminationAllowedOnly: terminationAllowedOnly)
    }

    static func identifiers(actions: [PadAction], terminationAllowedOnly: Bool = false) -> Set<String> {
        var result = Set<String>()
        for action in actions {
            if action.kind == .app || action.kind == .appFolder {
                if !action.value.isEmpty && (!terminationAllowedOnly || action.canQuitApp) { result.insert(action.value) }
            } else if !terminationAllowedOnly, action.kind == .shortcut, !action.targetAppBundleIdentifier.isEmpty {
                result.insert(action.targetAppBundleIdentifier)
            } else if action.kind == .workflow {
                result.formUnion(identifiers(actions: action.workflowSteps.map(\.action), terminationAllowedOnly: terminationAllowedOnly))
            }
        }
        return result
    }

    static func persistedIdentifiers(terminationAllowedOnly: Bool = false) -> Set<String> {
        let preferences = UserDefaults(suiteName: "com.pdg.chatgpt-micro-launchpad.native") ?? .standard
        let pages: [LaunchPage]
        if let data = preferences.data(forKey: "chatgpt-micro-launchpad.pages") {
            pages = (try? JSONDecoder().decode([LaunchPage].self, from: data)) ?? []
        } else {
            pages = PadDefaults.pages()
        }
        return identifiers(macPages: pages, phonePages: SmartphoneDefaults.persistedPages(from: preferences), terminationAllowedOnly: terminationAllowedOnly)
    }
}
