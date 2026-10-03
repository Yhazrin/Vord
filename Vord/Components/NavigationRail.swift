import SwiftUI

private struct ContentExpandedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var vordContentExpanded: Bool {
        get { self[ContentExpandedKey.self] }
        set { self[ContentExpandedKey.self] = newValue }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case add
    case review
    case dictation
    case library
    case context
    case agent
    case settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .add: return "plus"
        case .review: return "arrow.triangle.2.circlepath"
        case .dictation: return "square.and.pencil"
        case .library: return "text.book.closed"
        case .context: return "text.alignleft"
        case .agent: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }

    var help: String {
        switch self {
        case .today: return "Today"
        case .add: return "Add"
        case .review: return "Review"
        case .dictation: return "Dictation"
        case .library: return "Library"
        case .context: return "Examples"
        case .agent: return "Companion"
        case .settings: return "Settings"
        }
    }
}

struct NavigationRail: View {
    @Binding var selection: AppTab
    var compact = false
    var onToggleContentSize: () -> Void
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var dueCount = 0
    @State private var iconStyle: NavigationIconStyle = .sculpted
    @State private var iconSize: CGFloat = 18
    @State private var hoveredTab: AppTab?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact {
                ChromeIconButton(symbol: "sidebar.left", help: "Hide Sidebar", action: onToggleContentSize)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(AppTypography.ui(size: 15)).foregroundStyle(AppColors.primaryText)
                    Text("vord").font(AppTypography.ui(size: 22, weight: .semibold)).tracking(-0.4)
                    Spacer(minLength: 0)
                    ChromeIconButton(symbol: "sidebar.left", help: "Hide Sidebar", action: onToggleContentSize)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !compact { groupLabel("Practice") }
                    ForEach([AppTab.today, .review, .dictation, .context, .agent]) { tab in route(tab) }
                    if !compact { groupLabel("Words").padding(.top, 14) }
                    else { Hairline().padding(.vertical, 8) }
                    ForEach([AppTab.library, .add]) { tab in route(tab) }
                }
            }.scrollIndicators(.hidden)
            if !compact {
                Button { selection = .settings } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick add").font(AppTypography.ui(size: 11))
                        Text(dependencies.settings.shortcut.title).font(AppTypography.ui(size: 12, weight: .medium))
                    }.foregroundStyle(AppColors.tertiaryText).padding(.horizontal, 8)
                }.buttonStyle(.plain).help("Configure Quick add in Settings")
            }
            route(.settings)
        }.padding(.horizontal, compact ? 8 : 10).padding(.top, 16).padding(.bottom, 12)
            .backgroundPreferenceValue(NavigationSelectionBounds.self) { anchor in
                GeometryReader { geometry in
                    if let anchor {
                        let bounds = geometry[anchor]
                        let motionReduced = reducedMotion
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColors.accentWash)
                            .frame(width: bounds.width, height: bounds.height)
                            .keyframeAnimator(initialValue: NavigationBubbleShape(), trigger: selection) { bubble, shape in
                                bubble.scaleEffect(x: motionReduced ? 1 : shape.width, y: motionReduced ? 1 : shape.height)
                            } keyframes: { _ in
                                KeyframeTrack(\.width) {
                                    CubicKeyframe(0.96, duration: 0.07)
                                    CubicKeyframe(1.015, duration: 0.12)
                                    CubicKeyframe(1, duration: 0.11)
                                }
                                KeyframeTrack(\.height) {
                                    CubicKeyframe(1.09, duration: 0.07)
                                    CubicKeyframe(0.99, duration: 0.12)
                                    CubicKeyframe(1, duration: 0.11)
                                }
                            }
                            .position(x: bounds.midX, y: bounds.midY)
                            .animation(AppMotion.navigation(reducedMotion), value: bounds)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .foregroundStyle(AppColors.primaryText)
            .animation(AppMotion.navigation(reducedMotion), value: iconStyle)
            .task { await refresh() }
            .onReceive(dependencies.settings.$navigationIconStyle) { iconStyle = $0 }
            .onReceive(dependencies.settings.$navigationIconSize) { iconSize = CGFloat($0) }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in Task { await refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: .vordLibraryDidChange)) { _ in Task { await refresh() } }
    }
    private func groupLabel(_ title: String) -> some View {
        Text(title).font(AppTypography.ui(size: 11, weight: .medium))
            .foregroundStyle(AppColors.tertiaryText).padding(.leading, 12).padding(.bottom, 8)
    }
    private func route(_ tab: AppTab) -> some View {
        Button { selection = tab } label: {
            HStack(spacing: iconStyle == .sculpted ? 6 : 8) {
                NavigationIcon(tab: tab, style: iconStyle, size: iconSize, selected: selection == tab, hovering: hoveredTab == tab)
                if !compact { Text(tab.help).font(AppTypography.ui(size: 13, weight: selection == tab ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.85) }
                if !compact, tab == .review, dueCount > 0 {
                    Text(dueCount > 99 ? "99+" : "\(dueCount)").font(AppTypography.ui(size: 10, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(dueCount)))
                        .animation(AppMotion.feedback(reducedMotion), value: dueCount)
                }
                if !compact { Spacer(minLength: 0) }
            }.foregroundStyle(selection == tab ? AppColors.accent : AppColors.secondaryText)
                .padding(.horizontal, compact ? 0 : 8).frame(maxWidth: .infinity).frame(height: max(36, iconSize + 10))
                .overlay(alignment: .topTrailing) {
                    if compact, tab == .review, dueCount > 0 {
                        Circle().fill(AppColors.primaryText).frame(width: 5, height: 5).padding(5)
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(MotionPressStyle())
            .onHover { hovering in
                if hovering { hoveredTab = tab }
                else if hoveredTab == tab { hoveredTab = nil }
            }
            .anchorPreference(key: NavigationSelectionBounds.self, value: .bounds) { selection == tab ? $0 : nil }
            .accessibilityLabel(tab == .review ? "Review, \(dueCount) words due" : tab.help)
            .help(tab == .review ? "\(dueCount) words due" : tab.help)
    }
    private func refresh() async { dueCount = (try? await dependencies.repository.todaySummary(now: Date()).dueCount) ?? 0 }
}

private struct NavigationBubbleShape {
    var width: CGFloat = 1
    var height: CGFloat = 1
}

private struct NavigationSelectionBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

struct ChromeIconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(AppTypography.ui(size: 13, weight: .medium))
                .foregroundStyle(hovering ? AppColors.primaryText : AppColors.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(hovering ? AppColors.hover : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
        .buttonStyle(MotionPressStyle())
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(reducedMotion ? nil : AppMotion.quick, value: hovering)
    }
}
