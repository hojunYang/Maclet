import AppKit
import Combine
import Foundation
import MacletCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var commands: [SavedCommand] = []
    @Published private(set) var runHistory: [CommandRunRecord] = []
    @Published private(set) var runningCommandIDs: Set<UUID> = []
    @Published var selectedTab: MainTab = .commands
    @Published var selectedLogID: UUID?
    @Published var editorDraft: CommandDraft?
    @Published var pendingConfirmation: SavedCommand?
    @Published var alert: AppAlert?
    @Published private(set) var loginItemState = LoginItemState.disabled
    @Published private(set) var settings = AppSettings.defaults
    @Published private(set) var clipboardPayload: ClipboardPayload = .empty
    @Published private(set) var clipboardHistory: [ClipboardHistoryItem] = []
    @Published private(set) var clipboardCopyFeedbackVisible = false
    @Published private(set) var copiedClipboardItemID: ClipboardHistoryItem.ID?
    @Published private(set) var globalShortcutRegistrationError: String?
    @Published private(set) var isRecordingGlobalShortcut = false

    let repository: JSONCommandRepository
    let keepDisplayOnManager: KeepDisplayOnManager
    let timerManager: CountdownTimerManager
    let keepAwakeManager: KeepAwakeManager
    private let runner: CommandRunning
    private let clipboardManager: ClipboardManaging
    private let loginItemManager: LoginItemManaging
    private var didBootstrap = false
    private var runningCommandTasks: [UUID: Task<Void, Never>] = [:]
    private var clipboardFeedbackTask: Task<Void, Never>?
    private var clipboardMonitorCancellable: AnyCancellable?
    private var lastClipboardChangeCount: Int?

    init(
        repository: JSONCommandRepository = JSONCommandRepository(),
        keepDisplayOnManager: KeepDisplayOnManager? = nil,
        timerManager: CountdownTimerManager? = nil,
        keepAwakeManager: KeepAwakeManager? = nil,
        runner: CommandRunning? = nil,
        adminAuthorizationCoordinator: AdminAuthorizationCoordinator? = nil,
        clipboardManager: ClipboardManaging = PasteboardClipboardManager(),
        loginItemManager: LoginItemManaging = ServiceManagementLoginItemManager()
    ) {
        let adminAuthorizationCoordinator = adminAuthorizationCoordinator ?? AdminAuthorizationCoordinator.live()
        self.repository = repository
        self.keepDisplayOnManager = keepDisplayOnManager ?? KeepDisplayOnManager()
        self.timerManager = timerManager ?? CountdownTimerManager()
        self.keepAwakeManager = keepAwakeManager ?? KeepAwakeManager(
            adminAuthorizationCoordinator: adminAuthorizationCoordinator
        )
        self.runner = runner ?? ShellCommandRunner(adminExecutor: adminAuthorizationCoordinator)
        self.clipboardManager = clipboardManager
        self.loginItemManager = loginItemManager
        self.timerManager.onCompletion = { [weak self] durationSeconds in
            self?.alert = AppAlert(
                title: "Timer Complete",
                message: "The \(CountdownText.clock(seconds: durationSeconds)) timer has finished."
            )
        }
        refreshLoginItemState()
    }

    // MARK: - App lifecycle

    func bootstrapIfNeeded() async {
        guard !didBootstrap else {
            return
        }

        didBootstrap = true
        do {
            commands = try repository.loadCommands()
            settings = try repository.loadSettings()
            runHistory = try repository.loadRunHistory().sorted { $0.startedAt > $1.startedAt }
        } catch {
            alert = AppAlert(title: "Load Failed", message: error.localizedDescription)
        }

        if isFeatureEnabled(.keepAwake) {
            await refreshKeepAwake()
        }

        if isFeatureEnabled(.clipboardHistory) {
            startClipboardMonitoring()
        }
    }

    // MARK: - Derived UI state

    var favoriteCommands: [SavedCommand] {
        commands.filter(\.isFavorite)
    }

    var quickCommands: [SavedCommand] {
        guard isFeatureEnabled(.quickCommands) else {
            return []
        }

        return favoriteCommands
    }

    var recentRuns: [CommandRunRecord] {
        Array(runHistory.prefix(8))
    }

    var selectedLog: CommandRunRecord? {
        guard let selectedLogID else {
            return runHistory.first
        }
        return runHistory.first { $0.id == selectedLogID }
    }

    var runningCommandCount: Int {
        runningCommandIDs.count
    }

    var hasRunningCommands: Bool {
        !runningCommandIDs.isEmpty
    }

    var hasActiveTimer: Bool {
        timerManager.phase.isActive
    }

    var loginItemEnabled: Bool {
        loginItemState.isEnabled
    }

    func isFeatureEnabled(_ feature: AppFeature) -> Bool {
        settings.isEnabled(feature)
    }

    // MARK: - Commands

    func run(_ command: SavedCommand) {
        if command.requiresConfirmation {
            pendingConfirmation = command
            return
        }

        runConfirmed(command)
    }

    func runPendingConfirmation() {
        guard let command = pendingConfirmation else {
            return
        }
        pendingConfirmation = nil
        runConfirmed(command)
    }

    func runConfirmed(_ command: SavedCommand) {
        guard !runningCommandIDs.contains(command.id) else {
            return
        }

        runningCommandIDs.insert(command.id)

        let task = Task {
            let record = await runner.run(command)
            await MainActor.run {
                self.runningCommandIDs.remove(command.id)
                self.runningCommandTasks[command.id] = nil
                self.recordRun(record)
            }
        }
        runningCommandTasks[command.id] = task
    }

    func beginAddCommand() {
        editorDraft = CommandDraft()
    }

    func beginEdit(_ command: SavedCommand) {
        editorDraft = CommandDraft(command: command)
    }

    func saveDraft(_ draft: CommandDraft) {
        do {
            let command = try draft.makeCommand()
            try CommandValidator.validate(command)

            if let index = commands.firstIndex(where: { $0.id == command.id }) {
                commands[index] = command
            } else {
                commands.append(command)
            }

            try persistCommands()
            editorDraft = nil
        } catch {
            alert = AppAlert(title: "Command Not Saved", message: error.localizedDescription)
        }
    }

    func delete(_ command: SavedCommand) {
        commands.removeAll { $0.id == command.id }
        do {
            try persistCommands()
        } catch {
            alert = AppAlert(title: "Delete Failed", message: error.localizedDescription)
        }
    }

    func duplicate(_ command: SavedCommand) {
        var copy = command
        copy.id = UUID()
        copy.title = "\(command.title) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastRun = nil
        commands.append(copy)

        do {
            try persistCommands()
        } catch {
            alert = AppAlert(title: "Duplicate Failed", message: error.localizedDescription)
        }
    }

    func resetToDefaultCommands() {
        commands = CommandPresets.defaults
        do {
            try persistCommands()
        } catch {
            alert = AppAlert(title: "Reset Failed", message: error.localizedDescription)
        }
    }

    func setCommandFavorite(_ command: SavedCommand, isFavorite: Bool) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }),
              commands[index].isFavorite != isFavorite else {
            return
        }

        commands[index].isFavorite = isFavorite
        commands[index].updatedAt = Date()

        do {
            try persistCommands()
        } catch {
            alert = AppAlert(title: "Command Not Saved", message: error.localizedDescription)
        }
    }

    // MARK: - Persisted settings

    func setFeature(_ feature: AppFeature, enabled: Bool) {
        guard isFeatureEnabled(feature) != enabled else {
            return
        }

        if enabled {
            enableFeature(feature)
            return
        }

        disableFeature(feature)
    }

    func setFeatureOrder(_ features: [AppFeature]) {
        let normalizedOrder = AppSettings.normalizedFeatureOrder(features)
        guard settings.featureOrder != normalizedOrder else {
            return
        }

        let previousOrder = settings.featureOrder
        settings.setFeatureOrder(normalizedOrder)

        do {
            try repository.saveSettings(settings)
        } catch {
            settings.setFeatureOrder(previousOrder)
            alert = AppAlert(title: "Settings Not Saved", message: error.localizedDescription)
        }
    }

    func setClipboardHistoryLimit(_ limit: Int) {
        let normalizedLimit = AppSettings.normalizedClipboardHistoryLimit(limit)
        guard settings.clipboardHistoryLimit != normalizedLimit else {
            return
        }

        let previousLimit = settings.clipboardHistoryLimit
        settings.setClipboardHistoryLimit(normalizedLimit)

        do {
            try repository.saveSettings(settings)
            trimClipboardHistory()
        } catch {
            settings.setClipboardHistoryLimit(previousLimit)
            alert = AppAlert(title: "Settings Not Saved", message: error.localizedDescription)
        }
    }

    func setCommandCenterShortcut(_ shortcut: GlobalShortcut?) {
        guard settings.commandCenterShortcut != shortcut else {
            return
        }

        let previousShortcut = settings.commandCenterShortcut
        settings.commandCenterShortcut = shortcut

        do {
            try repository.saveSettings(settings)
        } catch {
            settings.commandCenterShortcut = previousShortcut
            alert = AppAlert(title: "Settings Not Saved", message: error.localizedDescription)
        }
    }

    func setTimerPresets(_ values: [Int]) {
        let normalizedValues = AppSettings.normalizedTimerPresets(values)
        guard settings.timerPresetSeconds != normalizedValues else {
            return
        }

        let previousValues = settings.timerPresetSeconds
        settings.setTimerPresets(normalizedValues)

        do {
            try repository.saveSettings(settings)
        } catch {
            settings.setTimerPresets(previousValues)
            alert = AppAlert(title: "Settings Not Saved", message: error.localizedDescription)
        }
    }

    func setGlobalShortcutRegistrationError(_ message: String?) {
        globalShortcutRegistrationError = message
    }

    func setGlobalShortcutRecording(_ isRecording: Bool) {
        isRecordingGlobalShortcut = isRecording
    }

    // MARK: - Logs and system links

    func clearRunHistory() {
        runHistory = []
        do {
            try repository.saveRunHistory(runHistory)
        } catch {
            alert = AppAlert(title: "Clear Failed", message: error.localizedDescription)
        }
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(repository.rootURL)
    }

    func openPrivateRelaySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openLoginItemsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.users?LoginItems"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Keep Display On

    func setKeepDisplayOn(_ option: KeepDisplayOnDuration) {
        guard isFeatureEnabled(.keepDisplayOn) else {
            return
        }

        do {
            try keepDisplayOnManager.activate(option: option)
        } catch {
            alert = AppAlert(title: "Keep Display On Failed", message: error.localizedDescription)
        }
    }

    func stopKeepDisplayOn() {
        keepDisplayOnManager.stop()
    }

    // MARK: - Timer

    func startTimer(seconds: Int) {
        guard isFeatureEnabled(.timer) else {
            return
        }
        timerManager.start(seconds: seconds)
    }

    func pauseTimer() {
        timerManager.pause()
    }

    func resumeTimer() {
        timerManager.resume()
    }

    func stopTimer() {
        timerManager.stop()
    }

    func prepareForTermination() {
        stopActiveServices()
    }

    func cancelRunningCommands() {
        for task in runningCommandTasks.values {
            task.cancel()
        }
        runner.cancelAll()
    }

    private func stopActiveServices() {
        cancelRunningCommands()
        stopKeepDisplayOn()
        stopTimer()
    }

    // MARK: - Keep Awake

    func refreshKeepAwake() async {
        guard isFeatureEnabled(.keepAwake) else {
            return
        }

        do {
            try await keepAwakeManager.refresh()
        } catch {
            alert = AppAlert(title: "Keep Awake Refresh Failed", message: error.localizedDescription)
        }
    }

    func toggleKeepAwake() {
        guard isFeatureEnabled(.keepAwake) else {
            return
        }

        Task {
            do {
                try await keepAwakeManager.toggle()
            } catch {
                alert = AppAlert(title: "Keep Awake Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Clipboard

    func refreshClipboard() {
        guard isFeatureEnabled(.clipboardHistory) else {
            return
        }

        let snapshot = clipboardManager.readSnapshot()
        guard snapshot.changeCount != lastClipboardChangeCount else {
            return
        }

        lastClipboardChangeCount = snapshot.changeCount
        clipboardPayload = snapshot.payload
        rememberClipboardPayload(snapshot.payload, changeCount: snapshot.changeCount)
    }

    func copyClipboardItem(_ item: ClipboardHistoryItem) {
        guard isFeatureEnabled(.clipboardHistory) else {
            return
        }

        guard item.payload.isCopyable else {
            return
        }

        do {
            try clipboardManager.write(item.payload)
            let snapshot = clipboardManager.readSnapshot()
            lastClipboardChangeCount = snapshot.changeCount
            clipboardPayload = snapshot.payload
            rememberClipboardPayload(snapshot.payload, changeCount: snapshot.changeCount)
            showClipboardCopyFeedback(itemID: item.id)
        } catch {
            alert = AppAlert(title: "Clipboard Copy Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Start at Login

    func toggleLoginItem(_ enabled: Bool) {
        do {
            try loginItemManager.setEnabled(enabled)
            refreshLoginItemState()

            if enabled, loginItemState == .requiresApproval {
                alert = AppAlert(
                    title: "Start at Login Needs Approval",
                    message: "Open System Settings > General > Login Items and allow Maclet."
                )
            }
        } catch {
            refreshLoginItemState()
            alert = AppAlert(title: "Start at Login Failed", message: error.localizedDescription)
        }
    }

    func refreshLoginItemState() {
        loginItemState = loginItemManager.state
    }

    // MARK: - Private persistence and feature lifecycle

    private func recordRun(_ record: CommandRunRecord) {
        runHistory.insert(record, at: 0)
        runHistory = Array(runHistory.prefix(200))
        selectedLogID = record.id

        if let index = commands.firstIndex(where: { $0.id == record.commandID }) {
            commands[index].lastRun = record.summary
            commands[index].updatedAt = Date()
        }

        do {
            try persistCommands()
            try repository.saveRunHistory(runHistory)
            showOutputAlertIfNeeded(for: record)
        } catch {
            alert = AppAlert(title: "Log Save Failed", message: error.localizedDescription)
        }
    }

    private func showOutputAlertIfNeeded(for record: CommandRunRecord) {
        let output = record.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return
        }

        alert = AppAlert(
            title: "\(record.commandTitle) Output",
            message: output,
            messageStyle: .monospaced
        )
    }

    private func persistCommands() throws {
        try repository.saveCommands(commands.sorted { $0.createdAt < $1.createdAt })
        commands = try repository.loadCommands()
    }

    private func enableFeature(_ feature: AppFeature) {
        guard updateFeatureSetting(feature, enabled: true) else {
            return
        }

        switch feature {
        case .timer, .keepDisplayOn, .cleanKeyboard, .quickCommands:
            break
        case .keepAwake:
            Task {
                await refreshKeepAwake()
            }
        case .clipboardHistory:
            startClipboardMonitoring()
        }
    }

    private func disableFeature(_ feature: AppFeature) {
        switch feature {
        case .timer:
            guard updateFeatureSetting(feature, enabled: false) else {
                return
            }
            stopTimer()
        case .keepDisplayOn:
            guard updateFeatureSetting(feature, enabled: false) else {
                return
            }
            stopKeepDisplayOn()
        case .keepAwake:
            Task {
                await disableKeepAwakeFeature()
            }
        case .clipboardHistory:
            guard updateFeatureSetting(feature, enabled: false) else {
                return
            }
            stopClipboardMonitoring()
        case .cleanKeyboard, .quickCommands:
            updateFeatureSetting(feature, enabled: false)
        }
    }

    private func disableKeepAwakeFeature() async {
        do {
            if keepAwakeManager.isEnabled {
                try await keepAwakeManager.setEnabled(false)
            }
            _ = updateFeatureSetting(.keepAwake, enabled: false)
        } catch {
            alert = AppAlert(title: "Keep Awake Failed", message: error.localizedDescription)
        }
    }

    @discardableResult
    private func updateFeatureSetting(_ feature: AppFeature, enabled: Bool) -> Bool {
        settings.setFeature(feature, enabled: enabled)

        do {
            try repository.saveSettings(settings)
            return true
        } catch {
            settings.setFeature(feature, enabled: !enabled)
            alert = AppAlert(title: "Settings Not Saved", message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Private clipboard monitoring

    private func startClipboardMonitoring() {
        guard isFeatureEnabled(.clipboardHistory) else {
            return
        }

        guard clipboardMonitorCancellable == nil else {
            return
        }

        refreshClipboard()
        clipboardMonitorCancellable = Timer
            .publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshClipboard()
            }
    }

    private func stopClipboardMonitoring() {
        clipboardFeedbackTask?.cancel()
        clipboardFeedbackTask = nil
        clipboardMonitorCancellable?.cancel()
        clipboardMonitorCancellable = nil
        lastClipboardChangeCount = nil
        clipboardPayload = .empty
        clipboardHistory = []
        copiedClipboardItemID = nil
        clipboardCopyFeedbackVisible = false
    }

    private func rememberClipboardPayload(_ payload: ClipboardPayload, changeCount: Int) {
        guard let id = payload.historyIdentifier else {
            return
        }

        clipboardHistory.removeAll { $0.id == id }
        clipboardHistory.insert(
            ClipboardHistoryItem(
                id: id,
                payload: payload,
                capturedAt: Date(),
                changeCount: changeCount
            ),
            at: 0
        )
        trimClipboardHistory()
    }

    private func trimClipboardHistory() {
        clipboardHistory = Array(clipboardHistory.prefix(settings.clipboardHistoryLimit))
    }

    private func showClipboardCopyFeedback(itemID: ClipboardHistoryItem.ID) {
        clipboardFeedbackTask?.cancel()
        copiedClipboardItemID = itemID
        clipboardCopyFeedbackVisible = true

        clipboardFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else {
                return
            }
            copiedClipboardItemID = nil
            clipboardCopyFeedbackVisible = false
        }
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case commands = "Commands"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .commands:
            return "terminal"
        case .logs:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}

enum AppAlertMessageStyle {
    case plain
    case monospaced
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var messageStyle: AppAlertMessageStyle = .plain
}
