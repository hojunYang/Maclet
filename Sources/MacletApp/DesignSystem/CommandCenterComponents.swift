import SwiftUI

enum CommandCenterPalette {
    static let text = Color.white
    static let inactiveIconFill = Color.white.opacity(0.286)
    static let clipboardIconFill = Color.white.opacity(0.18)
    static let clipboardRowFill = Color.white.opacity(0.08)
    static let clipboardCopiedRowFill = Color.white.opacity(0.13)
}

enum CommandCenterMetrics {
    static let featureIconSize: CGFloat = 36
    static let featureSymbolSize: CGFloat = 16
    static let featureTitleSize: CGFloat = 11.5
    static let featureHeaderSpacing: CGFloat = 6
    static let featureCardPadding: CGFloat = 10
    static let featureHeaderLeadingInset: CGFloat = 14
    static let featureHeaderTopInset: CGFloat = 14
    static let featureCardCornerRadius: CGFloat = 32
    static let expandedFeatureInsets = EdgeInsets(
        top: featureHeaderTopInset,
        leading: featureCardPadding,
        bottom: featureCardPadding,
        trailing: featureCardPadding
    )
    static let actionHeight: CGFloat = 24
}

struct CommandCenterFeatureIcon: View {
    let systemName: String
    let isActive: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: CommandCenterMetrics.featureSymbolSize, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : CommandCenterPalette.text)
            .frame(
                width: CommandCenterMetrics.featureIconSize,
                height: CommandCenterMetrics.featureIconSize
            )
            .background {
                if isActive {
                    Circle().fill(Color.white)
                } else {
                    Circle().fill(CommandCenterPalette.inactiveIconFill)
                }
            }
    }
}

struct CommandCenterFeatureLabel: View {
    let title: String
    let systemName: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: CommandCenterMetrics.featureHeaderSpacing) {
            CommandCenterFeatureIcon(systemName: systemName, isActive: isActive)

            Text(title)
                .font(.system(size: CommandCenterMetrics.featureTitleSize, weight: .semibold))
                .foregroundStyle(CommandCenterPalette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)
        }
        .padding(
            .leading,
            CommandCenterMetrics.featureHeaderLeadingInset - CommandCenterMetrics.featureCardPadding
        )
    }
}

struct CommandCenterCountdownLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            .foregroundStyle(CommandCenterPalette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.numericText(countsDown: true))
    }
}

struct CommandCenterActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(CommandCenterPalette.text)
                .frame(maxWidth: .infinity, minHeight: CommandCenterMetrics.actionHeight)
                .contentShape(Capsule())
        }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .controlCenterSurface(cornerRadius: CommandCenterMetrics.actionHeight / 2)
            .help(title)
    }
}

extension View {
    func frame(size: CGSize) -> some View {
        frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    func controlCenterSurface(cornerRadius: CGFloat, isActive: Bool = false) -> some View {
        background {
            ControlCenterSurfaceBackground(cornerRadius: cornerRadius)
        }
    }
}

private struct ControlCenterSurfaceBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        MacletGlassSurface(
            cornerRadius: cornerRadius,
            style: .clear,
            fallbackMaterial: .hudWindow,
            tint: .clear
        )
        .overlay {
            shape.fill(Color.black.opacity(0.314))
        }
        .clipShape(shape)
        .contentShape(shape)
    }
}
