import AppKit
import Combine
import SwiftUI
import MacletCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var presentationCoordinator: AppPresentationCoordinator?
    private var alertWindowController: AlertWindowController?
    private let cleanKeyboardController = CleanKeyboardController()
    private var keyboardShortcutMonitor: Any?
    private var globalHotKeyManager: GlobalHotKeyManager?
    private var globalShortcutCancellable: AnyCancellable?
    private var isUserConfirmedTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureQuitShortcutMonitor()

        if let renderURL = renderPopoverURL {
            Task {
                await SharedAppState.value.bootstrapIfNeeded()
                SharedAppState.value.refreshClipboard()
                renderPopover(to: renderURL)
                terminateWithoutConfirmation(nil)
            }
            return
        }

        presentationCoordinator = AppPresentationCoordinator(
            appState: SharedAppState.value,
            cleanKeyboard: { [weak self] in
                self?.cleanKeyboardController.begin()
            },
            quitApplication: { [weak self] in
                self?.terminateApplication(nil)
            }
        )

        alertWindowController = AlertWindowController(appState: SharedAppState.value)
        configureGlobalShortcut()

        Task {
            await SharedAppState.value.bootstrapIfNeeded()
        }

        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.presentationCoordinator?.showCommandCenter()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForTermination()
        if let keyboardShortcutMonitor {
            NSEvent.removeMonitor(keyboardShortcutMonitor)
            self.keyboardShortcutMonitor = nil
        }
        globalShortcutCancellable = nil
        globalHotKeyManager = nil
        presentationCoordinator = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isUserConfirmedTermination || confirmTermination() else {
            return .terminateCancel
        }

        prepareForTermination()
        return .terminateNow
    }

    private func configureMainMenu() {
        AppMenuBuilder.configure(
            settingsTarget: self,
            settingsAction: #selector(showSettings(_:)),
            quitTarget: self,
            quitAction: #selector(terminateApplication(_:)),
            closeTarget: self,
            closeAction: #selector(closeActiveWindow(_:))
        )
    }

    @objc private func showSettings(_ sender: Any?) {
        presentationCoordinator?.showManagementWindow(tab: .settings)
    }

    private func configureQuitShortcutMonitor() {
        keyboardShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.isCommandQShortcut {
                self?.terminateApplication(nil)
                return nil
            }

            if event.isCommandWShortcut {
                self?.closeActiveWindow(nil)
                return nil
            }

            if event.isEscapeKey {
                if self?.cancelActiveInteraction() == true {
                    return nil
                }
            }

            return event
        }
    }

    private func configureGlobalShortcut() {
        let manager = GlobalHotKeyManager { [weak self] in
            self?.presentationCoordinator?.toggleCommandCenter()
        }
        globalHotKeyManager = manager

        globalShortcutCancellable = Publishers.CombineLatest(
            SharedAppState.value.$settings.map(\.commandCenterShortcut),
            SharedAppState.value.$isRecordingGlobalShortcut
        )
            .removeDuplicates { previous, current in
                previous.0 == current.0 && previous.1 == current.1
            }
            .sink { shortcut, isRecording in
                let error = manager.setShortcut(isRecording ? nil : shortcut)
                SharedAppState.value.setGlobalShortcutRegistrationError(error)
            }
    }

    @objc private func terminateApplication(_ sender: Any?) {
        guard confirmTermination() else {
            return
        }

        isUserConfirmedTermination = true
        NSApp.terminate(sender)
    }

    private func terminateWithoutConfirmation(_ sender: Any?) {
        isUserConfirmedTermination = true
        NSApp.terminate(sender)
    }

    @objc private func closeActiveWindow(_ sender: Any?) {
        let keyWindow = NSApp.keyWindow
        if presentationCoordinator?.closeSurface(for: keyWindow) == true {
            return
        }

        if let keyWindow {
            keyWindow.performClose(sender)
        }
    }

    private func cancelActiveInteraction() -> Bool {
        let appState = SharedAppState.value

        if appState.alert != nil {
            appState.alert = nil
            return true
        }

        if appState.pendingConfirmation != nil {
            appState.pendingConfirmation = nil
            return true
        }

        if appState.editorDraft != nil {
            appState.editorDraft = nil
            return true
        }

        if presentationCoordinator?.dismissCommandCenterIfActive() == true {
            return true
        }

        return false
    }

    private func prepareForTermination() {
        SharedAppState.value.prepareForTermination()
    }

    private func confirmTermination() -> Bool {
        let runningCommandCount = SharedAppState.value.runningCommandCount
        let hasActiveTimer = SharedAppState.value.hasActiveTimer

        let alert = NSAlert()
        alert.alertStyle = runningCommandCount > 0 || hasActiveTimer ? .warning : .informational
        alert.messageText = "Maclet을 종료하시겠습니까?"
        if runningCommandCount > 0, hasActiveTimer {
            alert.informativeText = "\(runningCommandCount)개의 명령과 타이머가 실행 중입니다. 종료하면 모두 중단됩니다."
        } else if runningCommandCount > 0 {
            alert.informativeText = "\(runningCommandCount)개의 명령이 실행 중입니다. 종료하면 실행 중인 명령이 중단됩니다."
        } else if hasActiveTimer {
            alert.informativeText = "타이머가 실행 중입니다. 종료하면 타이머가 중단됩니다."
        } else {
            alert.informativeText = "종료하면 메뉴 막대에서 Maclet이 사라집니다."
        }
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "취소")

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private var renderPopoverURL: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-popover"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private func renderPopover(to url: URL) {
        let size = CommandCenterPanelMetrics.size(for: SharedAppState.value)
        let rootView = CommandCenterView(
            presentationState: CommandCenterPresentationState(
                isPresented: true,
                animatesEntrance: false
            ),
            openManagement: { _ in },
            cleanKeyboard: {},
            quitApplication: {}
        )
            .environmentObject(SharedAppState.value)
            .frame(width: size.width, height: size.height)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        try? data.write(to: url, options: [.atomic])
    }
}

@MainActor
enum SharedAppState {
    static let value = AppState()
}

extension NSEvent {
    var isCommandQShortcut: Bool {
        guard charactersIgnoringModifiers?.lowercased() == "q" else {
            return false
        }

        let modifierFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifierFlags.contains(.command)
            && !modifierFlags.contains(.shift)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
    }

    var isCommandWShortcut: Bool {
        guard charactersIgnoringModifiers?.lowercased() == "w" else {
            return false
        }

        let modifierFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifierFlags.contains(.command)
            && !modifierFlags.contains(.shift)
            && !modifierFlags.contains(.option)
            && !modifierFlags.contains(.control)
    }

    var isEscapeKey: Bool {
        keyCode == 53
    }
}
