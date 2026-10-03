import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class OrbMotion: ObservableObject {
    @Published private(set) var refraction = CGSize.zero
    @Published private(set) var isDragging = false
    private var position = [0.0, 0.0]
    private var velocity = [0.0, 0.0]
    private var target = [0.0, 0.0]
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0

    func begin() {
        isDragging = true
        startTimer()
    }

    func drive(_ pointerVelocity: CGPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { reset(); return }
        target = [max(-5, min(5, -pointerVelocity.x / 180)), max(-5, min(5, pointerVelocity.y / 180))]
        startTimer()
    }

    func release() {
        isDragging = false
        target = [0, 0]
        startTimer()
    }

    func reset() {
        timer?.invalidate(); timer = nil
        position = [0, 0]; velocity = [0, 0]; target = [0, 0]
        refraction = .zero
    }

    private func startTimer() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { reset(); return }
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        let clock = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
    }

    private func step() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { reset(); return }
        let now = CACurrentMediaTime(), dt = now - lastTime
        lastTime = now
        for index in 0..<2 {
            let state = OrbPhysics.advance(position: position[index], velocity: velocity[index], target: target[index], seconds: dt)
            position[index] = state.position; velocity[index] = state.velocity
        }
        refraction = CGSize(width: position[0], height: position[1])
        if !isDragging && position.allSatisfy({ abs($0) < 0.015 }) && velocity.allSatisfy({ abs($0) < 0.08 }) { reset() }
    }

    deinit { timer?.invalidate() }
}

struct GlassOrbView: View {
    @ObservedObject var motion: OrbMotion
    var onOpen: () -> Void
    var onDragBegin: (CGPoint) -> Void
    var onDragChange: (CGPoint) -> Void
    var onDragEnd: (CGPoint) -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if reduceTransparency {
                Circle().fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.9))
            } else {
                OrbGlassMaterial()
                Circle().fill(RadialGradient(colors: [.white.opacity(0.45), .white.opacity(0.04), .black.opacity(0.14)],
                    center: .init(x: 0.28 + motion.refraction.width / 60, y: 0.22 + motion.refraction.height / 60),
                    startRadius: 0, endRadius: 56))
                // Reflected light moves inside a fixed circular silhouette.
                Ellipse().fill(.white.opacity(0.68)).frame(width: 27, height: 9)
                    .blur(radius: 1.8).rotationEffect(.degrees(-32))
                    .offset(x: -9 + motion.refraction.width, y: -16 + motion.refraction.height)
                Circle().stroke(.white.opacity(0.32), lineWidth: 4)
                    .blur(radius: 2).padding(4)
                    .offset(x: motion.refraction.width * 0.6, y: motion.refraction.height * 0.6)
            }
            Image(systemName: "plus").font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                .offset(x: motion.refraction.width * 0.2, y: motion.refraction.height * 0.2)
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.15), .white.opacity(0.5)],
            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .shadow(color: .black.opacity(motion.isDragging ? 0.2 : 0.13), radius: motion.isDragging ? 7 : 4, y: 3)
        .overlay(OrbPointerSurface(onOpen: onOpen, onBegin: onDragBegin, onChange: onDragChange, onEnd: onDragEnd))
        .brightness(hovered && !reduceMotion ? 0.035 : 0)
        .onHover { hovered = $0 }
        .help("Add a word · Drag to move")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vord quick add")
        .accessibilityHint("Opens quick add. Drag to position at either screen edge.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }
}

private struct OrbGlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = OrbEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}

private final class OrbEffectView: NSVisualEffectView {
    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
    }
}

private struct OrbPointerSurface: NSViewRepresentable {
    var onOpen: () -> Void
    var onBegin: (CGPoint) -> Void
    var onChange: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void
    func makeNSView(context: Context) -> OrbPointerView { let view = OrbPointerView(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: OrbPointerView, context: Context) {
        view.onOpen = onOpen; view.onBegin = onBegin; view.onChange = onChange; view.onEnd = onEnd
    }
}

private final class OrbPointerView: NSView {
    var onOpen: (() -> Void)?
    var onBegin: ((CGPoint) -> Void)?
    var onChange: ((CGPoint) -> Void)?
    var onEnd: ((CGPoint) -> Void)?
    private var start = CGPoint.zero
    private var dragged = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let delta = CGPoint(x: local.x - bounds.midX, y: local.y - bounds.midY)
        return delta.x * delta.x + delta.y * delta.y <= bounds.width * bounds.width / 4 ? self : nil
    }
    override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if !dragged {
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            dragged = true; onBegin?(start)
        }
        onChange?(point)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { onEnd?(NSEvent.mouseLocation) } else { onOpen?() }
        dragged = false
    }
}
