import SwiftUI

struct TimerDurationFields: View {
    @Binding var input: TimerInput
    var foregroundStyle: Color = .primary
    var fieldBackground: Color = MacletSystemColors.controlBackground
    var isProminent = false
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 5) {
            field("Hours", text: $input.hours, isValid: input.isHoursValid)
            unit("h")
            field("Minutes", text: $input.minutes, isValid: input.isMinutesValid)
            unit("m")
            field("Seconds", text: $input.seconds, isValid: input.isSecondsValid)
            unit("s")
        }
        .onChange(of: input.hours) { _, _ in input.sanitize() }
        .onChange(of: input.minutes) { _, _ in input.sanitize() }
        .onChange(of: input.seconds) { _, _ in input.sanitize() }
    }

    private func field(_ label: String, text: Binding<String>, isValid: Bool) -> some View {
        TextField("00", text: text)
            .textFieldStyle(.plain)
            .font(.system(
                size: isProminent ? 17 : 12,
                weight: .medium,
                design: .monospaced
            ))
            .foregroundStyle(foregroundStyle)
            .multilineTextAlignment(.center)
            .frame(width: isProminent ? 44 : 35, height: isProminent ? 34 : 28)
            .background(
                fieldBackground,
                in: RoundedRectangle(
                    cornerRadius: isProminent ? 9 : 7,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: isProminent ? 9 : 7,
                    style: .continuous
                )
                    .stroke(isValid ? Color.clear : Color.red, lineWidth: 1)
            }
            .accessibilityLabel(label)
            .onSubmit(onSubmit)
    }

    private func unit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: isProminent ? 12 : 10, weight: .medium))
            .foregroundStyle(foregroundStyle.opacity(0.72))
    }
}
