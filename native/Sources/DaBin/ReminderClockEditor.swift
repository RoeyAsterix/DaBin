import SwiftUI

/// Both editors resolve countdowns only when their draft is saved.
@MainActor
struct ReminderClockEditor: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.workspaceZoom) private var zoom
    @Binding var enabled: Bool
    @Binding var mode: ReminderScheduleMode
    @Binding var date: Date
    @Binding var hours: Int
    @Binding var minutes: Int

    private var controlFont: CGFloat { min(15, max(12, zoom.fontSize(13))) }
    private var summary: String {
        if mode == .date { return date.formatted(date: .abbreviated, time: .shortened) }
        return hours == 0 ? "In \(minutes) minutes" : "In \(hours)h \(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if enabled {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        reminderLabel
                        Spacer(minLength: 4)
                        modeChoices
                        reminderToggle
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) { reminderLabel; Spacer(minLength: 4); reminderToggle }
                        modeChoices
                    }
                }
            } else {
                HStack(spacing: 4) { reminderLabel; Spacer(minLength: 4); reminderToggle }
            }
            BuddyActionFlow {
                preset("15 min", identifier: "reminder-preset-15") { chooseCountdown(hours: 0, minutes: 15) }
                preset("1 hour", identifier: "reminder-preset-60") { chooseCountdown(hours: 1, minutes: 0) }
                preset("Tomorrow", identifier: "reminder-preset-tomorrow", action: chooseTomorrow)
            }
            if enabled {
                if mode == .countdown {
                    HStack(alignment: .top, spacing: 8) {
                        durationField("Hours", value: $hours, identifier: "reminder-countdown-hours")
                        durationField("Minutes", value: $minutes, identifier: "reminder-countdown-minutes")
                    }
                } else {
                    // Separate native fields keep both controls readable when
                    // the pane is narrow; they continue editing one Date value.
                    BuddyActionFlow {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.field).labelsHidden().controlSize(.regular)
                            .fixedSize().frame(minHeight: 32)
                            .accessibilityLabel("Reminder date")
                            .accessibilityIdentifier("reminder-date-time")
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.field).labelsHidden().controlSize(.regular)
                            .fixedSize().frame(minHeight: 32)
                            .accessibilityLabel("Reminder time")
                            .accessibilityIdentifier("reminder-time")
                    }
                }
                Text(mode == .countdown ? "Countdown starts when saved." : TimeZone.current.identifier)
                    .font(.system(size: min(13, max(11, zoom.fontSize(11))))).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.14), lineWidth: 0.7))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Reminder")
            .accessibilityValue(enabled ? summary : "Off")
            .accessibilityIdentifier("reminder-editor")
    }

    private var reminderLabel: some View {
        Button { enabled.toggle() } label: {
            Label("Reminder", systemImage: "clock")
                .font(.system(size: controlFont, weight: .semibold))
                .frame(minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Reminder")
            .accessibilityValue(enabled ? "On" : "Off")
            .accessibilityHint("Turn the reminder on or off")
            .accessibilityIdentifier("reminder-label-toggle")
    }

    private var reminderToggle: some View {
        Toggle("Reminder", isOn: $enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
            .frame(minHeight: 32)
            .accessibilityLabel("Reminder")
            .accessibilityIdentifier("reminder-enabled")
    }

    private var modeChoices: some View {
        HStack(spacing: 4) {
            modeButton(.countdown, title: "Countdown")
            modeButton(.date, title: "Date")
        }
    }

    private func preset(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: controlFont, weight: .medium))
                .padding(.horizontal, 10).frame(minHeight: 32)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 0.7))
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityLabel(title == "Tomorrow" ? "Remind me tomorrow at 9 AM" : "Remind me in \(title)")
            .accessibilityIdentifier(identifier)
    }

    private func chooseCountdown(hours: Int, minutes: Int) {
        self.hours = hours; self.minutes = minutes
        mode = .countdown; enabled = true
    }

    private func chooseTomorrow() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
              let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else { return }
        date = morning; mode = .date; enabled = true
    }

    private func modeButton(_ target: ReminderScheduleMode, title: String) -> some View {
        Button { mode = target } label: {
            Text(title).font(.system(size: controlFont, weight: .medium))
                .padding(.horizontal, 6).frame(minHeight: 32).contentShape(RoundedRectangle(cornerRadius: 7))
                .background(mode == target ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityAddTraits(mode == target ? .isSelected : [])
            .accessibilityIdentifier("reminder-mode-\(target == .date ? "date" : "countdown")")
    }

    private func durationField(_ title: String, value: Binding<Int>, identifier: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: controlFont)).foregroundStyle(Palette.muted)
            TextField(title, value: value, format: .number.grouping(.never))
                .font(.system(size: min(22, zoom.fontSize(18)), design: .rounded)).monospacedDigit()
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 56, height: 32)
                .accessibilityLabel("Countdown \(title.lowercased())")
                .accessibilityIdentifier(identifier)
        }
    }
}
