import SwiftUI

/// Colors used by the Mac editor. Hardware and phone previews keep their own colors.
struct MacAppearance {
    let scheme: ColorScheme

    private var isDark: Bool { scheme == .dark }

    var canvas: Color { isDark ? Color(red: 0.035, green: 0.035, blue: 0.045) : Color(red: 0.85, green: 0.875, blue: 0.92) }
    var panel: Color { isDark ? Color(red: 0.065, green: 0.065, blue: 0.08) : Color(red: 0.80, green: 0.84, blue: 0.90) }
    var input: Color { isDark ? Color(red: 0.01, green: 0.02, blue: 0.05) : Color(red: 0.97, green: 0.98, blue: 0.995) }
    var foreground: Color { isDark ? .white : Color(red: 0.105, green: 0.125, blue: 0.16) }
    var accent: Color { isDark ? .orange : Color(red: 0.23, green: 0.42, blue: 0.66) }
    var accentForeground: Color { isDark ? .black : .white }
    var border: Color { foreground.opacity(isDark ? 0.18 : 0.26) }
    var control: Color { isDark ? foreground.opacity(0.075) : Color(red: 0.965, green: 0.975, blue: 0.995) }
    var inset: Color { foreground.opacity(isDark ? 0.045 : 0.035) }
}
