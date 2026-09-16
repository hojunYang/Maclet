import SwiftUI
import MacletCore

struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(title: "Settings", systemName: "gearshape")

                GlobalShortcutPanel()

                FeatureTogglesPanel()

                QuickButtonsPanel()

                StartupPanel()

                StoragePanel()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct FeatureTogglesPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Features")
                .font(.headline)

            ForEach(Array(appState.settings.featureOrder.enumerated()), id: \.element) { index, feature in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { appState.isFeatureEnabled(feature) },
                        set: { appState.setFeature(feature, enabled: $0) }
                    )) {
                        Label(feature.title, systemImage: feature.symbolName)
                    }

                    Spacer(minLength: 8)

                    IconButton(systemName: "arrow.up", title: "Move Up") {
                        moveFeature(from: index, to: index - 1)
                    }
                    .disabled(index == 0)

                    IconButton(systemName: "arrow.down", title: "Move Down") {
                        moveFeature(from: index, to: index + 1)
                    }
                    .disabled(index == appState.settings.featureOrder.count - 1)
                }

                if feature == .timer {
                    TimerPresetSettings()
                        .disabled(!appState.isFeatureEnabled(.timer))
                }

                if feature == .clipboardHistory {
                    HStack {
                        Spacer()

                        Picker("Clipboard Items", selection: Binding(
                            get: { appState.settings.clipboardHistoryLimit },
                            set: { appState.setClipboardHistoryLimit($0) }
                        )) {
                            ForEach(AppSettings.clipboardHistoryLimitOptions, id: \.self) { limit in
                                Text("\(limit)")
                                    .tag(limit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .disabled(!appState.isFeatureEnabled(.clipboardHistory))
                    }
                    .font(.subheadline)
                }

                if index < appState.settings.featureOrder.count - 1 {
                    Divider()
                }
            }
        }
        .panelStyle()
    }

    private func moveFeature(from source: Int, to destination: Int) {
        guard appState.settings.featureOrder.indices.contains(source),
              appState.settings.featureOrder.indices.contains(destination) else {
            return
        }
        var features = appState.settings.featureOrder
        features.swapAt(source, destination)
        appState.setFeatureOrder(features)
    }
}

private struct StoragePanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage")
                .font(.headline)

            Text(appState.repository.rootURL.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button {
                    appState.openStorageFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }

                Button {
                    appState.resetToDefaultCommands()
                } label: {
                    Label("Reset Presets", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .panelStyle()
    }
}

private extension AppFeature {
    var title: String {
        switch self {
        case .timer:
            return "Timer"
        case .keepDisplayOn:
            return "Keep Display On"
        case .keepAwake:
            return "Keep Awake"
        case .cleanKeyboard:
            return "Clean Keyboard"
        case .clipboardHistory:
            return "Clipboard History"
        case .quickCommands:
            return "Custom Command Buttons"
        }
    }

    var symbolName: String {
        switch self {
        case .timer:
            return "timer"
        case .keepDisplayOn:
            return "moon.zzz"
        case .keepAwake:
            return "lock.shield"
        case .cleanKeyboard:
            return "keyboard"
        case .clipboardHistory:
            return "clipboard"
        case .quickCommands:
            return "rectangle.grid.2x2"
        }
    }
}
