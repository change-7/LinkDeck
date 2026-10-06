import SwiftUI
import AppKit

enum AppPalette {
    static let accent = adaptiveColor(
        light: NSColor(calibratedRed: 0.23, green: 0.42, blue: 0.66, alpha: 1),
        dark: .systemOrange
    )
    static let folderSurface = accent.opacity(0.14)
    static let listSurface = adaptiveColor(
        light: NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.995, alpha: 1),
        dark: NSColor(calibratedWhite: 1, alpha: 0.075)
    )
    static let settingsSurface = adaptiveColor(
        light: NSColor(calibratedRed: 0.80, green: 0.84, blue: 0.90, alpha: 1),
        dark: NSColor(calibratedRed: 0.065, green: 0.065, blue: 0.08, alpha: 1)
    )
    static let sectionBorder = adaptiveColor(
        light: NSColor(calibratedRed: 0.105, green: 0.125, blue: 0.16, alpha: 0.26),
        dark: NSColor(calibratedWhite: 1, alpha: 0.18)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
