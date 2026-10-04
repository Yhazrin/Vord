import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class OrbMotion: ObservableObject {
    @Published private(set) var refraction = CGSize.zero
    @Published private(set) var isDragging = false
    @Published private(set) var returnedAt: Double?
    @Published private(set) var returnedSuccessfully = false
    @Published var activity: OrbActivity = .idle
    func didReturn(successful: Bool) {
        returnedSuccessfully = successful
        returnedAt = Date().timeIntervalSinceReferenceDate
    }
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
    var embedded = false
    var lensSize = CGSize(width: 56, height: 56)
    var lensRadius: CGFloat = 28
    var faceOpacity: Double = 1
    var opticsOpacity: Double = 1
    @State private var hovered = false
    @State private var visible = false
    @State private var pointerOffset = CGSize.zero
    @State private var appearedAt = Date().timeIntervalSinceReferenceDate
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: lensRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.94))
            } else if #available(macOS 26, *) {
                // Keep the live compositor surface out of SwiftUI masks, blur and
                // shadow passes. AppKit owns its curved edge and optical response.
                OrbLiquidGlass(dark: colorScheme == .dark, interactive: !reduceMotion, radius: lensRadius,
                    onOpen: onOpen, onBegin: onDragBegin, onChange: onDragChange,
                    onEnd: onDragEnd, onPointer: trackPointer)
            } else {
                OrbGlassMaterial(dark: colorScheme == .dark, radius: lensRadius)
                    .shadow(color: .black.opacity(0.09), radius: 4, y: 2)
            }
            TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || !visible)) { clock in
                let phase = clock.date.timeIntervalSinceReferenceDate
                ZStack {
                    if !reduceTransparency {
                        OrbOptics(phase: reduceMotion ? 0 : phase, displacement: CGSize(width: motion.refraction.width + pointerOffset.width,
                            height: motion.refraction.height + pointerOffset.height))
                            .opacity(opticsOpacity)
                    }
                    eyes(phase: phase).opacity(faceOpacity)
                }
                // The mask belongs to the lens bounds, not the face's intrinsic
                // size. A small inscribed circle otherwise cuts both eyes in half.
                .frame(width: lensSize.width, height: lensSize.height)
                .clipShape(Circle())
                .allowsHitTesting(false)
            }
        }
        .frame(width: lensSize.width, height: lensSize.height)
        .overlay {
            if reduceTransparency {
                pointerSurface
            } else if #available(macOS 26, *) {
                EmptyView()
            } else {
                pointerSurface
            }
        }
        .onHover { hovered = $0 }
        .onAppear { visible = true; appearedAt = Date().timeIntervalSinceReferenceDate }
        .onDisappear { visible = false }
        .help(embedded ? "Talk with Companion · Drag to move" : "Add a word · Drag to move")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(embedded ? "Vord companion" : "Vord quick add")
        .accessibilityHint(embedded ? "Focuses the conversation. Drag out to keep it at the screen edge." : "Opens quick add. Drag to position at either screen edge.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private var pointerSurface: some View {
        OrbPointerSurface(onOpen: onOpen, onBegin: onDragBegin, onChange: onDragChange,
                          onEnd: onDragEnd, onPointer: trackPointer)
    }
    private func trackPointer(_ point: CGPoint?) {
        hovered = point != nil
        guard !reduceMotion else { return }
        withAnimation(.smooth(duration: 0.18)) {
            pointerOffset = point.map { CGSize(width: $0.x * 2.4, height: $0.y * 2.4) } ?? .zero
        }
    }

    private func eyes(phase: Double) -> some View {
        let pose = OrbFacePose.sample(elapsed: phase - appearedAt,
            returnElapsed: motion.returnedAt.map { max(0, phase - $0) },
            successful: motion.returnedSuccessfully, hovered: hovered,
            dragging: motion.isDragging, displacement: motion.refraction.width, reduced: reduceMotion,
            activity: motion.activity)
        return HStack(spacing: 9) {
            OrbEye(openness: pose.openness, smile: pose.smile)
                .stroke(style: StrokeStyle(lineWidth: 6.2, lineCap: .round))
            OrbEye(openness: pose.rightOpenness, smile: pose.smile)
                .stroke(style: StrokeStyle(lineWidth: 6.2, lineCap: .round))
        }
        .frame(width: 34, height: 24)
        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.88) : Color(white: 0.16).opacity(0.88))
        .rotationEffect(.degrees(pose.tilt))
        .offset(x: motion.refraction.width * 0.22 + pointerOffset.width * 0.8 + pose.gaze.width,
                y: 1 + motion.refraction.height * 0.22 + pointerOffset.height * 0.8 + pose.gaze.height + pose.lift)
    }

}

/// One continuous stroke turns from a vertical eye into a quiet happy arch.
private struct OrbEye: Shape {
    var openness: Double
    var smile: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(openness, smile) }
        set { openness = newValue.first; smile = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let halfHeight = 7.3 * openness * (1 - smile)
        let closed = pow(max(0, 1 - openness), 2) * (1 - smile)
        let halfWidth = 4.6 * smile + 3.8 * closed
        var path = Path()
        path.move(to: CGPoint(x: centre.x - halfWidth, y: centre.y - halfHeight + 1.4 * smile))
        path.addQuadCurve(to: CGPoint(x: centre.x + halfWidth, y: centre.y + halfHeight + 1.4 * smile),
                          control: CGPoint(x: centre.x, y: centre.y - 6.5 * smile + 1.2 * closed))
        return path
    }
}

/// The system supplies background sampling and lensing. These broad highlights
/// add spherical volume, rather than drawing a bubble outline or waves on top.
private struct OrbOptics: View {
    var phase: Double
    var displacement: CGSize

    var body: some View {
        let drift = sin(phase * 0.32)
        ZStack {
            // A soft reflected light source, with a narrow, crisp specular core.
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.01)],
                startPoint: .top, endPoint: .bottom))
                .frame(width: 25, height: 11).blur(radius: 1.8)
                .rotationEffect(.degrees(-36))
                .offset(x: -9 + displacement.width * 0.5 + drift,
                        y: -15 + displacement.height * 0.5)
            Ellipse().fill(.white.opacity(0.48))
                .frame(width: 13, height: 2.6).blur(radius: 0.5)
                .rotationEffect(.degrees(-36))
                .offset(x: -11 + displacement.width * 0.5 + drift,
                        y: -18 + displacement.height * 0.5)
            // Light collecting through the opposite side of a solid glass lens.
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.24), .clear],
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
    var interactive: Bool
    var radius: CGFloat
    var onOpen: () -> Void
    var onBegin: (CGPoint) -> Void
    var onChange: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void
    var onPointer: (CGPoint?) -> Void
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = OrbLiquidLensView()
        view.style = .clear
        view.tintColor = nil
        let pointer = OrbPointerView()
        pointer.autoresizingMask = [.width, .height]
        // Input belongs to the native glass hierarchy so its interactive effect
        // sees the control's actual pointer events, rather than a sibling overlay.
        view.contentView = pointer
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        (view as? OrbLiquidLensView)?.lensRadius = radius
        if let pointer = view.contentView as? OrbPointerView {
            pointer.onOpen = onOpen; pointer.onBegin = onBegin
            pointer.onChange = onChange; pointer.onEnd = onEnd; pointer.onPointer = onPointer
        }
        if #available(macOS 27, *) {
            if view.effectIsInteractive != interactive { view.effectIsInteractive = interactive }
        }
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
    }
}

@available(macOS 26, *)
private final class OrbLiquidLensView: NSGlassEffectView {
    var lensRadius: CGFloat = 28 {
        didSet { cornerRadius = min(lensRadius, min(bounds.width, bounds.height) / 2) }
    }
    override func layout() {
        super.layout()
        cornerRadius = min(lensRadius, min(bounds.width, bounds.height) / 2)
    }
}

private struct OrbGlassMaterial: NSViewRepresentable {
    var dark: Bool
    var radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = OrbEffectView()
        view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        updateMaterial(view)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { updateMaterial(nsView) }
    private func updateMaterial(_ view: NSVisualEffectView) {
        (view as? OrbEffectView)?.lensRadius = radius
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
        let opacity = dark ? 0.48 : 0.34
        if view.alphaValue != opacity { view.alphaValue = opacity }
    }
}

private final class OrbEffectView: NSVisualEffectView {
    var lensRadius: CGFloat = 28 {
        didSet { layer?.cornerRadius = min(lensRadius, min(bounds.width, bounds.height) / 2) }
    }
    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.cornerRadius = min(lensRadius, min(bounds.width, bounds.height) / 2)
        layer?.masksToBounds = true
    }
}

private struct OrbPointerSurface: NSViewRepresentable {
    var onOpen: () -> Void
    var onBegin: (CGPoint) -> Void
    var onChange: (CGPoint) -> Void
    var onEnd: (CGPoint) -> Void
    var onPointer: (CGPoint?) -> Void
    func makeNSView(context: Context) -> OrbPointerView { let view = OrbPointerView(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: OrbPointerView, context: Context) {
        view.onOpen = onOpen; view.onBegin = onBegin; view.onChange = onChange; view.onEnd = onEnd; view.onPointer = onPointer
    }
}

private final class OrbPointerView: NSView {
    override var isOpaque: Bool { false }
    var onOpen: (() -> Void)?
    var onBegin: ((CGPoint) -> Void)?
    var onChange: ((CGPoint) -> Void)?
    var onEnd: ((CGPoint) -> Void)?
    var onPointer: ((CGPoint?) -> Void)?
    private var pointerTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
        addTrackingArea(area); pointerTracking = area
    }
    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseMoved(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { onPointer?(nil) }
    private func trackPointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let radius = max(1, bounds.width / 2)
        let dx = (point.x - bounds.midX) / radius
        let dy = (bounds.midY - point.y) / radius
        guard dx * dx + dy * dy <= 1 else { onPointer?(nil); return }
        onPointer?(CGPoint(x: dx, y: dy))
    }
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
