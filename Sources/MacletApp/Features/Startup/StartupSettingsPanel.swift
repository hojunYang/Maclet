import SwiftUI

struct StartupPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Start at Login", systemImage: "power")
                    .font(.headline)

                Spacer()

                Badge(text: appState.loginItemState.badgeTitle, color: appState.loginItemState.badgeColor)

                Toggle("Start at Login", isOn: Binding(
                    get: { appState.loginItemEnabled },
                    set: { appState.toggleLoginItem($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if let message = appState.loginItemState.detailMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.loginItemState == .requiresApproval {
                Button {
                    appState.openLoginItemsSettings()
                } label: {
                    Label("Open Login Items Settings", systemImage: "gearshape")
                }
            }
        }
        .panelStyle()
        .onAppear {
            appState.refreshLoginItemState()
        }
    }
}

private extension LoginItemState {
    var badgeTitle: String {
        switch self {
        case .enabled:
            return "ON"
        case .disabled:
            return "OFF"
        case .requiresApproval:
            return "APPROVAL"
        case .unavailable:
            return "UNAVAILABLE"
        }
    }

    var badgeColor: Color {
        switch self {
        case .enabled:
            return .green
        case .disabled:
            return .gray
        case .requiresApproval:
            return .orange
        case .unavailable:
            return .red
        }
    }

    var detailMessage: String? {
        switch self {
        case .enabled:
            return "Maclet will open automatically when you log in."
        case .disabled:
            return nil
        case .requiresApproval:
            return "Approval is required in macOS Login Items."
        case .unavailable:
            return "Run Maclet from the packaged app before enabling this."
        }
    }
}
