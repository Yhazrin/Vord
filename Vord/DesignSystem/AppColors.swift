import AppKit
import SwiftUI

enum AppColors {
    private static func adaptive(_ light: UInt32, _ dark: UInt32,
                                 contrastLight: UInt32? = nil, contrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ||
                match == .accessibilityHighContrastDarkAqua || match == .accessibilityHighContrastAqua
            let value = isDark ? (increased ? contrastDark ?? dark : dark) : (increased ? contrastLight ?? light : light)
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    // Neutral surfaces stay quiet; typography and spacing carry the reading hierarchy.
    static let windowBackground = adaptive(0xEEEEEE, 0x141414)
    static let contentBackground = adaptive(0xFAFAFA, 0x1C1C1C)
    static let surface = contentBackground
    static let elevatedSurface = adaptive(0xFFFFFF, 0x222222)
    static let inputSurface = adaptive(0xF2F2F2, 0x181818)
    static let primaryText = adaptive(0x202020, 0xEFEFEF)
    static let secondaryText = adaptive(0x595959, 0xBDBDBD, contrastLight: 0x3D3D3D, contrastDark: 0xDFDFDF)
    static let tertiaryText = adaptive(0x656565, 0xA3A3A3, contrastLight: 0x494949, contrastDark: 0xC7C7C7)
    static let accent = adaptive(0x292929, 0xE8E8E8)
    static let accentWash = adaptive(0xE8E8E8, 0x303030, contrastLight: 0xD9D9D9, contrastDark: 0x3B3B3B)
    static let hero = adaptive(0x242424, 0x282828)
    static let heroText = adaptive(0xF7F7F7, 0xEFEFEF)
    static let gold = adaptive(0x696969, 0xC8C8C8)
    static let hover = adaptive(0xEDEDED, 0x292929)
    static let selected = accentWash
    static let hairline = adaptive(0xDEDEDE, 0x303030, contrastLight: 0x858585, contrastDark: 0x7C7C7C)
    static let subtleBorder = hairline
    static let accentNeutral = accent
    static let primaryButton = adaptive(0x292929, 0xE8E8E8)
    static let primaryButtonText = adaptive(0xFAFAFA, 0x202020)
    static let destructive = adaptive(0x595959, 0xCCCCCC)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: alpha)
    }
}
