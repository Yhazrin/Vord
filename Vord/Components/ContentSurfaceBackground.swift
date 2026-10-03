import SwiftUI

/// Fixed, neutral fibres give the panel texture without changing its base colour.
struct ContentSurfaceBackground: View {
    var woodGrain: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppColors.surface.overlay {
            if woodGrain {
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    let dark = colorScheme == .dark
                    let ink = dark ? Color.white : Color.black
                    let light = dark ? Color.black : Color.white
                    // The seed belongs to the panel, never to a redraw. Scrolling
                    // and navigation do not regenerate or animate the grain.
                    for index in -5...Int(size.height / 3.5 + 5) {
                        let baseline = Double(index) * 3.5 + noise(index, 1) * 2.7
                        let amplitude = 0.45 + noise(index, 2) * 1.8
                        let phase = noise(index, 3) * .pi * 2
                        let wavelength = 70 + noise(index, 4) * 130
                        let width = 0.35 + noise(index, 5) * 0.35
                        let opacity = (dark ? 0.045 : 0.065) + noise(index, 6) * (dark ? 0.035 : 0.050)
                        var cursor = -30.0
                        var segment = 0
                        while cursor < size.width {
                            let salt = segment * 7
                            // Some fibres span the panel; most fade into small,
                            // irregular runs like old, finely sanded timber.
                            let length = noise(index, 7) > 0.84 ? Double(size.width) + 60 : 34 + noise(index, 20 + salt) * 210
                            let end = min(Double(size.width) + 20, cursor + length)
                            var path = Path()
                            let samples = max(2, Int((end - cursor) / 9))
                            for point in 0...samples {
                                let x = cursor + (end - cursor) * Double(point) / Double(samples)
                                let sharedDrift = sin(x / 185) * 2.4 + sin(x / 67 + 0.4) * 0.65
                                let fineDrift = sin(x / wavelength + phase) * amplitude + sin(x / 23 + phase) * 0.16
                                let position = CGPoint(x: x, y: baseline + sharedDrift + fineDrift)
                                if point == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                            let fade = Gradient(stops: [
                                .init(color: ink.opacity(0), location: 0),
                                .init(color: ink.opacity(opacity), location: 0.10),
                                .init(color: ink.opacity(opacity * 0.72), location: 0.68),
                                .init(color: ink.opacity(0), location: 1)
                            ])
                            context.stroke(path, with: .linearGradient(fade, startPoint: CGPoint(x: cursor, y: baseline), endPoint: CGPoint(x: end, y: baseline)),
                                           style: StrokeStyle(lineWidth: width, lineCap: .round))
                            context.stroke(path.offsetBy(dx: 0, dy: 0.8), with: .color(light.opacity(dark ? 0.035 : 0.24)), lineWidth: 0.35)
                            cursor = end + 6 + noise(index, 21 + salt) * 46
                            segment += 1
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func noise(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index + 1007) * 127.1 + Double(salt) * 311.7) * 43758.5453
        return value - floor(value)
    }
}
