import SwiftUI
import MacletCore

struct GridSpan: Equatable {
    let row: Int
    let col: Int
}

struct CommandCenterGridPlacement: Equatable, Identifiable {
    let feature: AppFeature
    let row: Int
    let column: Int
    let span: GridSpan

    var id: AppFeature { feature }
}

private struct CommandCenterGridCell: Hashable {
    let row: Int
    let column: Int
}

enum CommandCenterLayout {
    static let unit: CGFloat = 64
    static let gap: CGFloat = 12
    static let padding: CGFloat = 8
    static let topBarHeight: CGFloat = 32
    static let keepDisplayOnControlHeight: CGFloat = 24
    static let maxQuickCommands = 8
    static let columnCount = 4
    static let timer = GridSpan(row: 2, col: 4)
    static let keepDisplayOn = GridSpan(row: 2, col: 2)
    static let keepAwake = GridSpan(row: 1, col: 2)
    static let cleanKeyboard = GridSpan(row: 1, col: 2)
    static let clipboard = GridSpan(row: 5, col: 4)
    static let quickCommandColumns = 4

    static let content = GridSpan(row: 0, col: 4)

    static let blurScaleX: CGFloat = 1.5
    static let blurScaleY: CGFloat = 1.236

    static func span(_ count: Int) -> CGFloat {
        CGFloat(count) * unit + CGFloat(max(0, count - 1)) * gap
    }

    static func size(_ gridSpan: GridSpan) -> CGSize {
        CGSize(width: span(gridSpan.col), height: span(gridSpan.row))
    }

    static func quickCommandRows(count: Int) -> Int {
        guard count > 0 else {
            return 0
        }

        return min(maxQuickCommands, count + quickCommandColumns - 1) / quickCommandColumns
    }

    static func quickCommandHeight(count: Int) -> CGFloat {
        let rows = quickCommandRows(count: count)
        guard rows > 0 else {
            return 0
        }

        return CGFloat(rows) * unit + CGFloat(rows - 1) * gap
    }

    static func contentSize(
        featureOrder: [AppFeature],
        enabledFeatures: Set<AppFeature>,
        quickCommandCount: Int
    ) -> CGSize {
        let placements = featurePlacements(
            featureOrder: featureOrder,
            enabledFeatures: enabledFeatures,
            quickCommandCount: quickCommandCount
        )
        let gridRows = placements.map { $0.row + $0.span.row }.max() ?? 0
        let gridHeight = gridRows > 0 ? gap + span(gridRows) : 0
        let contentHeight = topBarHeight + gridHeight

        return CGSize(
            width: padding * 2 + span(content.col),
            height: padding * 2 + contentHeight
        )
    }

    static func panelSize(
        featureOrder: [AppFeature],
        enabledFeatures: Set<AppFeature>,
        quickCommandCount: Int
    ) -> CGSize {
        let content = contentSize(
            featureOrder: featureOrder,
            enabledFeatures: enabledFeatures,
            quickCommandCount: quickCommandCount
        )

        return CGSize(
            width: content.width * blurScaleX,
            height: content.height * blurScaleY
        )
    }

    static func featurePlacements(
        featureOrder: [AppFeature],
        enabledFeatures: Set<AppFeature>,
        quickCommandCount: Int
    ) -> [CommandCenterGridPlacement] {
        var occupied: Set<CommandCenterGridCell> = []
        var placements: [CommandCenterGridPlacement] = []
        var cursor = (row: 0, column: 0)

        for feature in featureOrder where enabledFeatures.contains(feature) {
            let featureSpan = moduleSpan(for: feature, quickCommandCount: quickCommandCount)
            guard featureSpan.row > 0, featureSpan.col > 0, featureSpan.col <= columnCount else {
                continue
            }
            let origin = firstAvailableOrigin(
                for: featureSpan,
                occupied: occupied,
                startingAt: cursor
            )
            for row in origin.row..<(origin.row + featureSpan.row) {
                for column in origin.column..<(origin.column + featureSpan.col) {
                    occupied.insert(CommandCenterGridCell(row: row, column: column))
                }
            }
            placements.append(CommandCenterGridPlacement(
                feature: feature,
                row: origin.row,
                column: origin.column,
                span: featureSpan
            ))
            let nextColumn = origin.column + featureSpan.col
            cursor = nextColumn < columnCount
                ? (origin.row, nextColumn)
                : (origin.row + 1, 0)
        }
        return placements
    }

    static func offset(_ gridIndex: Int) -> CGFloat {
        CGFloat(gridIndex) * (unit + gap)
    }

    private static func moduleSpan(for feature: AppFeature, quickCommandCount: Int) -> GridSpan {
        switch feature {
        case .timer:
            return timer
        case .keepDisplayOn:
            return keepDisplayOn
        case .keepAwake:
            return keepAwake
        case .cleanKeyboard:
            return cleanKeyboard
        case .clipboardHistory:
            return clipboard
        case .quickCommands:
            return GridSpan(row: quickCommandRows(count: quickCommandCount), col: columnCount)
        }
    }

    private static func firstAvailableOrigin(
        for span: GridSpan,
        occupied: Set<CommandCenterGridCell>,
        startingAt start: (row: Int, column: Int)
    ) -> (row: Int, column: Int) {
        var row = start.row
        var firstColumn = start.column
        while true {
            let lastColumn = columnCount - span.col
            if firstColumn <= lastColumn {
                for column in firstColumn...lastColumn {
                    let fits = (row..<(row + span.row)).allSatisfy { candidateRow in
                        (column..<(column + span.col)).allSatisfy { candidateColumn in
                            !occupied.contains(CommandCenterGridCell(row: candidateRow, column: candidateColumn))
                        }
                    }
                    if fits {
                        return (row, column)
                    }
                }
            }
            row += 1
            firstColumn = 0
        }
    }

    static let defaultPanelSize = panelSize(
        featureOrder: AppFeature.allCases,
        enabledFeatures: Set(AppFeature.allCases),
        quickCommandCount: 0
    )
}

private enum CommandCenterVisualPhase {
    case hidden
    case appearing
    case visible
    case disappearing
}

struct CommandCenterView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var presentationState: CommandCenterPresentationState
    @State private var isBackgroundVisible = false
    @State private var isContentVisible = false
    @State private var visualPhase = CommandCenterVisualPhase.hidden
    @State private var entranceTask: Task<Void, Never>?

    let openManagement: (MainTab) -> Void
    let cleanKeyboard: () -> Void
    let quitApplication: () -> Void

    init(
        presentationState: CommandCenterPresentationState,
        openManagement: @escaping (MainTab) -> Void,
        cleanKeyboard: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        self.presentationState = presentationState
        self.openManagement = openManagement
        self.cleanKeyboard = cleanKeyboard
        self.quitApplication = quitApplication
    }

    private var panelSize: CGSize {
        CommandCenterLayout.panelSize(
            featureOrder: appState.settings.featureOrder,
            enabledFeatures: appState.settings.enabledFeatures,
            quickCommandCount: appState.quickCommands.count
        )
    }

    private var contentSize: CGSize {
        CommandCenterLayout.contentSize(
            featureOrder: appState.settings.featureOrder,
            enabledFeatures: appState.settings.enabledFeatures,
            quickCommandCount: appState.quickCommands.count
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            RootGradientBlurBackground(size: panelSize)
                .opacity(isBackgroundVisible ? 1 : 0)
                .scaleEffect(
                    isBackgroundVisible || visualPhase == .disappearing ? 1 : 0.94,
                    anchor: .top
                )

            CommandCenterContent(
                timerManager: appState.timerManager,
                keepDisplayOnManager: appState.keepDisplayOnManager,
                keepAwakeManager: appState.keepAwakeManager,
                timerPresets: appState.settings.timerPresetSeconds,
                featurePlacements: CommandCenterLayout.featurePlacements(
                    featureOrder: appState.settings.featureOrder,
                    enabledFeatures: appState.settings.enabledFeatures,
                    quickCommandCount: appState.quickCommands.count
                ),
                quickCommands: appState.quickCommands,
                openSettings: {
                    openManagement(.settings)
                },
                startTimer: { seconds in
                    appState.startTimer(seconds: seconds)
                },
                pauseTimer: {
                    appState.pauseTimer()
                },
                resumeTimer: {
                    appState.resumeTimer()
                },
                stopTimer: {
                    appState.stopTimer()
                },
                setKeepDisplayOn: { option in
                    appState.setKeepDisplayOn(option)
                },
                toggleKeepAwake: {
                    appState.toggleKeepAwake()
                },
                cleanKeyboard: cleanKeyboard,
                runCommand: { command in
                    appState.run(command)
                },
                clipboardPayload: appState.clipboardPayload,
                clipboardItems: appState.clipboardHistory,
                copiedClipboardItemID: appState.copiedClipboardItemID,
                copyClipboardItem: { item in
                    appState.copyClipboardItem(item)
                },
                quitApplication: quitApplication
            )
            .padding(CommandCenterLayout.padding)
            .frame(width: contentSize.width, height: contentSize.height)
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(
                reduceMotion || visualPhase != .appearing
                    ? 1
                    : MacletMotion.commandCenterInitialScale,
                anchor: .top
            )
            .blur(
                radius: reduceMotion || visualPhase != .appearing
                    ? 0
                    : MacletMotion.commandCenterInitialBlur
            )
        }
        .frame(size: panelSize)
        .preferredColorScheme(.dark)
        .macletModals(presentsEditor: false)
        .onAppear {
            updatePresentation(isPresented: presentationState.isPresented)
        }
        .onChange(of: presentationState.isPresented) { _, isPresented in
            updatePresentation(isPresented: isPresented)
        }
        .onDisappear {
            entranceTask?.cancel()
            entranceTask = nil
        }
    }

    private func updatePresentation(isPresented: Bool) {
        entranceTask?.cancel()
        entranceTask = nil

        guard isPresented else {
            guard visualPhase != .hidden else {
                isBackgroundVisible = false
                isContentVisible = false
                return
            }

            visualPhase = .disappearing
            withAnimation(MacletMotion.commandCenterDismissal(reduceMotion: reduceMotion)) {
                isBackgroundVisible = false
                isContentVisible = false
            }

            let delay = reduceMotion
                ? MacletMotion.commandCenterReducedMotionDismissalDelay
                : MacletMotion.commandCenterDismissalDelay
            entranceTask = Task { @MainActor in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, !presentationState.isPresented else {
                    return
                }
                visualPhase = .hidden
                entranceTask = nil
            }
            return
        }

        guard presentationState.animatesEntrance else {
            visualPhase = .visible
            isBackgroundVisible = true
            isContentVisible = true
            return
        }

        if visualPhase == .disappearing {
            withAnimation(MacletMotion.commandCenterContent(reduceMotion: reduceMotion)) {
                visualPhase = .visible
                isBackgroundVisible = true
                isContentVisible = true
            }
            return
        }

        visualPhase = .appearing

        withAnimation(MacletMotion.commandCenterBackground(reduceMotion: reduceMotion)) {
            isBackgroundVisible = true
        }

        entranceTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: MacletMotion.commandCenterContentDelay)
            }
            guard !Task.isCancelled, presentationState.isPresented else {
                return
            }
            withAnimation(MacletMotion.commandCenterContent(reduceMotion: reduceMotion)) {
                visualPhase = .visible
                isContentVisible = true
            }
            entranceTask = nil
        }
    }
}

private struct CommandCenterContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var timerManager: CountdownTimerManager
    @ObservedObject var keepDisplayOnManager: KeepDisplayOnManager
    @ObservedObject var keepAwakeManager: KeepAwakeManager
    let timerPresets: [Int]
    let featurePlacements: [CommandCenterGridPlacement]
    let quickCommands: [SavedCommand]
    let openSettings: () -> Void
    let startTimer: (Int) -> Void
    let pauseTimer: () -> Void
    let resumeTimer: () -> Void
    let stopTimer: () -> Void
    let setKeepDisplayOn: (KeepDisplayOnDuration) -> Void
    let toggleKeepAwake: () -> Void
    let cleanKeyboard: () -> Void
    let runCommand: (SavedCommand) -> Void
    let clipboardPayload: ClipboardPayload
    let clipboardItems: [ClipboardHistoryItem]
    let copiedClipboardItemID: ClipboardHistoryItem.ID?
    let copyClipboardItem: (ClipboardHistoryItem) -> Void
    let quitApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CommandCenterLayout.gap) {
            TopBar(openSettings: openSettings, quitApplication: quitApplication)
                .frame(width: CommandCenterLayout.span(CommandCenterLayout.content.col), height: CommandCenterLayout.topBarHeight)

            if !featurePlacements.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(featurePlacements) { placement in
                        featureModule(placement.feature)
                            .offset(
                                x: CommandCenterLayout.offset(placement.column),
                                y: CommandCenterLayout.offset(placement.row)
                            )
                    }
                }
                .frame(
                    width: CommandCenterLayout.span(CommandCenterLayout.columnCount),
                    height: CommandCenterLayout.span(gridRowCount),
                    alignment: .topLeading
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(MacletMotion.stateChange(reduceMotion: reduceMotion), value: timerManager.phase)
        .animation(MacletMotion.stateChange(reduceMotion: reduceMotion), value: keepDisplayOnManager.activeOption.id)
        .animation(MacletMotion.stateChange(reduceMotion: reduceMotion), value: keepAwakeManager.isEnabled)
        .animation(MacletMotion.feedback(reduceMotion: reduceMotion), value: copiedClipboardItemID)
        .animation(MacletMotion.layout(reduceMotion: reduceMotion), value: featurePlacements)
        .animation(MacletMotion.layout(reduceMotion: reduceMotion), value: quickCommands.map(\.id))
    }

    private var gridRowCount: Int {
        featurePlacements.map { $0.row + $0.span.row }.max() ?? 0
    }

    @ViewBuilder
    private func featureModule(_ feature: AppFeature) -> some View {
        switch feature {
        case .timer:
            TimerModule(
                manager: timerManager,
                presets: timerPresets,
                start: startTimer,
                pause: pauseTimer,
                resume: resumeTimer,
                stop: stopTimer
            )
            .frame(size: CommandCenterLayout.size(CommandCenterLayout.timer))
        case .keepDisplayOn:
            KeepDisplayOnModule(
                option: keepDisplayOnManager.activeOption,
                activeUntil: keepDisplayOnManager.activeUntil,
                setKeepDisplayOn: setKeepDisplayOn
            )
            .frame(size: CommandCenterLayout.size(CommandCenterLayout.keepDisplayOn))
        case .keepAwake:
            KeepAwakeButton(
                isEnabled: keepAwakeManager.isEnabled,
                isChanging: keepAwakeManager.isChanging,
                action: toggleKeepAwake
            )
            .frame(size: CommandCenterLayout.size(CommandCenterLayout.keepAwake))
        case .cleanKeyboard:
            CleanKeyboardButton(action: cleanKeyboard)
                .frame(size: CommandCenterLayout.size(CommandCenterLayout.cleanKeyboard))
        case .clipboardHistory:
            ClipboardModule(
                payload: clipboardPayload,
                items: clipboardItems,
                copiedItemID: copiedClipboardItemID,
                action: copyClipboardItem
            )
            .frame(size: CommandCenterLayout.size(CommandCenterLayout.clipboard))
        case .quickCommands:
            if !quickCommands.isEmpty {
                QuickCommandsModule(commands: Array(quickCommands.prefix(CommandCenterLayout.maxQuickCommands)), runCommand: runCommand)
                    .frame(
                        width: CommandCenterLayout.span(CommandCenterLayout.content.col),
                        height: CommandCenterLayout.quickCommandHeight(count: quickCommands.count)
                    )
            }
        }
    }
}

private struct TopBar: View {
    let openSettings: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        HStack {
            SettingsButton(action: openSettings)

            Spacer(minLength: 0)

            QuitButton(action: quitApplication)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommandCenterPalette.text)
                .frame(width: CommandCenterLayout.topBarHeight, height: CommandCenterLayout.topBarHeight)
                .controlCenterSurface(cornerRadius: CommandCenterLayout.topBarHeight / 2)
        }
        .buttonStyle(.plain)
        .help("Open Settings")
    }
}

private struct QuitButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommandCenterPalette.text)
                .frame(width: CommandCenterLayout.topBarHeight, height: CommandCenterLayout.topBarHeight)
                .controlCenterSurface(cornerRadius: CommandCenterLayout.topBarHeight / 2)
        }
        .buttonStyle(.plain)
        .help("Quit Maclet")
    }
}

private struct RootGradientBlurBackground: View {
    let size: CGSize

    var body: some View {
        Color.black.opacity(0.118)
            .frame(size: size)
            .mask {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.0), location: 0.00),
                                .init(color: .white, location: 0.30),
                                .init(color: .white, location: 0.70),
                                .init(color: .white.opacity(0.0), location: 1.00)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.00),
                                .init(color: .white, location: 0.55),
                                .init(color: .white.opacity(0.0), location: 1.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .blur(radius: 16)
            }
            .allowsHitTesting(false)
    }
}
