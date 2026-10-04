import AppKit
import QuartzCore

/// The native window follows a damped spring. Re-targeting retains velocity instead of
/// restarting an ease curve, so typing and repeated shortcuts never produce a jump.
@MainActor
final class CaptureFrameSpring {
    private weak var window: NSWindow?
    private var timer: Timer?
    private var target = [Double](repeating: 0, count: 4)
    private var position = [Double](repeating: 0, count: 4)
    private var velocity = [Double](repeating: 0, count: 4)
    private var lastTime: CFTimeInterval = 0
    private var closing = false
    private var completion: (() -> Void)?

    func stop() {
        timer?.invalidate(); timer = nil
        velocity = [Double](repeating: 0, count: 4)
        completion = nil
    }

    func move(_ window: NSWindow, to frame: NSRect, initialVelocity: CGPoint? = nil,
              closing: Bool = false, onCompletion: (() -> Void)? = nil) {
        self.closing = closing
        completion = onCompletion
        let next = [frame.minX, frame.minY, frame.width, frame.height].map(Double.init)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !window.isVisible {
            timer?.invalidate(); timer = nil
            velocity = [Double](repeating: 0, count: 4)
            window.setPanelFrame(frame)
            completion = nil
            onCompletion?()
            return
        }
        if self.window !== window || timer == nil {
            position = [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height].map(Double.init)
            velocity = [Double](repeating: 0, count: 4)
        }
        if let initialVelocity {
            velocity[0] = initialVelocity.x
            velocity[1] = initialVelocity.y
        }
        self.window = window
        target = next
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        guard let window else { timer?.invalidate(); timer = nil; return }
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(0.001, now - lastTime))
        lastTime = now
        for index in 0..<4 {
            let state = CaptureSpringCurve.advance(position: position[index], velocity: velocity[index],
                target: target[index], seconds: dt, damping: closing ? 0.94 : 0.82)
            position[index] = state.position
            velocity[index] = state.velocity
        }
        let settled = zip(position, target).allSatisfy { abs($0 - $1) < 0.2 }
            && velocity.allSatisfy { abs($0) < 2 }
        if settled { position = target; velocity = [Double](repeating: 0, count: 4) }
        window.setPanelFrame(NSRect(x: position[0], y: position[1],
            width: max(32, position[2]), height: max(32, position[3])))
        if settled {
            timer?.invalidate(); timer = nil
            let finished = completion; completion = nil
            finished?()
        }
    }

    deinit { timer?.invalidate() }
}

enum CaptureSpringCurve {
    /// Closed form integration is stable when a display frame is delayed.
    static func advance(position: Double, velocity: Double, target: Double, seconds: Double, damping: Double = 0.82)
        -> (position: Double, velocity: Double) {
        let omega = 24.0
        let decay = damping * omega
        let damped = omega * sqrt(1 - damping * damping)
        let displacement = position - target
        let a = displacement
        let b = (velocity + decay * displacement) / damped
        let cosine = cos(damped * seconds)
        let sine = sin(damped * seconds)
        let envelope = exp(-decay * seconds)
        let offset = envelope * (a * cosine + b * sine)
        let speed = envelope * (-decay * (a * cosine + b * sine)
            + damped * (-a * sine + b * cosine))
        return (target + offset, speed)
    }
}
