import AppKit
import SwiftUI

enum AppTypography {
    static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func nativeUI(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static let largeTitle = ui(size: 28, weight: .semibold)
    static let title = ui(size: 17, weight: .semibold)
    static let headline = ui(size: 15, weight: .semibold)
    static let body = ui(size: 15)
    static let caption = ui(size: 13)

    static let pageTitle = largeTitle
    static let sectionTitle = ui(size: 13, weight: .semibold)
    static let heroStat = ui(size: 56, weight: .medium)
    static let stat = ui(size: 20, weight: .medium)
    static let word = Font.system(size: 52, weight: .regular, design: .serif)
    static let reading = ui(size: 22)
    static let input = ui(size: 22)

    static func studyWord(_ text: String) -> Font {
        let chinese = text.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        if chinese {
            return .system(size: text.count > 12 ? 28 : 40, weight: .regular)
        }
        return .system(size: text.count > 16 ? 32 : 52, weight: .regular, design: .serif)
    }
    static let button = ui(size: 13, weight: .semibold)
    static let secondary = caption
    static let tertiary = ui(size: 12)
    static let metaLabel = tertiary
    static let metaValue = ui(size: 14)
    static let rowTitle = ui(size: 15, weight: .medium)

    static let greeting = pageTitle
    static let metric = heroStat
}
