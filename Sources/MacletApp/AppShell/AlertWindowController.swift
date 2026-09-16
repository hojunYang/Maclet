import AppKit
import Combine

@MainActor
final class AlertWindowController {
    private let appState: AppState
    private var cancellable: AnyCancellable?
    private var presentedAlertID: UUID?

    init(appState: AppState) {
        self.appState = appState

        cancellable = appState.$alert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alert in
                guard let alert else {
                    return
                }

                self?.show(alert)
            }
    }

    private func show(_ appAlert: AppAlert) {
        guard presentedAlertID != appAlert.id else {
            return
        }

        presentedAlertID = appAlert.id
        let alert = makeAlert(for: appAlert)

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        if appState.alert?.id == appAlert.id {
            appState.alert = nil
        }
        presentedAlertID = nil
    }

    private func makeAlert(for appAlert: AppAlert) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = alertStyle(for: appAlert)
        alert.messageText = appAlert.title
        alert.addButton(withTitle: "OK")

        switch appAlert.messageStyle {
        case .plain:
            alert.informativeText = appAlert.message
        case .monospaced:
            alert.informativeText = "Command output:"
            alert.accessoryView = monospacedMessageView(appAlert.message)
        }

        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        return alert
    }

    private func monospacedMessageView(_ message: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = message
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        return scrollView
    }

    private func alertStyle(for appAlert: AppAlert) -> NSAlert.Style {
        let searchableText = "\(appAlert.title) \(appAlert.message)".lowercased()
        let warningTerms = [
            "failed",
            "failure",
            "error",
            "not saved",
            "authorization",
            "requires approval",
            "could not",
            "cannot"
        ]

        if warningTerms.contains(where: searchableText.contains) {
            return .warning
        }

        return .informational
    }
}
