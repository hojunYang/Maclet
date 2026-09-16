import SwiftUI
import MacletCore

struct RunLogView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Run History")
                        .font(.headline)
                    Spacer()
                    IconButton(systemName: "trash", title: "Clear", role: .destructive) {
                        appState.clearRunHistory()
                    }
                }

                if appState.runHistory.isEmpty {
                    EmptyStateView(title: "No command output yet", systemName: "clock")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.runHistory) { run in
                                Button {
                                    appState.selectedLogID = run.id
                                } label: {
                                    LogListItem(run: run, isSelected: appState.selectedLog?.id == run.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 240)
            .panelStyle()

            LogDetailView(run: appState.selectedLog)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panelStyle()
        }
    }
}

private struct LogListItem: View {
    let run: CommandRunRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: run.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.commandTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(run.startedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LogDetailView: View {
    let run: CommandRunRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let run {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.commandTitle)
                            .font(.headline)
                        Text(run.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    StatusBadge(status: run.status)
                }

                HStack(spacing: 16) {
                    MetricRow(title: "Exit", value: run.exitCode.map(String.init) ?? "-")
                    MetricRow(title: "Time", value: String(format: "%.2fs", run.duration))
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        OutputBlock(title: "STDOUT", text: run.stdout)
                        OutputBlock(title: "STDERR", text: run.stderr)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyStateView(title: "Select a run", systemName: "terminal")
            }
        }
    }
}

private struct OutputBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MacletSystemColors.textBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MacletSystemColors.separator.opacity(0.55), lineWidth: 1)
                }
        }
    }
}
