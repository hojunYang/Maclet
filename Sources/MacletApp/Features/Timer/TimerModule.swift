import SwiftUI

struct TimerModule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var manager: CountdownTimerManager
    @State private var input = TimerInput()

    let presets: [Int]
    let start: (Int) -> Void
    let pause: () -> Void
    let resume: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                CommandCenterFeatureLabel(
                    title: "Timer",
                    systemName: "timer",
                    isActive: manager.phase.isActive
                )

                Spacer(minLength: 0)
            }

            Group {
                if manager.phase.isActive {
                    ActiveTimerStatus(
                        manager: manager,
                        pause: pause,
                        resume: resume,
                        stop: stop
                    )
                    .transition(MacletMotion.contentTransition(reduceMotion: reduceMotion, anchor: .top))
                } else {
                    idleControls
                        .transition(MacletMotion.contentTransition(reduceMotion: reduceMotion, anchor: .bottom))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(CommandCenterMetrics.expandedFeatureInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .controlCenterSurface(cornerRadius: CommandCenterMetrics.featureCardCornerRadius)
    }

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TimerDurationFields(
                    input: $input,
                    foregroundStyle: CommandCenterPalette.text,
                    fieldBackground: CommandCenterPalette.inactiveIconFill,
                    isProminent: presets.isEmpty,
                    onSubmit: startInput
                )

                Spacer(minLength: 0)

                Button(action: startInput) {
                    Image(systemName: "play.fill")
                        .frame(
                            width: presets.isEmpty ? 34 : 28,
                            height: presets.isEmpty ? 34 : 28
                        )
                        .controlCenterSurface(
                            cornerRadius: presets.isEmpty ? 17 : 14,
                            isActive: input.totalSeconds != nil
                        )
                }
                .buttonStyle(.plain)
                .disabled(input.totalSeconds == nil)
                .help("Start Timer")
            }

            if !presets.isEmpty {
                HStack(spacing: 5) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            input = TimerInput(seconds: seconds)
                            start(seconds)
                        } label: {
                            Text(CountdownText.preset(seconds: seconds))
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .controlCenterSurface(cornerRadius: 13)
                        }
                        .buttonStyle(.plain)
                        .help("Start a \(CountdownText.preset(seconds: seconds)) timer")
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: presets.isEmpty ? .center : .top)
    }

    private func startInput() {
        guard let seconds = input.totalSeconds else {
            return
        }
        start(seconds)
    }
}

private struct ActiveTimerStatus: View {
    @ObservedObject var manager: CountdownTimerManager
    let pause: () -> Void
    let resume: () -> Void
    let stop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 10) {
                CommandCenterCountdownLabel(
                    text: CountdownText.clock(
                        seconds: manager.phase.remainingSeconds(at: timeline.date) ?? 0
                    )
                )

                HStack(spacing: 6) {
                    CommandCenterActionButton(
                        title: manager.phase.isPaused ? "Resume" : "Pause"
                    ) {
                        manager.phase.isPaused ? resume() : pause()
                    }

                    CommandCenterActionButton(title: "Stop", action: stop)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
