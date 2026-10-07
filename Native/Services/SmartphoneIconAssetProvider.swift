import AppKit
import Foundation

@MainActor
enum SmartphoneIconAssetProvider {
    private static var cache: [String: SmartphoneIconAsset] = [:]

    static func assets(for pages: [SmartphonePage]) -> [String: SmartphoneIconAsset] {
        var assets: [String: SmartphoneIconAsset] = [:]
        for button in pages.flatMap(\.buttons) {
            guard !button.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(button.secondTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let asset = asset(for: button, isSecondAction: false) {
                assets[assetKey(for: button.id, isSecondAction: false)] = asset
            }
            if button.secondAction != nil,
               let asset = asset(for: button, isSecondAction: true) {
                assets[assetKey(for: button.id, isSecondAction: true)] = asset
            }
            if let activeAsset = asset(for: button, isSecondAction: button.isSecondActionActive) {
                assets[button.id] = activeAsset
            }

            for shortcut in button.folderShortcuts {
                guard !shortcut.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(shortcut.secondTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if let asset = asset(for: shortcut, isSecondAction: false) {
                    assets[assetKey(for: shortcut.id, isSecondAction: false)] = asset
                }
                if shortcut.secondAction != nil,
                   let asset = asset(for: shortcut, isSecondAction: true) {
                    assets[assetKey(for: shortcut.id, isSecondAction: true)] = asset
                }
                if let activeAsset = asset(for: shortcut, isSecondAction: shortcut.isSecondActionActive) {
                    assets[shortcut.id] = activeAsset
                }
            }
        }
        return assets
    }

    static func assetKey(for id: String, isSecondAction: Bool) -> String {
        "\(id)__\(isSecondAction ? "B" : "A")"
    }

    private static func asset(for button: SmartphoneButton, isSecondAction: Bool) -> SmartphoneIconAsset? {
        let symbol = isSecondAction ? button.secondSymbol ?? button.symbol : button.symbol
        let customData: Data?
        if isSecondAction {
            customData = button.secondCustomIconData
                ?? (button.secondSymbol == nil ? button.customIconData : nil)
        } else {
            customData = button.customIconData
        }
        let configuredAction = isSecondAction ? button.secondAction ?? button.action : button.action
        let action = configuredAction.kind == .none ? button.longPressAction : configuredAction
        let usesActionIcon = isSecondAction
            ? button.secondSymbol == nil && button.usesActionIconForSymbol
            : button.usesActionIconForSymbol
        return asset(for: button.id, symbol: symbol, customData: customData, action: action, usesActionIcon: usesActionIcon)
    }

    private static func asset(for shortcut: SmartphoneFolderShortcut, isSecondAction: Bool) -> SmartphoneIconAsset? {
        let symbol = isSecondAction ? shortcut.secondSymbol ?? shortcut.symbol : shortcut.symbol
        let customData: Data?
        if isSecondAction {
            customData = shortcut.secondCustomIconData
                ?? (shortcut.secondSymbol == nil ? shortcut.customIconData : nil)
        } else {
            customData = shortcut.customIconData
        }
        return asset(
            for: shortcut.id,
            symbol: symbol,
            customData: customData,
            action: isSecondAction ? shortcut.secondAction ?? shortcut.action : shortcut.action,
            usesActionIcon: false
        )
    }

    private static func asset(for id: String, symbol: String, customData: Data?, action: PadAction, usesActionIcon: Bool) -> SmartphoneIconAsset? {
        if let customData,
           let customAsset = customAsset(for: id, data: customData) {
            return customAsset
        }

        guard !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if usesActionIcon,
           let bundleIdentifier = targetBundleIdentifier(for: action),
           !bundleIdentifier.isEmpty,
           let appAsset = appAsset(for: bundleIdentifier) {
            return appAsset
        }
        return symbolAsset(for: symbol)
    }

    private static func customAsset(for buttonID: String, data: Data) -> SmartphoneIconAsset? {
        guard let pngData = SmartphoneIconData.normalizedPNGData(from: data) else { return nil }
        let encodedData = pngData.base64EncodedString()
        let cacheKey = "custom:\(buttonID):\(encodedData)"
        if let cached = cache[cacheKey] { return cached }
        let asset = SmartphoneIconAsset(kind: "custom", data: encodedData)
        cache[cacheKey] = asset
        return asset
    }

    private static func targetBundleIdentifier(for action: PadAction) -> String? {
        switch action.kind {
        case .app, .appFolder:
            return action.value
        case .shortcut:
            return action.targetAppBundleIdentifier
        case .terminalCommand, .url, .clipboardText, .none:
            return nil
        }
    }

    private static func appAsset(for bundleIdentifier: String) -> SmartphoneIconAsset? {
        let cacheKey = "app:\(bundleIdentifier)"
        if let cached = cache[cacheKey] { return cached }
        guard let icon = AppRegistrationService.icon(for: bundleIdentifier),
              let pngData = pngData(for: icon, tint: nil) else { return nil }
        let asset = SmartphoneIconAsset(kind: "app", data: pngData.base64EncodedString())
        cache[cacheKey] = asset
        return asset
    }

    private static func symbolAsset(for symbol: String) -> SmartphoneIconAsset? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "symbol:\(normalizedSymbol)"
        if let cached = cache[cacheKey] { return cached }
        guard let icon = NSImage(systemSymbolName: normalizedSymbol, accessibilityDescription: nil),
              let pngData = pngData(
                for: icon.withSymbolConfiguration(.init(pointSize: 52, weight: .medium)) ?? icon,
                tint: .white
              ) else { return nil }
        let asset = SmartphoneIconAsset(kind: "sf-symbol", data: pngData.base64EncodedString())
        cache[cacheKey] = asset
        return asset
    }

    private static func pngData(for icon: NSImage, tint: NSColor?) -> Data? {
        let pixelSize = 96
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = NSImageInterpolation.high
        icon.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        if let tint {
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(tint.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}
