import AppKit
import Carbon
import SwiftUI
import MacletCore

struct GlobalShortcutPanel: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var recorder = ShortcutRecorder()

    private var shortcut: GlobalShortcut? {
        appState.settings.commandCenterShortcut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Global Shortcut", systemImage: "keyboard")
                    .font(.headline)

                Spacer()

                Toggle("Global Shortcut", isOn: Binding(
                    get: { shortcut != nil },
                    set: setEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if let shortcut {
                HStack(spacing: 8) {
                    Text("Open Maclet")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        recorder.isRecording ? cancelRecording() : beginRecording()
                    } label: {
                        Text(recorder.isRecording ? "Press shortcut…" : shortcut.displayName)
                            .frame(minWidth: 108)
                    }
                    .buttonStyle(.bordered)

                    Button("Reset") {
                        cancelRecording()
                        appState.setCommandCenterShortcut(.defaultCommandCenter)
                    }
                    .disabled(shortcut == .defaultCommandCenter)
                }

                Text(recorder.message ?? "Works while another app is active. Click the shortcut to change it.")
                    .font(.caption)
                    .foregroundStyle(recorder.message == nil ? Color.secondary : Color.orange)
            } else {
                Text("Turn this on to open Maclet from anywhere with a keyboard shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = appState.globalShortcutRegistrationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .panelStyle()
        .onDisappear {
            cancelRecording()
        }
    }

    private func setEnabled(_ enabled: Bool) {
        cancelRecording()
        appState.setCommandCenterShortcut(enabled ? .defaultCommandCenter : nil)
    }

    private func beginRecording() {
        appState.setGlobalShortcutRecording(true)
        recorder.start(
            onCapture: { shortcut in
                appState.setCommandCenterShortcut(shortcut)
            },
            onEnd: {
                appState.setGlobalShortcutRecording(false)
            }
        )
    }

    private func cancelRecording() {
        recorder.stop()
        appState.setGlobalShortcutRecording(false)
    }
}

private final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?

    private var eventMonitor: Any?
    private var onCapture: ((GlobalShortcut) -> Void)?
    private var onEnd: (() -> Void)?

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    func start(
        onCapture: @escaping (GlobalShortcut) -> Void,
        onEnd: @escaping () -> Void
    ) {
        stop()
        self.onCapture = onCapture
        self.onEnd = onEnd
        isRecording = true
        message = "Press a shortcut with at least one modifier. Escape cancels."

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }

            guard !event.isARepeat else {
                return nil
            }

            guard let shortcut = GlobalShortcut.make(from: event) else {
                self.message = "Include fn, Control, Option, Shift, or Command."
                return nil
            }

            self.onCapture?(shortcut)
            self.stop()
            return nil
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        let end = onEnd
        onCapture = nil
        onEnd = nil
        isRecording = false
        message = nil
        end?()
    }
}
