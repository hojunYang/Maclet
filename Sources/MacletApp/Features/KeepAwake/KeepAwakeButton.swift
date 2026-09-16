import SwiftUI

struct KeepAwakeButton: View {
    let isEnabled: Bool
    let isChanging: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                CommandCenterFeatureLabel(
                    title: "Keep\nAwake",
                    systemName: "laptopcomputer",
                    isActive: isEnabled
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CommandCenterMetrics.featureCardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .controlCenterSurface(
                cornerRadius: CommandCenterMetrics.featureCardCornerRadius,
                isActive: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isChanging)
        .help(isEnabled ? "Allow to sleep" : "Keep awake")
    }
}
