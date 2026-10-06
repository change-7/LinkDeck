import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    static let storageKey = "folderSyncAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: AppText.lightAppearance
        case .dark: AppText.darkAppearance
        case .system: AppText.systemAppearance
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
