import SwiftUI

struct ContentSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { ContentSurfaceBackground(woodGrain: settings.woodGrainEnabled) }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.content, style: .continuous))
    }
}

struct PageScroll<Content: View>: View {
    var width: CGFloat = AppSpacing.measure
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: width, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .modifier(PageInset(bottom: AppSpacing.xxl))
        }
    }
}

struct PageColumn<Content: View>: View {
    var width: CGFloat = AppSpacing.measure
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content()
                    .frame(maxWidth: width, minHeight: max(0, geometry.size.height - 80), alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .modifier(PageInset(bottom: AppSpacing.lg))
            }
        }
    }
}

struct PageInset: ViewModifier {
    @Environment(\.vordContentExpanded) private var contentExpanded
    @Environment(\.vordLayout) private var layout
    var top: CGFloat = AppSpacing.xl
    var bottom: CGFloat = AppSpacing.xxl

    func body(content: Content) -> some View {
        content
            .padding(.top, top + (contentExpanded ? 12 : 0))
            .padding(.bottom, bottom)
            .padding(.horizontal, layout.pagePadding)
    }
}

struct PageHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.primaryText)
                .tracking(-0.4)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AdaptiveColumns<Content: View>: View {
    var horizontal: Bool
    var spacing: CGFloat = AppSpacing.lg
    @ViewBuilder var content: () -> Content
    var body: some View {
        if horizontal {
            HStack(alignment: .top, spacing: spacing, content: content)
        } else {
            VStack(alignment: .leading, spacing: spacing, content: content)
        }
    }
}

struct SectionHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.secondaryText)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SectionBlock<Content: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: title, detail: detail)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ControlRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                label
                control().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                label
                control()
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: AppSpacing.controlHeight + AppSpacing.lg)
    }

    private var label: some View {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.primaryText)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.subtleBorder)
            .frame(height: 1)
    }
}

/// Separator inside a settings module. It stays inset from the card edge and
/// lighter than a page divider, so a row does not look underlined.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.hairline.opacity(0.72))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }
}

/// Parallel choices with the same structure as a system segmented control:
/// a recessed track and a raised selected segment. The system control stays
/// short, so these labels get the same height as the rest of Vord’s controls.
struct ChoiceTabs<Selection: Hashable>: View {
    var name: String
    @Binding var selection: Selection
    var choices: [Selection]
    var label: (Selection) -> String
    var fillsWidth = false
    @Namespace private var selectionSpace
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(choices, id: \.self) { choice in
                let selected = selection == choice
                Button {
                    selection = choice
                } label: {
                    Text(label(choice))
                        .font(AppTypography.ui(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppColors.primaryText : AppColors.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(AppColors.elevatedSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(AppColors.hairline.opacity(0.9), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "choice", in: selectionSpace)
                            }
                        }
                }
                .buttonStyle(MotionPressStyle())
                .accessibilityLabel(label(choice))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppColors.inputSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(AppMotion.navigation(reducedMotion), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }
}

struct FieldChrome<Content: View>: View {
    var focused: Bool = false
    var minHeight: CGFloat = AppSpacing.controlHeight
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        content()
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background(
                AppColors.inputSurface,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(focused ? AppColors.accentNeutral.opacity(0.38) : AppColors.subtleBorder, lineWidth: 1)
            )
            .animation(reducedMotion ? nil : AppMotion.quick, value: focused)
    }
}

struct LineField: View {
    var title: String
    @Binding var text: String
    var placeholder: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder ?? title).foregroundStyle(AppColors.tertiaryText)
            )
            .textFieldStyle(.plain)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.primaryText)
            .padding(.vertical, AppSpacing.sm)
            .overlay(alignment: .bottom) {
                Hairline()
            }
        }
    }
}

struct MenuSelect<Selection: Hashable>: View {
    var name: String
    @Binding var selection: Selection
    var choices: [Selection]
    var label: (Selection) -> String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        NativeMenuSelect(name: name, selection: $selection, choices: choices, label: label, isEnabled: isEnabled)
            .frame(width: controlWidth, height: AppSpacing.controlHeight)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var controlWidth: CGFloat {
        let textWidth = (label(selection) as NSString).size(withAttributes: [.font: AppTypography.nativeUI(size: 13, weight: .medium)]).width
        return min(360, max(88, ceil(textWidth) + 46))
    }
}

struct VordButton: View {
    enum Role {
        case primary
        case secondary
        case subtle
        case destructive
    }

    var title: String
    var role: Role = .primary
    var expands: Bool = false
    var shortcut: KeyboardShortcut?
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.button)
                .foregroundStyle(foreground)
                .padding(.horizontal, AppSpacing.md)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(height: AppSpacing.controlHeight)
                .background(background)
                .overlay(border)
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(MotionPressStyle())
        .modifier(ShortcutModifier(shortcut: shortcut))
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.38)
        .animation(reducedMotion ? nil : AppMotion.quick, value: hovering)
    }

    private var foreground: Color {
        switch role {
        case .primary:
            return AppColors.primaryButtonText
        case .secondary:
            return AppColors.primaryText
        case .subtle:
            return hovering ? AppColors.primaryText : AppColors.secondaryText
        case .destructive:
            return AppColors.destructive
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            .fill(fill)
    }

    private var fill: Color {
        switch role {
        case .primary:
            return hovering ? AppColors.primaryButton.opacity(0.88) : AppColors.primaryButton
        case .secondary:
            return hovering ? AppColors.accentWash.opacity(0.8) : AppColors.selected
        case .subtle:
            return hovering ? AppColors.hover : .clear
        case .destructive:
            return hovering ? AppColors.hover : .clear
        }
    }

    @ViewBuilder
    private var border: some View {
        if role == .destructive {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(hovering ? AppColors.destructive.opacity(0.45) : AppColors.subtleBorder, lineWidth: 1)
        }
    }
}

struct PrimaryButton: View {
    var title: String
    var shortcut: KeyboardShortcut?
    var action: () -> Void

    init(title: String, shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        VordButton(title: title, role: .primary, shortcut: shortcut, action: action)
    }
}

struct QuietButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        VordButton(title: title, role: .secondary, action: action)
    }
}

struct SubtleButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        VordButton(title: title, role: .subtle, action: action)
    }
}

struct MotionPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reducedMotion ? 1 : configuration.isPressed ? 0.975 : 1)
            .animation(AppMotion.feedback(reducedMotion), value: configuration.isPressed)
    }
}

private struct ShortcutModifier: ViewModifier {
    var shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}
