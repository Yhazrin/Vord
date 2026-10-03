import SwiftUI

/// Neutral texture belongs to the outer window, beneath the plain content panel.
struct ContentSurfaceBackground: View {
    var woodGrain: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppColors.windowBackground.overlay {
            if woodGrain {
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    let dark = colorScheme == .dark
                    let ink = dark ? Color.white : Color.black
                    // World-space seeds keep fibres still when resizing. Cells
                    // distribute seeds only; there are no visible tile boundaries.
                    for row in -1...Int(size.height / 100 + 1) {
                        for column in -1...Int(size.width / 140 + 1) {
                            let seed = row * 73856093 + column * 19349663
                            let count = 18 + Int(noise(seed, 1) * 42)
                            for fibre in 0..<count {
                                let salt = fibre * 13
                                let x = Double(column) * 140 + noise(seed, salt + 2) * 140
                                let y = Double(row) * 100 + noise(seed, salt + 3) * 100
                                let length = 12 + pow(noise(seed, salt + 4), 1.7) * 195
                                let bend = (noise(seed, salt + 5) - 0.5) * 12
                                let endY = y + (noise(seed, salt + 6) - 0.5) * 5
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: y))
                                path.addCurve(to: CGPoint(x: x + length, y: endY),
                                              control1: CGPoint(x: x + length * 0.34, y: y + bend),
                                              control2: CGPoint(x: x + length * 0.72, y: endY - bend * 0.35))
                                let opacity = (dark ? 0.040 : 0.065) + noise(seed, salt + 7) * (dark ? 0.035 : 0.050)
                                let fade = Gradient(stops: [
                                    .init(color: ink.opacity(0), location: 0),
                                    .init(color: ink.opacity(opacity), location: 0.18),
                                    .init(color: ink.opacity(opacity * 0.68), location: 0.65),
                                    .init(color: ink.opacity(0), location: 1)
                                ])
                                let shading = GraphicsContext.Shading.linearGradient(fade,
                                    startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + length, y: endY))
                                context.stroke(path, with: shading,
                                    style: StrokeStyle(lineWidth: 0.3 + noise(seed, salt + 8) * 0.4, lineCap: .round))
                                // Occasional neighbouring fibres form small grain
                                // clusters, rather than parallel, evenly spaced rules.
                                if noise(seed, salt + 9) > 0.72 {
                                    context.stroke(path.offsetBy(dx: 2, dy: 0.9 + noise(seed, salt + 10) * 2.2),
                                                   with: shading, lineWidth: 0.25)
                                }
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func noise(_ seed: Int, _ salt: Int) -> Double {
        let value = sin(Double(seed + 1007) * 127.1 + Double(salt) * 311.7) * 43758.5453
        return value - floor(value)
    }
}
