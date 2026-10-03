import SwiftUI

enum AppMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static func feedback(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.24, bounce: 0.12) }
    static func navigation(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.30, bounce: 0.12) }
    static func layout(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.38, bounce: 0.08) }
    static func reading(_ reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: 0.16) }
    static func reveal(_ reduced: Bool) -> AnyTransition {
        reduced ? .identity : .opacity.combined(with: .offset(y: 6))
    }
}

/// Only the incoming content moves. Outgoing pages disappear immediately, releasing keyboard monitors.
struct MotionArrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var arrived = false
    func body(content: Content) -> some View {
        content
            .opacity(reduced || arrived ? 1 : 0.65)
            .offset(y: reduced || arrived ? 0 : 6)
            .onAppear { withAnimation(AppMotion.reading(reduced)) { arrived = true } }
    }
}
