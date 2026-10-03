import Foundation
import CoreGraphics

/// Position follows a screen edge rather than absolute pixels, so it survives resolution changes.
struct OrbDockPosition: Codable, Equatable {
    enum Edge: String, Codable { case left, right }
    var edge: Edge = .right
    var heightFraction: Double = 0.04
    var displayID: UInt32?

    static let diameter: CGFloat = 72
    static let inset: CGFloat = 8

    func frame(in visible: CGRect) -> CGRect {
        let size = min(Self.diameter, visible.width, visible.height)
        let lower = visible.minY + Self.inset
        let upper = max(lower, visible.maxY - size - Self.inset)
        let fraction = min(1, max(0, heightFraction.isFinite ? heightFraction : 0.04))
        let x = edge == .left ? visible.minX + Self.inset : visible.maxX - size - Self.inset
        return CGRect(x: x, y: lower + (upper - lower) * fraction, width: size, height: size)
    }

    static func nearest(to frame: CGRect, in visible: CGRect, displayID: UInt32?) -> Self {
        let travel = max(1, visible.height - Self.diameter - 2 * Self.inset)
        return Self(edge: frame.midX < visible.midX ? .left : .right,
            heightFraction: min(1, max(0, (frame.minY - visible.minY - Self.inset) / travel)),
            displayID: displayID)
    }

    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, visible.minX + Self.inset), max(visible.minX, visible.maxX - frame.width - Self.inset)),
            y: min(max(frame.minY, visible.minY + Self.inset), max(visible.minY, visible.maxY - frame.height - Self.inset)),
            width: frame.width, height: frame.height)
    }
}

enum OrbPhysics {
    /// An underdamped interior response. The shell itself always remains circular.
    static func advance(position: Double, velocity: Double, target: Double, seconds: Double)
        -> (position: Double, velocity: Double) {
        let dt = min(0.08, max(0, seconds))
        let omega = 18.0, damping = 0.68
        let decay = damping * omega
        let frequency = omega * sqrt(1 - damping * damping)
        let a = position - target
        let b = (velocity + decay * a) / frequency
        let c = cos(frequency * dt), s = sin(frequency * dt), envelope = exp(-decay * dt)
        return (target + envelope * (a * c + b * s),
            envelope * (-decay * (a * c + b * s) + frequency * (-a * s + b * c)))
    }
}
