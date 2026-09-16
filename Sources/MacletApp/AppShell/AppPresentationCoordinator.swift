import AppKit
import Combine
import SwiftUI

@MainActor
enum CommandCenterPanelMetrics {
    static func size(for appState: AppState) -> NSSize {
        let size = CommandCenterLayout.panelSize(
            featureOrder: appState.settings.featureOrder,
            enabledFeatures: appState.settings.enabledFeatures,
            quickCommandCount: appState.quickCommands.count
        )
        return NSSize(width: size.width, height: size.height)
    }
}

enum StatusItemActivationDecision: Equatable {
    case focusManagementWindow
    case hideCommandCenter
    case showCommandCenter

    static func resolve(
        managementWindowIsPresented: Bool,
        commandCenterIsActive: Bool
    ) -> Self {
        if managementWindowIsPresented {
            return .focusManagementWindow
        }

        if commandCenterIsActive {
            return .hideCommandCenter
        }

        return .showCommandCenter
    }
}

enum CommandCenterDismissalDecision {
    static func shouldDismiss(
        isActive: Bool,
        isAppModalPresented: Bool,
        eventIsInsidePanel: Bool,
        eventIsStatusItem: Bool
    ) -> Bool {
        isActive
            && !isAppModalPresented
            && !eventIsInsidePanel
            && !eventIsStatusItem
    }
}

enum ManagementWindowPresentationPolicy {
    static let presentedActivationPolicy: NSApplication.ActivationPolicy = .regular
    static let dismissedActivationPolicy: NSApplication.ActivationPolicy = .accessory
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .auxiliary,
        .managed,
        .participatesInCycle,
        .fullScreenNone,
        .fullScreenDisallowsTiling
    ]
}

enum StatusItemPresentation {
    static func text(
        timerRemainingSeconds: Int?,
        timerIsPaused: Bool,
        keepDisplayOnRemainingSeconds: Int?,
        keepDisplayOnIsInfinite: Bool
    ) -> String? {
        if let timerRemainingSeconds {
            let text = CountdownText.clock(seconds: timerRemainingSeconds)
            return timerIsPaused ? "⏸ \(text)" : text
        }

        if keepDisplayOnIsInfinite {
            return "∞"
        }

        return keepDisplayOnRemainingSeconds.map(CountdownText.clock)
    }
}

@MainActor
final class AppPresentationCoordinator {
    private let statusItemController: StatusItemController
    private let commandCenterController: CommandCenterPanelController
    private let managementWindowController: ManagementWindowController
    private let quitApplication: () -> Void

    init(
        appState: AppState,
        cleanKeyboard: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        let statusItemController = StatusItemController(appState: appState)
        let commandCenterController = CommandCenterPanelController(appState: appState)
        let managementWindowController = ManagementWindowController(appState: appState)

        self.statusItemController = statusItemController
        self.commandCenterController = commandCenterController
        self.managementWindowController = managementWindowController
        self.quitApplication = quitApplication

        statusItemController.onActivate = { [weak self] in
            self?.handleStatusItemActivation()
        }
        commandCenterController.statusButtonProvider = { [weak statusItemController] in
            statusItemController?.button
        }
        commandCenterController.openManagement = { [weak self] tab in
            self?.showManagementWindow(tab: tab)
        }
        commandCenterController.cleanKeyboard = cleanKeyboard
        commandCenterController.quitApplication = { [weak self] in
            self?.handleQuitRequest()
        }
    }

    func showCommandCenter() {
        if managementWindowController.isPresented {
            commandCenterController.hide()
            _ = managementWindowController.focusIfPresented()
            return
        }

        guard let button = statusItemController.button else {
            return
        }

        commandCenterController.show(relativeTo: button) { [weak self] in
            self?.managementWindowController.isPresented == false
        }
    }

    func toggleCommandCenter() {
        handleStatusItemActivation()
    }

    func closeSurface(for window: NSWindow?) -> Bool {
        if let window {
            if commandCenterController.closeIfWindow(window) {
                return true
            }

            if managementWindowController.closeIfWindow(window) {
                return true
            }

            return false
        }

        if commandCenterController.dismissIfActive() {
            return true
        }

        return managementWindowController.closeIfPresented()
    }

    func dismissCommandCenterIfActive() -> Bool {
        commandCenterController.dismissIfActive()
    }

    private func handleStatusItemActivation() {
        let decision = StatusItemActivationDecision.resolve(
            managementWindowIsPresented: managementWindowController.isPresented,
            commandCenterIsActive: commandCenterController.isActive
        )

        switch decision {
        case .focusManagementWindow:
            commandCenterController.hide()
            _ = managementWindowController.focusIfPresented()
        case .hideCommandCenter:
            commandCenterController.hide()
        case .showCommandCenter:
            showCommandCenter()
        }
    }

    func showManagementWindow(tab: MainTab) {
        commandCenterController.hide()
        managementWindowController.show(tab: tab)
    }

    private func handleQuitRequest() {
        commandCenterController.hide()
        quitApplication()
    }
}

@MainActor
private final class StatusItemController: NSObject {
    var onActivate: (() -> Void)?

    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(appState: AppState) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        observeStatus(appState: appState)
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button else {
            return
        }

        if let image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Maclet") {
            image.isTemplate = true
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.title = "Maclet"
        }

        statusItem.length = NSStatusItem.variableLength
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = "Maclet"
        button.target = self
        button.action = #selector(activate(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeStatus(appState: AppState) {
        Publishers.CombineLatest3(
            appState.timerManager.$phase,
            appState.keepDisplayOnManager.$activeOption,
            appState.keepDisplayOnManager.$activeUntil
        )
        .sink { [weak self, weak appState] _, _, _ in
            guard let appState else {
                return
            }
            self?.updateStatus(appState: appState, now: Date())
        }
        .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self, weak appState] now in
                guard let appState else {
                    return
                }
                appState.timerManager.completeIfNeeded(now: now)
                self?.updateStatus(appState: appState, now: now)
            }
            .store(in: &cancellables)
    }

    private func updateStatus(appState: AppState, now: Date) {
        guard let button else {
            return
        }

        let timerRemaining = appState.timerManager.phase.remainingSeconds(at: now)
        let keepDisplayOnRemaining: Int?
        let keepDisplayOnIsInfinite: Bool

        switch appState.keepDisplayOnManager.activeOption {
        case .off:
            keepDisplayOnRemaining = nil
            keepDisplayOnIsInfinite = false
        case .infinite:
            keepDisplayOnRemaining = nil
            keepDisplayOnIsInfinite = true
        case .minutes, .hours:
            keepDisplayOnRemaining = appState.keepDisplayOnManager.activeUntil.map {
                max(0, Int(ceil($0.timeIntervalSince(now))))
            }
            keepDisplayOnIsInfinite = false
        }

        let text = StatusItemPresentation.text(
            timerRemainingSeconds: timerRemaining,
            timerIsPaused: appState.timerManager.phase.isPaused,
            keepDisplayOnRemainingSeconds: keepDisplayOnRemaining,
            keepDisplayOnIsInfinite: keepDisplayOnIsInfinite
        )
        if let text {
            button.title = text
            button.imagePosition = button.image == nil ? .noImage : .imageLeading
        } else {
            button.title = button.image == nil ? "Maclet" : ""
            button.imagePosition = button.image == nil ? .noImage : .imageOnly
        }
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        button.toolTip = text.map { "Maclet — \($0)" } ?? "Maclet"
    }

    @objc private func activate(_ sender: NSStatusBarButton) {
        onActivate?()
    }
}

@MainActor
private final class ManagementWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?

    var isPresented: Bool {
        guard let window else {
            return false
        }
        return window.isVisible || window.isMiniaturized
    }

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func show(tab: MainTab) {
        appState.selectedTab = tab
        enterManagementMode()
        let window = makeWindowIfNeeded()
        focus(window)
    }

    func focusIfPresented() -> Bool {
        guard isPresented, let window else {
            return false
        }

        enterManagementMode()
        focus(window)
        return true
    }

    func closeIfWindow(_ candidate: NSWindow) -> Bool {
        guard let window, window === candidate else {
            return false
        }

        window.performClose(nil)
        return true
    }

    func closeIfPresented() -> Bool {
        guard isPresented, let window else {
            return false
        }

        window.performClose(nil)
        return true
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let controller = NSHostingController(
            rootView: ManagementWindowView()
                .environmentObject(appState)
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "Maclet"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior = ManagementWindowPresentationPolicy.collectionBehavior
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 720, height: 560))
        window.center()
        self.window = window
        return window
    }

    private func enterManagementMode() {
        guard NSApp.activationPolicy() != ManagementWindowPresentationPolicy.presentedActivationPolicy else {
            return
        }

        NSApp.setActivationPolicy(ManagementWindowPresentationPolicy.presentedActivationPolicy)
    }

    private func focus(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }

        DispatchQueue.main.async { [weak self, weak closingWindow] in
            guard let self,
                  let closingWindow,
                  self.window === closingWindow,
                  !closingWindow.isVisible else {
                return
            }

            NSApp.setActivationPolicy(ManagementWindowPresentationPolicy.dismissedActivationPolicy)
        }
    }
}

@MainActor
private final class CommandCenterPanelController {
    var statusButtonProvider: (() -> NSStatusBarButton?)?
    var openManagement: ((MainTab) -> Void)?
    var cleanKeyboard: (() -> Void)?
    var quitApplication: (() -> Void)?

    private let appState: AppState
    private let presentationState = CommandCenterPresentationState()
    private var panel: MacletPanel?
    private var presentationTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var presentationGeneration = 0
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    var isActive: Bool {
        presentationState.isPresented || presentationTask != nil
    }

    init(appState: AppState) {
        self.appState = appState
        configureEventMonitors()
    }

    deinit {
        presentationTask?.cancel()
        dismissalTask?.cancel()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }

    func show(
        relativeTo button: NSStatusBarButton,
        shouldPresent: @escaping () -> Bool
    ) {
        dismissalTask?.cancel()
        dismissalTask = nil

        guard !isActive else {
            return
        }

        presentationGeneration += 1
        let generation = presentationGeneration

        presentationTask = Task { [weak self, weak button] in
            guard let self else {
                return
            }

            await appState.bootstrapIfNeeded()
            guard isCurrentPresentation(generation) else {
                return
            }

            appState.refreshClipboard()
            await appState.refreshKeepAwake()
            guard isCurrentPresentation(generation) else {
                return
            }

            presentationTask = nil
            guard shouldPresent(), let button else {
                return
            }

            present(relativeTo: button)
        }
    }

    func hide() {
        presentationGeneration += 1
        presentationTask?.cancel()
        presentationTask = nil
        dismissalTask?.cancel()
        dismissalTask = nil
        presentationState.dismiss()

        guard let panel, panel.isVisible else {
            return
        }

        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? MacletMotion.commandCenterReducedMotionDismissalDelay
            : MacletMotion.commandCenterDismissalDelay

        dismissalTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  !presentationState.isPresented else {
                return
            }
            panel?.orderOut(nil)
            dismissalTask = nil
        }
    }

    func dismissIfActive() -> Bool {
        guard isActive else {
            return false
        }

        hide()
        return true
    }

    func closeIfWindow(_ window: NSWindow) -> Bool {
        guard let panel, panel === window, panel.isVisible else {
            return false
        }

        hide()
        return true
    }

    private func isCurrentPresentation(_ generation: Int) -> Bool {
        !Task.isCancelled && presentationGeneration == generation
    }

    private func present(relativeTo button: NSStatusBarButton) {
        dismissalTask?.cancel()
        dismissalTask = nil
        let size = CommandCenterPanelMetrics.size(for: appState)
        let panel = makePanelIfNeeded()
        panel.setFrame(panelFrame(relativeTo: button, size: size), display: true)
        presentationState.present()
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanelIfNeeded() -> MacletPanel {
        if let panel {
            return panel
        }

        let hostingView = NSHostingView(
            rootView: CommandCenterView(
                presentationState: presentationState,
                openManagement: { [weak self] tab in
                    self?.openManagement?(tab)
                },
                cleanKeyboard: { [weak self] in
                    self?.cleanKeyboard?()
                },
                quitApplication: { [weak self] in
                    self?.quitApplication?()
                }
            )
            .environmentObject(appState)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        let panel = MacletPanel(
            contentRect: NSRect(origin: .zero, size: CommandCenterPanelMetrics.size(for: appState)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func panelFrame(relativeTo button: NSStatusBarButton, size: NSSize) -> NSRect {
        let statusFrame: NSRect
        if let window = button.window {
            statusFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            statusFrame = NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height)
        }

        let screenFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(
            max(statusFrame.midX - size.width / 2, screenFrame.minX + 8),
            screenFrame.maxX - size.width - 8
        )
        let y = max(statusFrame.minY - size.height - 8, screenFrame.minY + 8)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func configureEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissIfNeeded(for: event)
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.dismissIfNeeded(for: event)
            }
        }
    }

    private func dismissIfNeeded(for event: NSEvent) {
        let eventIsInsidePanel = panel?.isVisible == true && event.window === panel
        let eventIsStatusItem = event.window === statusButtonProvider?()?.window
        guard CommandCenterDismissalDecision.shouldDismiss(
            isActive: isActive,
            isAppModalPresented: NSApp.modalWindow != nil,
            eventIsInsidePanel: eventIsInsidePanel,
            eventIsStatusItem: eventIsStatusItem
        ) else {
            return
        }

        hide()
    }
}

private final class MacletPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
