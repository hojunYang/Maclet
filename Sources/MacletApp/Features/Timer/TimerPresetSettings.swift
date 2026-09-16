import SwiftUI
import MacletCore

struct TimerPresetSettings: View {
    @EnvironmentObject private var appState: AppState
    @State private var newPreset = TimerInput()

    private var presets: [Int] {
        appState.settings.timerPresetSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preset Times")
                    .foregroundStyle(.secondary)

                Spacer()

                Text(presets.isEmpty ? "None" : "\(presets.count)/\(AppSettings.maximumTimerPresets)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !presets.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(presets.enumerated()), id: \.element) { index, seconds in
                        TimerPresetRow(
                            seconds: seconds,
                            canMoveUp: index > 0,
                            canMoveDown: index < presets.count - 1,
                            canSave: { value in
                                !presets.enumerated().contains { offset, seconds in
                                    offset != index && seconds == value
                                }
                            },
                            save: { value in replacePreset(at: index, with: value) },
                            moveUp: { movePreset(from: index, to: index - 1) },
                            moveDown: { movePreset(from: index, to: index + 1) },
                            delete: { deletePreset(at: index) }
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                TimerDurationFields(input: $newPreset, onSubmit: addPreset)

                Spacer()

                Button(action: addPreset) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(!canAddPreset)
            }
        }
        .font(.subheadline)
    }

    private var canAddPreset: Bool {
        guard let seconds = newPreset.totalSeconds else {
            return false
        }
        return presets.count < AppSettings.maximumTimerPresets && !presets.contains(seconds)
    }

    private func addPreset() {
        guard canAddPreset, let seconds = newPreset.totalSeconds else {
            return
        }
        appState.setTimerPresets(presets + [seconds])
        newPreset = TimerInput()
    }

    private func replacePreset(at index: Int, with seconds: Int) {
        guard presets.indices.contains(index) else {
            return
        }
        var values = presets
        values[index] = seconds
        appState.setTimerPresets(values)
    }

    private func movePreset(from source: Int, to destination: Int) {
        guard presets.indices.contains(source), presets.indices.contains(destination) else {
            return
        }
        var values = presets
        values.swapAt(source, destination)
        appState.setTimerPresets(values)
    }

    private func deletePreset(at index: Int) {
        guard presets.indices.contains(index) else {
            return
        }
        var values = presets
        values.remove(at: index)
        appState.setTimerPresets(values)
    }
}

private struct TimerPresetRow: View {
    @State private var input: TimerInput

    let seconds: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canSave: (Int) -> Bool
    let save: (Int) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    init(
        seconds: Int,
        canMoveUp: Bool,
        canMoveDown: Bool,
        canSave: @escaping (Int) -> Bool,
        save: @escaping (Int) -> Void,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        delete: @escaping () -> Void
    ) {
        _input = State(initialValue: TimerInput(seconds: seconds))
        self.seconds = seconds
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.canSave = canSave
        self.save = save
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.delete = delete
    }

    var body: some View {
        HStack(spacing: 7) {
            TimerDurationFields(input: $input, onSubmit: saveInput)

            Text(CountdownText.preset(seconds: seconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            IconButton(systemName: "checkmark", title: "Save") {
                saveInput()
            }
            .disabled(!canSaveInput || input.totalSeconds == seconds)

            IconButton(systemName: "arrow.up", title: "Move Up", action: moveUp)
                .disabled(!canMoveUp)

            IconButton(systemName: "arrow.down", title: "Move Down", action: moveDown)
                .disabled(!canMoveDown)

            IconButton(systemName: "trash", title: "Delete", role: .destructive, action: delete)
        }
        .padding(7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var canSaveInput: Bool {
        input.totalSeconds.map(canSave) == true
    }

    private func saveInput() {
        guard let value = input.totalSeconds, canSave(value) else {
            return
        }
        save(value)
    }
}
