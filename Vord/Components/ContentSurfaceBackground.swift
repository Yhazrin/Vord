import SwiftUI

/// Stationary grain follows the panel's neutral colour; it never covers content.
struct ContentSurfaceBackground: View {
    var woodGrain: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppColors.surface.overlay {
            if woodGrain {
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    let dark = colorScheme == .dark
                    let ink = dark ? Color.white : Color.black
                    let highlight = dark ? Color.black : Color.white
                    // Fixed seeds and panel-space coordinates keep the texture still
                    // when navigating, scrolling or resizing. No repeating bitmap seams.
                    for index in -5...Int(size.height / 4.8 + 5) {
                        let seed = Double(index + 1007)
                        let variation = fraction(sin(seed * 127.1) * 43758.5453)
                        let phase = seed * 1.618
                        let baseline = Double(index) * 4.8 + variation * 2
                        var path = Path()
                        let points = Int(size.width / 18) + 2
                        for point in 0...points {
                            let x = Double(point) * 18
                            let drift = sin(x / (120 + variation * 130) + phase) * (1.2 + variation * 2.8)
                                + sin(x / 49 + phase * 0.7) * 0.38
                            let position = CGPoint(x: x, y: baseline + drift)
                            if point == 0 { path.move(to: position) } else { path.addLine(to: position) }
                        }
                        context.stroke(path, with: .color(ink.opacity((dark ? 0.026 : 0.020) * (0.55 + variation * 0.45))),
                                       lineWidth: 0.25 + variation * 0.2)
                        context.stroke(path.offsetBy(dx: 0, dy: 0.65), with: .color(highlight.opacity(dark ? 0.035 : 0.16)),
                                       lineWidth: 0.3)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func fraction(_ value: Double) -> Double { value - floor(value) }
}
