import SwiftUI

struct CleanKeyboardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                CommandCenterFeatureLabel(
                    title: "Clean\nKeyboard",
                    systemName: "keyboard",
                    isActive: false
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CommandCenterMetrics.featureCardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .controlCenterSurface(cornerRadius: CommandCenterMetrics.featureCardCornerRadius)
        }
        .buttonStyle(.plain)
        .help("Ignore keyboard input while cleaning")
    }
}
