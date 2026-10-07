import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case app
    case appFolder
    case shortcut
    case terminalCommand
    case url
    case clipboardText
    case none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .app: "앱 실행"
        case .appFolder: "앱 폴더"
        case .shortcut: "단축키 설정"
        case .terminalCommand: "터미널 명령"
        case .url: "웹페이지 이동"
        case .clipboardText: "클립보드 텍스트"
        case .none: "없음"
        }
    }
}

struct PadAction: Codable, Hashable {
    var kind: ActionKind = .none
    var value = ""
    /// Optional app that receives this shortcut. Empty keeps the existing global behavior.
    var targetAppBundleIdentifier = ""
    /// When a shortcut has a target app, launch it before dispatching when it is not running.
    var launchTargetAppIfNeeded = true
    var showTerminalWindow = true
    var openURLInCurrentTab = false

    init(
        kind: ActionKind = .none,
        value: String = "",
        targetAppBundleIdentifier: String = "",
        launchTargetAppIfNeeded: Bool = true,
        showTerminalWindow: Bool = true,
        openURLInCurrentTab: Bool = false
    ) {
        self.kind = kind
        self.value = value
        self.targetAppBundleIdentifier = targetAppBundleIdentifier
        self.launchTargetAppIfNeeded = launchTargetAppIfNeeded
        self.showTerminalWindow = showTerminalWindow
        self.openURLInCurrentTab = openURLInCurrentTab
    }

    /// Repairs the value left by the old action-kind switcher when an app
    /// bundle ID was retained as the shortcut value.
    var repairedForPersistence: PadAction {
        guard kind == .shortcut,
              !targetAppBundleIdentifier.isEmpty,
              value == targetAppBundleIdentifier,
              value.contains(".") else { return self }
        var repaired = self
        repaired.value = ""
        return repaired
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, targetAppBundleIdentifier, launchTargetAppIfNeeded, showTerminalWindow, openURLInCurrentTab
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(ActionKind.self, forKey: .kind) ?? .none
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        targetAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .targetAppBundleIdentifier) ?? ""
        launchTargetAppIfNeeded = try container.decodeIfPresent(Bool.self, forKey: .launchTargetAppIfNeeded) ?? true
        showTerminalWindow = try container.decodeIfPresent(Bool.self, forKey: .showTerminalWindow) ?? true
        openURLInCurrentTab = try container.decodeIfPresent(Bool.self, forKey: .openURLInCurrentTab) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
        try container.encode(targetAppBundleIdentifier, forKey: .targetAppBundleIdentifier)
        try container.encode(launchTargetAppIfNeeded, forKey: .launchTargetAppIfNeeded)
        try container.encode(showTerminalWindow, forKey: .showTerminalWindow)
        try container.encode(openURLInCurrentTab, forKey: .openURLInCurrentTab)
    }
}

private func nextConfiguredAction(
    primary: PadAction,
    secondary: PadAction?,
    isSecondActionActive: inout Bool
) -> PadAction {
    guard let secondary else {
        isSecondActionActive = false
        return primary
    }
    isSecondActionActive.toggle()
    return isSecondActionActive ? secondary : primary
}

struct SmartphoneFolderShortcut: Identifiable, Codable, Hashable {
    let id: String
    var title = ""
    var secondTitle: String?
    var symbol = "command"
    var secondSymbol: String?
    var customIconData: Data?
    var secondCustomIconData: Data?
    var action = PadAction(kind: .shortcut)
    var longPressAction = PadAction()
    var secondAction: PadAction?
    var isSecondActionActive = false

    var activeTitle: String {
        guard secondAction != nil, isSecondActionActive,
              let secondTitle, !secondTitle.isEmpty else { return title }
        return secondTitle
    }

    var activeSymbol: String {
        secondAction != nil && isSecondActionActive ? secondSymbol ?? symbol : symbol
    }

    var activeCustomIconData: Data? {
        guard secondAction != nil, isSecondActionActive else { return customIconData }
        if let secondCustomIconData { return secondCustomIconData }
        return secondSymbol == nil ? customIconData : nil
    }

    init(
        id: String,
        title: String = "",
        secondTitle: String? = nil,
        symbol: String = "command",
        secondSymbol: String? = nil,
        customIconData: Data? = nil,
        secondCustomIconData: Data? = nil,
        action: PadAction = PadAction(kind: .shortcut),
        longPressAction: PadAction = PadAction(),
        secondAction: PadAction? = nil,
        isSecondActionActive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.secondTitle = secondTitle
        self.symbol = symbol
        self.secondSymbol = secondSymbol
        self.customIconData = customIconData
        self.secondCustomIconData = secondCustomIconData
        self.action = action
        self.longPressAction = longPressAction
        self.secondAction = secondAction
        self.isSecondActionActive = isSecondActionActive
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, secondTitle, symbol, secondSymbol, customIconData, secondCustomIconData
        case action, longPressAction, secondAction, isSecondActionActive
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case requiresLongPress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        secondTitle = try container.decodeIfPresent(String.self, forKey: .secondTitle)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "command"
        secondSymbol = try container.decodeIfPresent(String.self, forKey: .secondSymbol)
        customIconData = try container.decodeIfPresent(Data.self, forKey: .customIconData)
        secondCustomIconData = try container.decodeIfPresent(Data.self, forKey: .secondCustomIconData)
        action = try container.decodeIfPresent(PadAction.self, forKey: .action) ?? PadAction(kind: .shortcut)
        let savedLongPressAction = try container.decodeIfPresent(PadAction.self, forKey: .longPressAction)
        longPressAction = savedLongPressAction ?? PadAction()
        secondAction = try container.decodeIfPresent(PadAction.self, forKey: .secondAction)
        isSecondActionActive = try container.decodeIfPresent(Bool.self, forKey: .isSecondActionActive) ?? false
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if savedLongPressAction == nil,
           try legacy.decodeIfPresent(Bool.self, forKey: .requiresLongPress) == true {
            longPressAction = action
            action = PadAction()
        }
    }

    mutating func actionForNextPress() -> PadAction {
        nextConfiguredAction(
            primary: action,
            secondary: secondAction,
            isSecondActionActive: &isSecondActionActive
        )
    }
}

struct Pad: Identifiable, Codable, Hashable {
    let id: String
    var title = ""
    var secondTitle: String?
    var symbol = ""
    var secondSymbol: String?
    var idleColor = "off"
    var activeColor = "green"
    var action = PadAction()
    var secondAction: PadAction?
    var isSecondActionActive = false

    var activeTitle: String {
        guard secondAction != nil, isSecondActionActive,
              let secondTitle, !secondTitle.isEmpty else { return title }
        return secondTitle
    }

    var activeSymbol: String {
        secondAction != nil && isSecondActionActive ? secondSymbol ?? symbol : symbol
    }

    var stateColor: String {
        secondAction != nil && isSecondActionActive ? activeColor : idleColor
    }

    mutating func actionForNextPress() -> PadAction {
        nextConfiguredAction(
            primary: action,
            secondary: secondAction,
            isSecondActionActive: &isSecondActionActive
        )
    }

    func configuration(at id: String) -> Pad {
        Pad(
            id: id,
            title: title,
            secondTitle: secondTitle,
            symbol: symbol,
            secondSymbol: secondSymbol,
            idleColor: idleColor,
            activeColor: activeColor,
            action: action,
            secondAction: secondAction,
            isSecondActionActive: isSecondActionActive
        )
    }
}

extension Pad {
    private enum CodingKeys: String, CodingKey {
        case id, title, secondTitle, symbol, secondSymbol, idleColor, activeColor, action, secondAction, isSecondActionActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        secondTitle = try container.decodeIfPresent(String.self, forKey: .secondTitle)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? ""
        secondSymbol = try container.decodeIfPresent(String.self, forKey: .secondSymbol)
        idleColor = try container.decodeIfPresent(String.self, forKey: .idleColor) ?? "off"
        activeColor = try container.decodeIfPresent(String.self, forKey: .activeColor) ?? "green"
        action = try container.decodeIfPresent(PadAction.self, forKey: .action) ?? PadAction()
        secondAction = try container.decodeIfPresent(PadAction.self, forKey: .secondAction)
        isSecondActionActive = try container.decodeIfPresent(Bool.self, forKey: .isSecondActionActive) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(secondTitle, forKey: .secondTitle)
        try container.encode(symbol, forKey: .symbol)
        try container.encodeIfPresent(secondSymbol, forKey: .secondSymbol)
        try container.encode(idleColor, forKey: .idleColor)
        try container.encode(activeColor, forKey: .activeColor)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(secondAction, forKey: .secondAction)
        try container.encode(isSecondActionActive, forKey: .isSecondActionActive)
    }
}

struct SmartphoneButton: Identifiable, Codable, Hashable {
    let id: String
    var title = ""
    var secondTitle: String?
    var symbol = "square.grid.2x2"
    var secondSymbol: String?
    var customIconData: Data?
    var secondCustomIconData: Data?
    var action = PadAction()
    var folderShortcuts: [SmartphoneFolderShortcut] = []
    var longPressAction = PadAction()
    var secondAction: PadAction?
    var isSecondActionActive = false
    var usesActionIconForSymbol = true

    var activeTitle: String {
        guard secondAction != nil, isSecondActionActive,
              let secondTitle, !secondTitle.isEmpty else { return title }
        return secondTitle
    }

    var activeSymbol: String {
        secondAction != nil && isSecondActionActive ? secondSymbol ?? symbol : symbol
    }

    var activeCustomIconData: Data? {
        guard secondAction != nil, isSecondActionActive else { return customIconData }
        if let secondCustomIconData { return secondCustomIconData }
        return secondSymbol == nil ? customIconData : nil
    }

    var activeUsesActionIconForSymbol: Bool {
        secondAction != nil && isSecondActionActive
            ? secondSymbol == nil && usesActionIconForSymbol
            : usesActionIconForSymbol
    }

    init(
        id: String,
        title: String = "",
        secondTitle: String? = nil,
        symbol: String = "square.grid.2x2",
        secondSymbol: String? = nil,
        customIconData: Data? = nil,
        secondCustomIconData: Data? = nil,
        action: PadAction = PadAction(),
        folderShortcuts: [SmartphoneFolderShortcut] = [],
        longPressAction: PadAction = PadAction(),
        secondAction: PadAction? = nil,
        isSecondActionActive: Bool = false,
        usesActionIconForSymbol: Bool = true
    ) {
        self.id = id
        self.title = title
        self.secondTitle = secondTitle
        self.symbol = symbol
        self.secondSymbol = secondSymbol
        self.customIconData = customIconData
        self.secondCustomIconData = secondCustomIconData
        self.action = action
        self.folderShortcuts = folderShortcuts
        self.longPressAction = longPressAction
        self.secondAction = secondAction
        self.isSecondActionActive = isSecondActionActive
        self.usesActionIconForSymbol = usesActionIconForSymbol
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, secondTitle, symbol, secondSymbol, customIconData, secondCustomIconData
        case action, folderShortcuts, longPressAction, secondAction, isSecondActionActive, usesActionIconForSymbol
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case requiresLongPress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        secondTitle = try container.decodeIfPresent(String.self, forKey: .secondTitle)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        secondSymbol = try container.decodeIfPresent(String.self, forKey: .secondSymbol)
        customIconData = try container.decodeIfPresent(Data.self, forKey: .customIconData)
        secondCustomIconData = try container.decodeIfPresent(Data.self, forKey: .secondCustomIconData)
        action = try container.decodeIfPresent(PadAction.self, forKey: .action) ?? PadAction()
        folderShortcuts = try container.decodeIfPresent([SmartphoneFolderShortcut].self, forKey: .folderShortcuts) ?? []
        let savedLongPressAction = try container.decodeIfPresent(PadAction.self, forKey: .longPressAction)
        longPressAction = savedLongPressAction ?? PadAction()
        secondAction = try container.decodeIfPresent(PadAction.self, forKey: .secondAction)
        isSecondActionActive = try container.decodeIfPresent(Bool.self, forKey: .isSecondActionActive) ?? false
        usesActionIconForSymbol = try container.decodeIfPresent(Bool.self, forKey: .usesActionIconForSymbol) ?? true
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if savedLongPressAction == nil,
           try legacy.decodeIfPresent(Bool.self, forKey: .requiresLongPress) == true {
            longPressAction = action
            action = PadAction()
        }
    }

    mutating func actionForNextPress() -> PadAction {
        nextConfiguredAction(
            primary: action,
            secondary: secondAction,
            isSecondActionActive: &isSecondActionActive
        )
    }

    func configuration(at id: String) -> SmartphoneButton {
        SmartphoneButton(
            id: id,
            title: title,
            secondTitle: secondTitle,
            symbol: symbol,
            secondSymbol: secondSymbol,
            customIconData: customIconData,
            secondCustomIconData: secondCustomIconData,
            action: action,
            folderShortcuts: folderShortcuts,
            longPressAction: longPressAction,
            secondAction: secondAction,
            isSecondActionActive: isSecondActionActive,
            usesActionIconForSymbol: usesActionIconForSymbol
        )
    }
}

struct SmartphonePage: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var buttons: [SmartphoneButton]

    mutating func swapButtonConfigurations(from sourceID: String, to destinationID: String) -> Bool {
        guard sourceID != destinationID,
              sourceID.hasPrefix("smartphone_page_"),
              destinationID.hasPrefix("smartphone_page_"),
              let sourceIndex = buttons.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = buttons.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        let source = buttons[sourceIndex]
        let destination = buttons[destinationIndex]
        buttons[sourceIndex] = destination.configuration(at: sourceID)
        buttons[destinationIndex] = source.configuration(at: destinationID)
        return true
    }

    mutating func swapButtonConfigurations(from sourceID: String, with destinationPage: inout SmartphonePage, to destinationID: String) -> Bool {
        guard sourceID != destinationID,
              let sourceIndex = buttons.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = destinationPage.buttons.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        let source = buttons[sourceIndex]
        let destination = destinationPage.buttons[destinationIndex]
        buttons[sourceIndex] = destination.configuration(at: sourceID)
        destinationPage.buttons[destinationIndex] = source.configuration(at: destinationID)
        return true
    }
}

struct LaunchPage: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var pads: [Pad]
    var pageIdleColor: String
    var pageActiveColor: String

    init(id: UUID = UUID(), name: String, pads: [Pad], pageIdleColor: String = "green", pageActiveColor: String = "brightGreen") {
        self.id = id
        self.name = name
        self.pads = pads
        self.pageIdleColor = pageIdleColor
        self.pageActiveColor = pageActiveColor
    }

    /// The top P button uses its selected-page color only while this page is active.
    func topButtonColor(isSelected: Bool) -> String {
        isSelected ? pageActiveColor : pageIdleColor
    }

    mutating func swapGridPadConfigurations(from sourceID: String, to destinationID: String) -> Bool {
        guard sourceID != destinationID,
              sourceID.hasPrefix("grid_"),
              destinationID.hasPrefix("grid_"),
              let sourceIndex = pads.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = pads.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        let source = pads[sourceIndex]
        let destination = pads[destinationIndex]
        pads[sourceIndex] = destination.configuration(at: sourceID)
        pads[destinationIndex] = source.configuration(at: destinationID)
        return true
    }

    mutating func clearGridPadConfiguration(_ padID: String) -> Bool {
        guard padID.hasPrefix("grid_"),
              let index = pads.firstIndex(where: { $0.id == padID }) else { return false }
        pads[index] = Pad(id: padID)
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, pads, pageColor, pageIdleColor, pageActiveColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        pads = try container.decode([Pad].self, forKey: .pads)
        let legacyColor = try container.decodeIfPresent(String.self, forKey: .pageColor)
        pageIdleColor = try container.decodeIfPresent(String.self, forKey: .pageIdleColor) ?? legacyColor ?? "green"
        pageActiveColor = try container.decodeIfPresent(String.self, forKey: .pageActiveColor) ?? "brightGreen"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(pads, forKey: .pads)
        try container.encode(pageIdleColor, forKey: .pageIdleColor)
        try container.encode(pageActiveColor, forKey: .pageActiveColor)
    }
}

enum PadColor: String, CaseIterable, Identifiable {
    // Launchpad Mini MK1: red + green LEDs only. No blue, purple, white, pink, or lime.
    case off, darkRed, red, brightRed, darkGreen, green, brightGreen, darkAmber, amber, yellow, orange

    var id: String { rawValue }

    static let launchpadPalette: [PadColor] = [.off, .darkRed, .red, .brightRed, .darkGreen, .green, .brightGreen, .darkAmber, .amber, .yellow, .orange]
}

/// An importable 8×8 animation preset. Coordinates in the JSON format are one-based
/// so they can be written naturally in a ChatGPT response and checked by the importer.
struct MotionPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var loop: Bool
    var frameDurationMs: Int
    var frames: [MotionFrame]

    init(id: UUID = UUID(), name: String, loop: Bool, frameDurationMs: Int, frames: [MotionFrame]) {
        self.id = id
        self.name = name
        self.loop = loop
        self.frameDurationMs = frameDurationMs
        self.frames = frames
    }
}

struct MotionFrame: Codable, Hashable {
    var pixels: [MotionPixel]
}

struct MotionPixel: Codable, Hashable {
    var row: Int
    var column: Int
    var color: String
}
