import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func controlGlass(cornerRadius: CGFloat, strongBlur: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            if strongBlur {
                background(.ultraThickMaterial, in: shape)
                    .glassEffect(.regular, in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background {
                VisualEffect(material: strongBlur ? .hudWindow : .popover, blendingMode: .behindWindow)
                    .clipShape(shape)
            }
        }
    }
}

struct MacletGlassSurface: View {
    enum Style {
        case clear
        case regular
        case interactive
    }

    let cornerRadius: CGFloat
    let style: Style
    let fallbackMaterial: NSVisualEffectView.Material
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            let glass = switch style {
            case .clear:
                Glass.clear.tint(tint)
            case .regular:
                Glass.regular.tint(tint)
            case .interactive:
                Glass.regular.tint(tint).interactive()
            }

            shape
                .fill(Color.white.opacity(0.001))
                .glassEffect(glass, in: shape)
        } else {
            ZStack {
                MacletGlassFallback(material: fallbackMaterial)
                shape.fill(tint)
            }
            .clipShape(shape)
        }
    }
}

private struct MacletGlassFallback: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}
