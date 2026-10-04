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
    @State private var visible = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || !visible)) { clock in
            let phase = reduceMotion ? 0 : clock.date.timeIntervalSinceReferenceDate
            ZStack {
                if reduceTransparency {
                    Circle().fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.94))
                } else {
                    if #available(macOS 26, *) {
                        OrbLiquidGlass(dark: colorScheme == .dark)
                    } else {
                        OrbGlassMaterial(dark: colorScheme == .dark)
                    }
                    OrbOptics(phase: phase, displacement: motion.refraction, dark: colorScheme == .dark)
                }
                eyes(phase: phase)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .shadow(color: .black.opacity(motion.isDragging ? 0.2 : 0.14), radius: motion.isDragging ? 5 : 3, y: 3)
        .overlay(OrbPointerSurface(onOpen: onOpen, onBegin: onDragBegin, onChange: onDragChange, onEnd: onDragEnd))
        .onHover { hovered = $0 }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .help("Add a word · Drag to move")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vord quick add")
        .accessibilityHint("Opens quick add. Drag to position at either screen edge.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private func eyes(phase: Double) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 7.6)
        let blink = reduceMotion || cycle > 0.18 ? 1 : max(0.2, abs(cos(cycle / 0.18 * .pi)))
        return HStack(spacing: 7) {
            Capsule().frame(width: 3.2, height: 8.5)
            Capsule().frame(width: 3.2, height: 8.5)
        }
        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.82) : Color(white: 0.2).opacity(0.82))
        .scaleEffect(x: 1, y: blink)
        .shadow(color: .white.opacity(0.28), radius: 0.4, y: 0.6)
        .offset(x: motion.refraction.width * 0.22, y: 1 + motion.refraction.height * 0.22 + (hovered ? -0.6 : 0))
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovered)
    }
}

/// The system supplies background sampling and lensing. These broad highlights
/// add spherical volume, rather than drawing a bubble outline or waves on top.
private struct OrbOptics: View {
    var phase: Double
    var displacement: CGSize
    var dark: Bool

    var body: some View {
        let drift = sin(phase * 0.32)
        ZStack {
            Circle().fill(RadialGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.62),
                .init(color: .black.opacity(dark ? 0.22 : 0.14), location: 0.87),
                .init(color: .white.opacity(0.3), location: 0.98),
                .init(color: .clear, location: 1)
            ], center: .center, startRadius: 0, endRadius: 28))
            // A soft reflected light source, with a narrow, crisp specular core.
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.76), .white.opacity(0.03)],
                startPoint: .top, endPoint: .bottom))
                .frame(width: 25, height: 11).blur(radius: 1.8)
                .rotationEffect(.degrees(-36))
                .offset(x: -9 + displacement.width * 0.5 + drift,
                        y: -15 + displacement.height * 0.5)
            Ellipse().fill(.white.opacity(0.78))
                .frame(width: 13, height: 2.6).blur(radius: 0.5)
                .rotationEffect(.degrees(-36))
                .offset(x: -11 + displacement.width * 0.5 + drift,
                        y: -18 + displacement.height * 0.5)
            // Light collecting through the opposite side of a solid glass lens.
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.52), .clear],
                center: .center, startRadius: 0, endRadius: 15))
                .frame(width: 30, height: 13).rotationEffect(.degrees(-30))
                .offset(x: 9 + displacement.width * 0.35 - drift,
                        y: 18 + displacement.height * 0.35)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@available(macOS 26, *)
private struct OrbLiquidGlass: NSViewRepresentable {
    var dark: Bool
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = OrbLiquidLensView()
        view.style = .clear
        view.tintColor = nil
        view.contentView = NSView()
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
    }
}

@available(macOS 26, *)
private final class OrbLiquidLensView: NSGlassEffectView {
    override func layout() {
        super.layout()
        cornerRadius = min(bounds.width, bounds.height) / 2
    }
}

private struct OrbGlassMaterial: NSViewRepresentable {
    var dark: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = OrbEffectView()
        view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        updateMaterial(view)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { updateMaterial(nsView) }
    private func updateMaterial(_ view: NSVisualEffectView) {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
        let opacity = dark ? 0.48 : 0.34
        if view.alphaValue != opacity { view.alphaValue = opacity }
    }
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
