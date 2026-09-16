import SwiftUI
import MacletCore

struct QuickCommandsModule: View {
    let commands: [SavedCommand]
    let runCommand: (SavedCommand) -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(CommandCenterLayout.unit), spacing: CommandCenterLayout.gap),
        count: CommandCenterLayout.quickCommandColumns
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: CommandCenterLayout.gap) {
            ForEach(commands) { command in
                QuickCommandButton(command: command) {
                    runCommand(command)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct QuickCommandButton: View {
    let command: SavedCommand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: command.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 18)

                Text(command.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .foregroundStyle(CommandCenterPalette.text)
            .padding(.horizontal, 6)
            .frame(width: CommandCenterLayout.unit, height: CommandCenterLayout.unit)
            .controlCenterSurface(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .help(command.command)
    }
}
