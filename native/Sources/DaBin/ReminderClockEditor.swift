import SwiftUI

/// Both editors resolve countdowns only when their draft is saved.
@MainActor
struct ReminderClockEditor: View {
    @Environment(\.daBinAccent) private var accent
    @Binding var enabled: Bool
    @Binding var mode: ReminderScheduleMode
    @Binding var date: Date
    @Binding var hours: Int
    @Binding var minutes: Int

    private var minuteAngle: Double { Double(mode == .countdown ? minutes : Calendar.current.component(.minute, from: date)) * 6 }
    private var hourAngle: Double { Double(mode == .countdown ? hours % 12 : Calendar.current.component(.hour, from: date) % 12) * 30 + minuteAngle / 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Reminder", systemImage: "clock").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Reminder", isOn: $enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("reminder-enabled")
            }
            if enabled {
                HStack(spacing: 14) {
                    clock.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            modeButton(.countdown, title: "Countdown", symbol: "timer")
                            modeButton(.date, title: "Date", symbol: "calendar")
                        }
                        if mode == .countdown {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                durationField("Hours", value: $hours)
                                Text(":").font(.system(size: 26, weight: .light, design: .rounded)).foregroundStyle(accent)
                                durationField("Minutes", value: $minutes)
                            }
                        } else {
                            DatePicker("Remind me", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.field).labelsHidden().controlSize(.small)
                                .accessibilityLabel("Reminder date and time")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(mode == .countdown ? "Hours : minutes · starts when you save" : TimeZone.current.identifier)
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.14), lineWidth: 0.7))
    }

    private var clock: some View {
        ZStack {
            Circle().fill(Palette.surface)
            Circle().stroke(accent.opacity(0.25), lineWidth: 1)
            ForEach(0..<12) { tick in
                Capsule().fill(accent.opacity(tick.isMultiple(of: 3) ? 0.7 : 0.28))
                    .frame(width: 1.5, height: tick.isMultiple(of: 3) ? 5 : 3)
                    .offset(y: -25).rotationEffect(.degrees(Double(tick) * 30))
            }
            Capsule().fill(accent).frame(width: 3, height: 16).offset(y: -7).rotationEffect(.degrees(hourAngle))
            Capsule().fill(accent).frame(width: 2, height: 22).offset(y: -10).rotationEffect(.degrees(minuteAngle))
            Circle().fill(accent).frame(width: 5, height: 5)
        }.frame(width: 64, height: 64).shadow(color: accent.opacity(0.08), radius: 8, y: 3)
    }

    private func modeButton(_ target: ReminderScheduleMode, title: String, symbol: String) -> some View {
        Button { mode = target } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(mode == target ? accent.opacity(0.14) : .clear, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityAddTraits(mode == target ? .isSelected : [])
            .accessibilityIdentifier("reminder-mode-\(target == .date ? "date" : "countdown")")
    }

    private func durationField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number.grouping(.never))
            .font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
            .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 48)
            .padding(.vertical, 4).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Countdown \(title.lowercased())")
    }
}
