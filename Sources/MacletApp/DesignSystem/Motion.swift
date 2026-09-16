import SwiftUI

final class CommandCenterPresentationState: ObservableObject {
    @Published private(set) var isPresented: Bool
    let animatesEntrance: Bool

    init(isPresented: Bool = false, animatesEntrance: Bool = true) {
        self.isPresented = isPresented
        self.animatesEntrance = animatesEntrance
    }

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

enum MacletMotion {
    static let commandCenterContentDelay: Duration = .milliseconds(150)
    static let commandCenterDismissalDelay: Duration = .milliseconds(300)
    static let commandCenterReducedMotionDismissalDelay: Duration = .milliseconds(120)
    static let commandCenterInitialScale: CGFloat = 1.02
    static let commandCenterInitialBlur: CGFloat = 8

    static func commandCenterBackground(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : 0.16)
    }

    static func commandCenterContent(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : 0.14)
    }

    static func commandCenterDismissal(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.12 : 0.30)
    }

    static func stateChange(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(duration: 0.30, bounce: 0.08)
    }

    static func feedback(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.10)
            : .spring(duration: 0.22, bounce: 0.06)
    }

    static func layout(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.06)
    }

    static func contentTransition(
        reduceMotion: Bool,
        anchor: UnitPoint
    ) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .opacity.combined(with: .scale(scale: 0.98, anchor: anchor))
    }
}

extension View {
    @ViewBuilder
    func macletSymbolReplacement(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            contentTransition(.symbolEffect(.replace))
        }
    }
}
