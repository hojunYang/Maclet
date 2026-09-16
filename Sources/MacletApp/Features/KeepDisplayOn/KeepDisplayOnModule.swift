import SwiftUI

struct KeepDisplayOnModule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = Array(
        repeating: GridItem(.fixed(CommandCenterLayout.keepDisplayOnControlHeight), spacing: 5),
        count: 4
    )
    let option: KeepDisplayOnDuration
    let activeUntil: Date?
    let setKeepDisplayOn: (KeepDisplayOnDuration) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    CommandCenterFeatureLabel(
                        title: "Keep\nDisplay On",
                        systemName: "display",
                        isActive: option.keepsDisplayOn
                    )

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 4)

                Group {
                    if option.keepsDisplayOn {
                        ActiveKeepDisplayOnStatus(
                            option: option,
                            activeUntil: activeUntil,
                            now: timeline.date
                        ) {
                            setKeepDisplayOn(.off)
                        }
                        .transition(MacletMotion.contentTransition(reduceMotion: reduceMotion, anchor: .top))
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                            ForEach(KeepDisplayOnDuration.controls) { option in
                                KeepDisplayOnDurationButton(option: option) {
                                    setKeepDisplayOn(option)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .transition(MacletMotion.contentTransition(reduceMotion: reduceMotion, anchor: .bottom))
                    }
                }
                .frame(
                    height: option.keepsDisplayOn
                        ? 64
                        : CommandCenterLayout.keepDisplayOnControlHeight * 2 + 5,
                    alignment: .bottom
                )
            }
            .padding(CommandCenterMetrics.expandedFeatureInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .controlCenterSurface(cornerRadius: CommandCenterMetrics.featureCardCornerRadius)
        }
    }
}

private struct KeepDisplayOnDurationButton: View {
    let option: KeepDisplayOnDuration
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(option.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(CommandCenterPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(
                    width: CommandCenterLayout.keepDisplayOnControlHeight,
                    height: CommandCenterLayout.keepDisplayOnControlHeight
                )
                .controlCenterSurface(cornerRadius: CommandCenterLayout.keepDisplayOnControlHeight / 2)
        }
        .buttonStyle(.plain)
        .help("Keep the display on for \(option.label)")
    }
}

private struct ActiveKeepDisplayOnStatus: View {
    let option: KeepDisplayOnDuration
    let activeUntil: Date?
    let now: Date
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommandCenterCountdownLabel(
                text: option.remainingText(until: activeUntil, now: now)
            )

            CommandCenterActionButton(title: "Stop", action: stop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
