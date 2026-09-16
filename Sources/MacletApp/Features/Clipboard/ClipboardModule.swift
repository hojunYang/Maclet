import SwiftUI

struct ClipboardModule: View {
    let payload: ClipboardPayload
    let items: [ClipboardHistoryItem]
    let copiedItemID: ClipboardHistoryItem.ID?
    let action: (ClipboardHistoryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CommandCenterFeatureLabel(
                    title: "Clipboard",
                    systemName: "clipboard",
                    isActive: false
                )

                Spacer(minLength: 0)
            }

            if items.isEmpty {
                Text(payload.previewText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CommandCenterPalette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(items) { item in
                            ClipboardHistoryRow(
                                item: item,
                                isCopied: item.id == copiedItemID
                            ) {
                                action(item)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(CommandCenterMetrics.expandedFeatureInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(
            cornerRadius: CommandCenterMetrics.featureCardCornerRadius,
            style: .continuous
        ))
        .controlCenterSurface(cornerRadius: CommandCenterMetrics.featureCardCornerRadius)
        .opacity(items.isEmpty && !payload.isCopyable ? 0.62 : 1)
        .help(items.isEmpty ? "No clipboard history" : "Copy clipboard history item")
    }
}

private struct ClipboardHistoryRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ClipboardHistoryItem
    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCopied ? "checkmark" : item.payload.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CommandCenterPalette.text)
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(isCopied ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(CommandCenterPalette.clipboardIconFill))
                }
                .macletSymbolReplacement(reduceMotion: reduceMotion)

            Text(isCopied ? "Copied" : item.payload.previewText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CommandCenterPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(isCopied ? CommandCenterPalette.clipboardCopiedRowFill : CommandCenterPalette.clipboardRowFill)
        }
        .onTapGesture(perform: action)
    }
}

private extension ClipboardPayload {
    var previewText: String {
        switch self {
        case .empty:
            return "Empty Clipboard"
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Empty Clipboard" : trimmed
        case .image:
            return "🖼 image.."
        case .unsupported:
            return "Unsupported Clipboard"
        }
    }

    var symbolName: String {
        switch self {
        case .empty:
            return "clipboard"
        case .text:
            return "doc.on.clipboard"
        case .image:
            return "photo"
        case .unsupported:
            return "questionmark"
        }
    }
}
