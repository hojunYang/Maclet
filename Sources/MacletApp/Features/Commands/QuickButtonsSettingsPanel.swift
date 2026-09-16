import SwiftUI
import MacletCore

struct QuickButtonsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Buttons")
                    .font(.headline)

                Spacer()

                Button {
                    appState.beginAddCommand()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if appState.commands.isEmpty {
                EmptyStateView(title: "No commands", systemName: "terminal")
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.commands) { command in
                        QuickButtonCommandRow(command: command)
                    }
                }
            }
        }
        .panelStyle()
    }
}

private struct QuickButtonCommandRow: View {
    @EnvironmentObject private var appState: AppState
    let command: SavedCommand

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(command.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(command.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("Show as Button", isOn: Binding(
                get: { command.isFavorite },
                set: { appState.setCommandFavorite(command, isFavorite: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()

            IconButton(systemName: "square.and.pencil", title: "Edit") {
                appState.beginEdit(command)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
