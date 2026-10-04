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


/// The shell follows actual window dimensions, not a second animation clock.
struct CaptureCollapseGeometry {
    var progress: CGFloat
    var inset: CGFloat
    var radius: CGFloat
    var glassOpacity: Double

    init(size: CGSize, origin: CGSize) {
        let target = OrbDockPosition.diameter
        let widthTravel = max(1, origin.width - target)
        let heightTravel = max(1, origin.height - target)
        let remaining = max((size.width - target) / widthTravel, (size.height - target) / heightTravel)
        progress = min(1, max(0, 1 - remaining))
        inset = 8 * Self.smooth((progress - 0.65) / 0.35)
        radius = min(24 + 4 * progress, max(0, (min(size.width, size.height) - 2 * inset) / 2))
        glassOpacity = Double(Self.smooth((progress - 0.72) / 0.25))
    }
    private static func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

struct OrbFacePose {
    var openness: Double
    var smile: Double
    var tilt: Double

    static func sample(elapsed: Double, returnElapsed: Double?, successful: Bool,
                       hovered: Bool, dragging: Bool, displacement: Double, reduced: Bool) -> Self {
        if reduced { return Self(openness: 1, smile: 0, tilt: 0) }
        let cycle = max(0, elapsed).truncatingRemainder(dividingBy: 7.1)
        func blink(_ time: Double, start: Double, duration: Double) -> Double {
            guard time >= start, time < start + duration else { return 1 }
            return 1 - 0.93 * pow(sin((time - start) / duration * .pi), 2)
        }
        var opening = min(blink(cycle, start: 5.7, duration: 0.18), blink(cycle, start: 6.02, duration: 0.14))
        if let sinceReturn = returnElapsed, !successful {
            opening = min(opening, blink(sinceReturn, start: 0.12, duration: 0.2))
        }
        let smile: Double
        if successful, let sinceReturn = returnElapsed, sinceReturn >= 0, sinceReturn < 1.5 {
            smile = min(1, sinceReturn / 0.16) * min(1, max(0, (1.5 - sinceReturn) / 0.35))
        } else { smile = 0 }
        return Self(openness: opening * (dragging ? 0.74 : (hovered ? 1.06 : 1)),
                    smile: smile, tilt: dragging ? max(-4, min(4, displacement * 0.75)) : 0)
    }
}
