import SwiftUI

private enum EditorStyle {
    static let cornerRadius: CGFloat = 8

    static var border: Color {
        MacletSystemColors.separator.opacity(0.55)
    }
}

struct CommandEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: CommandDraft
    @FocusState private var focusedField: Field?

    private enum Field {
        case title, workingDirectory, command, environment
    }

    init(draft: CommandDraft) {
        _draft = State(initialValue: draft)
    }

    private var isEditing: Bool {
        !draft.title.isEmpty
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var symbolName: String {
        let value = draft.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "terminal" : value
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                generalSection
                commandSection
                runtimeSection
                optionsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            footer
        }
        .frame(width: 540, height: 600)
        .background(MacletSystemColors.windowBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(MacletSystemColors.secondaryLabel)
                .frame(width: 48, height: 48)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EditorStyle.border, lineWidth: 1)
                }
                .macletSymbolReplacement(reduceMotion: reduceMotion)
                .animation(MacletMotion.feedback(reduceMotion: reduceMotion), value: symbolName)

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Edit Command" : "New Command")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MacletSystemColors.label)

                Text(draft.title.isEmpty ? "Set up a new shortcut" : draft.title)
                    .font(.system(size: 12))
                    .foregroundStyle(MacletSystemColors.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button("Cancel") {
                appState.editorDraft = nil
                dismiss()
            }
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                appState.saveDraft(draft)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(MacletSystemColors.label.opacity(0.85))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section {
            TextField("Title", text: $draft.title, prompt: Text("Deploy to staging"))
                .focused($focusedField, equals: .title)

            LabeledContent("Icon") {
                IconPickerButton(symbolName: $draft.symbolName)
            }

            TextField("Working Directory", text: $draft.workingDirectory, prompt: Text("~/Projects/app"))
                .font(.system(.body, design: .monospaced))
                .focused($focusedField, equals: .workingDirectory)
        } header: {
            sectionHeader("General")
        }
    }

    private var commandSection: some View {
        Section {
            CodeEditor(
                text: $draft.command,
                placeholder: "echo \"Hello, world\"",
                minHeight: 120
            )
            .focused($focusedField, equals: .command)
        } header: {
            sectionHeader("Command")
        } footer: {
            Text("The shell command to execute when this shortcut runs.")
                .font(.system(size: 11))
                .foregroundStyle(MacletSystemColors.tertiaryLabel)
        }
    }

    private var runtimeSection: some View {
        Section {
            LabeledContent("Timeout") {
                HStack(spacing: 12) {
                    Slider(value: $draft.timeoutSeconds, in: 1...3600, step: 1)
                        .tint(MacletSystemColors.secondaryLabel)
                        .frame(maxWidth: 220)

                    Text("\(Int(draft.timeoutSeconds))s")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(MacletSystemColors.secondaryLabel)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Environment")
                    .font(.system(size: 12))
                    .foregroundStyle(MacletSystemColors.secondaryLabel)

                CodeEditor(
                    text: $draft.environmentText,
                    placeholder: "KEY=value",
                    minHeight: 64
                )
                .focused($focusedField, equals: .environment)
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader("Runtime")
        }
    }

    private var optionsSection: some View {
        Section {
            OptionToggle(
                title: "Favorite",
                subtitle: "Pin to the top of your list",
                systemName: "star",
                isOn: $draft.isFavorite
            )
            OptionToggle(
                title: "Ask before running",
                subtitle: "Show a confirmation prompt first",
                systemName: "checkmark.shield",
                isOn: $draft.requiresConfirmation
            )
            OptionToggle(
                title: "Administrator authorization",
                subtitle: "Run with elevated privileges",
                systemName: "lock.shield",
                isOn: $draft.requiresAdmin
            )
        } header: {
            sectionHeader("Options")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(MacletSystemColors.secondaryLabel)
    }
}

// MARK: - Code editor with placeholder

private struct CodeEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
            .foregroundStyle(MacletSystemColors.label)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: EditorStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EditorStyle.cornerRadius, style: .continuous)
                    .stroke(EditorStyle.border, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(MacletSystemColors.tertiaryLabel)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Option toggle row

private struct OptionToggle: View {
    let title: String
    let subtitle: String
    let systemName: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? MacletSystemColors.label : MacletSystemColors.secondaryLabel)
                    .frame(width: 26, height: 26)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(EditorStyle.border, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(MacletSystemColors.label)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(MacletSystemColors.secondaryLabel)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(MacletSystemColors.secondaryLabel)
        .padding(.vertical, 2)
    }
}

// MARK: - Icon picker

private struct IconPickerButton: View {
    @Binding var symbolName: String
    @State private var isPresented = false

    private var resolved: String {
        let value = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "terminal" : value
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: resolved)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MacletSystemColors.label)
                    .frame(width: 22, height: 22)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacletSystemColors.tertiaryLabel)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: EditorStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EditorStyle.cornerRadius, style: .continuous)
                    .stroke(EditorStyle.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            IconPickerGrid(selection: $symbolName, resolved: resolved) {
                isPresented = false
            }
        }
    }
}

private struct IconPickerGrid: View {
    @Binding var selection: String
    let resolved: String
    let dismiss: () -> Void

    @State private var query = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 7)

    private var symbols: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return CommandSymbolCatalog.all
        }
        return CommandSymbolCatalog.all.filter { $0.contains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacletSystemColors.secondaryLabel)

                TextField("Search symbols", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: EditorStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EditorStyle.cornerRadius, style: .continuous)
                    .stroke(EditorStyle.border, lineWidth: 1)
            }

            ScrollView {
                if symbols.isEmpty {
                    Text("No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(MacletSystemColors.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(symbols, id: \.self) { symbol in
                            IconPickerCell(symbol: symbol, isSelected: symbol == resolved) {
                                selection = symbol
                                dismiss()
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: 240)
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct IconPickerCell: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? MacletSystemColors.label : MacletSystemColors.secondaryLabel)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(MacletSystemColors.label.opacity(0.12))
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(EditorStyle.border, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(symbol)
    }
}

private enum CommandSymbolCatalog {
    static let all: [String] = [
        "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "command", "keyboard", "apple.terminal",
        "bolt", "bolt.fill", "play", "play.fill", "arrow.clockwise", "arrow.triangle.2.circlepath", "hammer", "wrench.and.screwdriver", "gearshape", "gearshape.2", "slider.horizontal.3", "wand.and.stars",
        "folder", "folder.fill", "doc", "doc.fill", "doc.text", "tray", "tray.full", "archivebox", "shippingbox", "externaldrive", "internaldrive", "sdcard",
        "network", "wifi", "antenna.radiowaves.left.and.right", "globe", "cloud", "icloud", "server.rack", "cable.connector", "personalhotspot",
        "lock", "lock.fill", "lock.shield", "key", "checkmark.shield", "exclamationmark.shield", "eye", "eye.slash", "touchid", "faceid",
        "trash", "trash.fill", "xmark.bin", "paintbrush", "scissors", "square.and.arrow.up", "square.and.arrow.down", "arrow.down.circle", "arrow.up.circle",
        "moon.zzz", "sun.max", "powersleep", "power", "battery.100", "cpu", "memorychip", "desktopcomputer", "laptopcomputer", "display",
        "clipboard", "doc.on.clipboard", "list.bullet", "checklist", "calendar", "clock", "timer", "stopwatch", "bell", "tag",
        "star", "star.fill", "heart", "flag", "bookmark", "pin", "paperplane", "envelope", "message", "bubble.left",
        "magnifyingglass", "camera", "photo", "video", "mic", "speaker.wave.2", "music.note", "headphones",
        "person", "person.2", "gamecontroller", "cart", "creditcard", "bag", "house", "building.2", "map", "location"
    ]
}
