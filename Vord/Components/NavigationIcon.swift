import AppKit
import ImageIO
import SwiftUI

enum NavigationIconStyle: String, CaseIterable, Identifiable, Sendable {
    case sculpted, outline
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sculpted: return "Sculpted"
        case .outline: return "Outline"
        }
    }
}

struct NavigationIcon: View {
    var tab: AppTab
    var style: NavigationIconStyle
    var size: CGFloat = 26
    var selected = false
    var hovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    private var lift: CGFloat { reducedMotion ? 0 : (hovering ? 1.1 : selected ? 0.45 : 0) }
    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if style == .sculpted, let image = NavigationIconAtlas.image(for: tab) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    // The transparent icon itself is the shadow mask. There is no
                    // enclosing tile, bevel or rectangle for these shadows to trace.
                    .compositingGroup()
                    .shadow(color: .black.opacity(dark ? 0.30 : 0.16), radius: 0.65, x: 0, y: 0.55)
                    .shadow(color: .black.opacity(dark ? 0.34 : 0.12), radius: 1.6 + lift * 0.45, x: 0, y: 1.3 + lift * 0.8)
                    .offset(y: -lift)
            } else {
                Image(systemName: tab.symbol)
                    .font(AppTypography.ui(size: 15))
                    .frame(width: style == .sculpted ? size : 20, height: size)
            }
        }
        .accessibilityHidden(true)
        .animation(reducedMotion ? nil : AppMotion.quick, value: hovering)
        .animation(AppMotion.navigation(reducedMotion), value: selected)
    }
}

/// Shared atlas loaded once; individual routes never decode the PNG on redraw.
@MainActor
enum NavigationIconAtlas {
    private static let images: [AppTab: NSImage] = load()
    static func image(for tab: AppTab) -> NSImage? { images[tab] }

    private static func load() -> [AppTab: NSImage] {
        guard let url = Bundle.main.url(forResource: "navigation-icons-sculpted", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width >= 4, atlas.height >= 2 else { return [:] }
        let width = atlas.width / 4
        let height = atlas.height / 2
        let tabs: [AppTab] = [.today, .review, .dictation, .context, .agent, .library, .add, .settings]
        var result: [AppTab: NSImage] = [:]
        for (index, tab) in tabs.enumerated() {
            let bounds = CGRect(x: (index % 4) * width, y: (index / 4) * height, width: width, height: height)
            guard let tile = atlas.cropping(to: bounds),
                  let clean = NavigationIconMask.sanitized(tile) else { continue }
            result[tab] = NSImage(cgImage: clean, size: NSSize(width: clean.width, height: clean.height))
        }
        return result
    }
}

/// Removes isolated alpha debris once during atlas decoding. Pixel colours and
/// the original antialiased outline survive; all live shadows remain SwiftUI's.
enum NavigationIconMask {
    static func sanitized(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 4, height > 4, width <= 2048, height <= 2048 else { return nil }
        let count = width * height
        var rgba = [UInt8](repeating: 0, count: count * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let decoded = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard decoded else { return nil }
        let opaque = (0..<count).map { rgba[$0 * 4 + 3] >= 220 ? UInt8(1) : UInt8(0) }
        // Two source pixels are a fraction of a point at sidebar size. Opening
        // breaks thin debris bridges without rounding the icon into a tile.
        let opened = morph(morph(opaque, width: width, height: height, radius: 2, dilate: false),
                           width: width, height: height, radius: 2, dilate: true)
        let body = substantialComponents(opened, width: width, height: height)
        guard body.contains(1) else { return nil }
        // Restore the source's antialiasing only immediately beside clean bodies.
        let support = morph(body, width: width, height: height, radius: 1, dilate: true)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for index in 0..<count {
            let byte = index * 4
            if support[index] == 0 {
                rgba[byte] = 0; rgba[byte + 1] = 0; rgba[byte + 2] = 0; rgba[byte + 3] = 0
            } else if rgba[byte + 3] > 0 {
                minX = min(minX, index % width); maxX = max(maxX, index % width)
                minY = min(minY, index / width); maxY = max(maxY, index / width)
            }
        }
        let data = Data(rgba)
        guard maxX >= minX, maxY >= minY,
              let provider = CGDataProvider(data: data as CFData),
              let cleaned = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                    decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let padding = 3
        let left = max(0, minX - padding), top = max(0, minY - padding)
        let right = min(width - 1, maxX + padding), bottom = min(height - 1, maxY + padding)
        return cleaned.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
    }

    private static func morph(_ mask: [UInt8], width: Int, height: Int, radius: Int, dilate: Bool) -> [UInt8] {
        var horizontal = [UInt8](repeating: 0, count: mask.count)
        var result = horizontal
        for y in 0..<height {
            for x in 0..<width {
                var active = !dilate
                for offset in -radius...radius {
                    let neighbor = x + offset
                    let set = neighbor >= 0 && neighbor < width && mask[y * width + neighbor] == 1
                    if dilate && set { active = true; break }
                    if !dilate && !set { active = false; break }
                }
                horizontal[y * width + x] = active ? 1 : 0
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var active = !dilate
                for offset in -radius...radius {
                    let neighbor = y + offset
                    let set = neighbor >= 0 && neighbor < height && horizontal[neighbor * width + x] == 1
                    if dilate && set { active = true; break }
                    if !dilate && !set { active = false; break }
                }
                result[y * width + x] = active ? 1 : 0
            }
        }
        return result
    }

    private static func substantialComponents(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        var labels = [Int](repeating: 0, count: mask.count)
        var areas = [0]
        for seed in mask.indices where mask[seed] == 1 && labels[seed] == 0 {
            let label = areas.count
            var stack = [seed]
            labels[seed] = label
            var area = 0
            while let index = stack.popLast() {
                area += 1
                let x = index % width, y = index / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbor = ny * width + nx
                        if mask[neighbor] == 1 && labels[neighbor] == 0 {
                            labels[neighbor] = label
                            stack.append(neighbor)
                        }
                    }
                }
            }
            areas.append(area)
        }
        let threshold = max(80, (areas.max() ?? 0) / 40)
        // The microphone capsule and its U-shaped stand are genuinely separate
        // components; retain all substantial bodies, not just the largest one.
        return labels.map { $0 > 0 && areas[$0] >= threshold ? 1 : 0 }
    }
}

struct NavigationIconSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ControlRow(title: "Sidebar icons") {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach([AppTab.today, .review, .library], id: \.self) { tab in
                        NavigationIcon(tab: tab, style: settings.navigationIconStyle, size: 22)
                    }
                }
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
                MenuSelect(name: "Sidebar icon style",
                           selection: Binding(get: { settings.navigationIconStyle }, set: { settings.setNavigationIconStyle($0) }),
                           choices: NavigationIconStyle.allCases, label: { $0.title })
            }
        }
    }
}
