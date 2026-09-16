import SwiftUI
import MacletCore

struct CommandListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var filteredCommands: [SavedCommand] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return appState.commands
        }

        return appState.commands.filter { command in
            command.title.localizedCaseInsensitiveContains(searchText)
                || command.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search commands", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    appState.beginAddCommand()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredCommands) { command in
                        CommandRow(command: command)
                    }
                }
            }
        }
    }
}

private struct CommandRow: View {
    @EnvironmentObject private var appState: AppState
    let command: SavedCommand

    private var isRunning: Bool {
        appState.runningCommandIDs.contains(command.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(command.title)
                        .font(.headline)
                        .lineLimit(1)

                    if command.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    if command.requiresAdmin {
                        Badge(text: "ADMIN", color: .orange)
                    }
                }

                Text(command.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else if let lastRun = command.lastRun {
                StatusDot(status: lastRun.status)
            }

            IconButton(systemName: "play.fill", title: "Run") {
                appState.run(command)
            }
            .disabled(isRunning)

            IconButton(systemName: "square.and.pencil", title: "Edit") {
                appState.beginEdit(command)
            }

            IconButton(systemName: "doc.on.doc", title: "Duplicate") {
                appState.duplicate(command)
            }

            IconButton(systemName: "trash", title: "Delete", role: .destructive) {
                appState.delete(command)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
