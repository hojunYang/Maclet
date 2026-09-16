import AppKit
import SwiftUI
import MacletCore

enum MacletSystemColors {
    static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var textBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var label: Color { Color(nsColor: .labelColor) }
    static var secondaryLabel: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiaryLabel: Color { Color(nsColor: .tertiaryLabelColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
}

struct IconButton: View {
    let systemName: String
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct StatusDot: View {
    let status: CommandRunStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status.rawValue)
    }

    private var color: Color {
        switch status {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .timedOut:
            return .orange
        case .cancelled:
            return .gray
        case .adminFailed:
            return .purple
        }
    }
}

struct StatusBadge: View {
    let status: CommandRunStatus

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: status)
            Text(status.rawValue)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

struct PanelHeader: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemName: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = NSAppearance(named: .vibrantDark)
    }
}

extension View {
    func panelStyle() -> some View {
        padding(12)
            .background(
                MacletSystemColors.controlBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MacletSystemColors.separator.opacity(0.8))
            }
            .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
    }

    func macletModals(presentsEditor: Bool = true) -> some View {
        modifier(MacletModalModifier(presentsEditor: presentsEditor))
    }
}

extension Color {
    func mix(with color: Color, by amount: Double) -> Color {
        let fraction = min(max(amount, 0), 1)
        let baseColor = NSColor(self)
        let mixedColor = baseColor.blended(withFraction: fraction, of: NSColor(color)) ?? baseColor
        return Color(nsColor: mixedColor)
    }
}

private struct MacletModalModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    let presentsEditor: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let decoratedContent = content
            .confirmationDialog(
                "Run command?",
                isPresented: Binding(
                    get: { appState.pendingConfirmation != nil },
                    set: { if !$0 { appState.pendingConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Run") {
                    appState.runPendingConfirmation()
                }

                Button("Cancel", role: .cancel) {
                    appState.pendingConfirmation = nil
                }
            } message: {
                Text(appState.pendingConfirmation?.command ?? "")
            }

        if presentsEditor {
            decoratedContent
                .sheet(item: $appState.editorDraft) { draft in
                    CommandEditorView(draft: draft)
                        .environmentObject(appState)
                }
        } else {
            decoratedContent
        }
    }
}
