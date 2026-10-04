import SwiftUI

/// Calendar arithmetic stays in local civil days, including across DST and
/// locale-specific week starts. Only occupied weeks take vertical space.
enum TimelineCalendarLayout {
    static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func cells(in month: Date, calendar: Calendar = .current) -> [Date?] {
        let start = monthStart(month, calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
        let cellCount = ((leading + dates.count + 6) / 7) * 7
        return Array(repeating: nil, count: leading) + dates.map(Optional.some)
            + Array(repeating: nil, count: cellCount - leading - dates.count)
    }

    static func weekdays(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}

/// Weekly edits are staged until Apply. Dismissing the popover leaves the
/// current calendar and window untouched; a daily selection opens immediately.
@MainActor
struct TimelineCalendarPicker: View {
    @ObservedObject var state: AppState
    let weekly: Bool
    let dismiss: () -> Void
    @Environment(\.daBinAccent) private var accent
    @State private var month: Date
    @State private var selection: Set<Date>
    @State private var useCurrentWeek = false
    @State private var hoveredDay: Date?
    @FocusState private var focusedDay: Date?

    init(state: AppState, weekly: Bool, dismiss: @escaping () -> Void) {
        self.state = state
        self.weekly = weekly
        self.dismiss = dismiss
        let days = weekly ? state.weeklyDays : [state.selectedDay]
        _selection = State(initialValue: Set(days.map { Calendar.current.startOfDay(for: $0) }))
        _month = State(initialValue: TimelineCalendarLayout.monthStart(days.last ?? Date()))
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var activityDays: Set<String> {
        Set(TimelineCalendarLayout.cells(in: month).compactMap { $0 }.filter { !state.allCaptures(for: $0).isEmpty }.map { CaptureCalendar.dayString($0) })
    }
    private var visibleCount: Int { selection.filter { !state.allCaptures(for: $0).isEmpty }.count }

    var body: some View {
        let daysWithActivity = activityDays
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekly ? "Choose your days" : "Jump to a day")
                    .font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if weekly {
                    Text("\(selection.count) / 7").monospacedDigit().font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(accent.opacity(0.12), in: Capsule())
                        .accessibilityLabel("\(selection.count) of 7 days selected")
                        .accessibilityIdentifier("calendar-selection-count")
                }
            }
            if weekly {
                Text("Pick up to 7 days. Days with activity appear side by side.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                monthButton(-1)
                monthButton(1)
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(Array(TimelineCalendarLayout.weekdays().enumerated()), id: \.offset) { _, title in
                        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                            .frame(width: 36, height: 18).accessibilityHidden(true)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(TimelineCalendarLayout.cells(in: month).enumerated()), id: \.offset) { _, day in
                        if let day { dayButton(day, active: daysWithActivity.contains(CaptureCalendar.dayString(day))) }
                        else { Color.clear.frame(width: 36, height: 36).accessibilityHidden(true) }
                    }
                }
                .onMoveCommand { direction in moveFocus(direction) }
            }
            HStack(spacing: 5) {
                Circle().fill(accent).frame(width: 4, height: 4).accessibilityHidden(true)
                Text("Saved activity").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Button(weekly ? "Last 7 days" : "Today") {
                    if weekly {
                        selection = Set((-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) })
                        month = TimelineCalendarLayout.monthStart(today)
                        useCurrentWeek = true
                    } else { state.selectWeeklyDay(today); dismiss() }
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                    .frame(minHeight: 28).accessibilityIdentifier("calendar-today")
            }
            if weekly {
                Rectangle().fill(Palette.line).frame(height: 1)
                Text(selection.count == 7 ? "7 days selected. Uncheck a day to choose another."
                     : "\(visibleCount) \(visibleCount == 1 ? "day has" : "days have") activity · empty days stay hidden")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 28, alignment: .leading)
                HStack(spacing: 8) {
                    Button("Clear") { selection.removeAll(); useCurrentWeek = false }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).frame(minHeight: 32)
                        .disabled(selection.isEmpty).accessibilityIdentifier("calendar-clear")
                    Spacer(minLength: 4)
                    Button("Cancel", action: dismiss).buttonStyle(.plain).frame(minHeight: 32)
                        .accessibilityIdentifier("calendar-cancel")
                    Button {
                        if useCurrentWeek { state.showCurrentWeek(); dismiss() }
                        else if state.setWeeklyDays(Array(selection)) { dismiss() }
                    } label: {
                        Text(selection.count == 1 ? "Show day" : "Show \(selection.count) days")
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
                            .background(accent.opacity(selection.isEmpty ? 0.05 : 0.18), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.35), lineWidth: 1))
                    }.buttonStyle(.plain).foregroundStyle(accent).disabled(selection.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("calendar-apply")
                }.font(.system(size: 12))
            }
        }
        .padding(16).frame(width: 308).background(Palette.surface).foregroundStyle(Palette.foreground)
        .accessibilityElement(children: .contain).accessibilityLabel(weekly ? "Choose up to seven days" : "Choose date")
        .accessibilityIdentifier("timeline-calendar")
        .onExitCommand(perform: dismiss)
    }

    private func monthButton(_ offset: Int) -> some View {
        Button {
            if let date = Calendar.current.date(byAdding: .month, value: offset, to: month) { month = date }
        } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
                .background(Palette.soft, in: Circle()).contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(accent)
            .disabled(offset > 0 && month >= TimelineCalendarLayout.monthStart(today))
            .accessibilityLabel(offset < 0 ? "Previous month" : "Next month")
            .accessibilityIdentifier(offset < 0 ? "calendar-previous-month" : "calendar-next-month")
    }

    private func dayButton(_ day: Date, active: Bool) -> some View {
        let selected = selection.contains(day)
        let future = day > today
        let full = weekly && selection.count >= 7 && !selected
        return Button {
            if weekly {
                useCurrentWeek = false
                if selected { selection.remove(day) }
                else if selection.count < 7 { selection.insert(day) }
            } else { state.selectWeeklyDay(day); dismiss() }
        } label: {
            ZStack(alignment: .bottom) {
                Text(day.formatted(.dateTime.day())).font(.system(size: 13, weight: selected ? .bold : .medium))
                    .monospacedDigit().frame(width: 36, height: 36)
                if active { Circle().fill(accent).frame(width: 4, height: 4).padding(.bottom, 3) }
            }
            .foregroundStyle(selected ? accent : Palette.foreground)
            .background(selected ? accent.opacity(0.19) : hoveredDay == day ? accent.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(
                day == today ? accent.opacity(0.8) : selected ? accent.opacity(0.3) : Color.clear, lineWidth: 1))
            .opacity(future ? 0.6 : full ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(future || full).focused($focusedDay, equals: day)
            .onHover { if $0 { hoveredDay = day } else if hoveredDay == day { hoveredDay = nil } }
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityValue(selected ? "Selected" : active ? "Has saved activity" : "No saved activity")
            .accessibilityHint(full ? "Seven days selected. Deselect a day to add another." : weekly ? "Toggle this day" : "Open this day")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("calendar-day-\(CaptureCalendar.dayString(day))")
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let delta: Int
        switch direction { case .left: delta = -1; case .right: delta = 1; case .up: delta = -7; case .down: delta = 7; default: return }
        let start = focusedDay ?? selection.sorted().last ?? min(month, today)
        let next: Date
        if weekly && selection.count >= 7 {
            // Skip disabled dates instead of trapping keyboard focus at gaps.
            let candidates = selection.sorted()
            guard let selected = delta < 0 ? candidates.last(where: { $0 < start }) : candidates.first(where: { $0 > start }) else { return }
            next = selected
        } else {
            guard let date = Calendar.current.date(byAdding: .day, value: delta, to: start), date <= today else { return }
            next = date
        }
        month = TimelineCalendarLayout.monthStart(next)
        focusedDay = next
    }
}
