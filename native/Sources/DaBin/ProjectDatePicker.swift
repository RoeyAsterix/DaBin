import SwiftUI

/// A day or a complete local-calendar week can be chosen with one click.
/// Adjacent-month dates remain visible so a week never appears cut in half.
@MainActor
struct ProjectDatePicker: View {
    let selection: ProjectDateSelection?
    let dateFilter: WorkspaceDateFilter
    let activityDays: Set<String>
    let onSelect: (ProjectDateSelection) -> Void
    let onClear: () -> Void
    let dismiss: () -> Void
    @Environment(\.daBinAccent) private var accent
    @State private var month: Date
    @State private var mode: ProjectDateSelection.Mode
    @State private var hoveredDay: Date?
    @FocusState private var focusedDay: Date?

    init(selection: ProjectDateSelection?, dateFilter: WorkspaceDateFilter,
         activityDays: Set<String>, onSelect: @escaping (ProjectDateSelection) -> Void,
         onClear: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.selection = selection
        self.dateFilter = dateFilter
        self.activityDays = activityDays
        self.onSelect = onSelect
        self.onClear = onClear
        self.dismiss = dismiss
        _month = State(initialValue: TimelineCalendarLayout.monthStart(selection?.date() ?? Date()))
        _mode = State(initialValue: selection?.mode ?? (dateFilter == .lastSevenDays ? .week : .day))
    }

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var activeSelection: ProjectDateSelection? {
        if let selection { return selection.mode == mode ? selection : nil }
        return dateFilter == .today && mode == .day ? ProjectDateSelection(date: today, mode: .day) : nil
    }
    private var cells: [Date] {
        let start = TimelineCalendarLayout.monthStart(month, calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = ((leading + range.count + 6) / 7) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: start) }
    }
    private var weeks: [[Date]] {
        let days = cells
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 3) {
                modeButton(.day, title: "Day")
                modeButton(.week, title: "Week")
            }
            .padding(3)
            .background(Palette.soft, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Choose a day or week")

            HStack(spacing: 4) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                monthButton(-1)
                monthButton(1)
            }

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(Array(TimelineCalendarLayout.weekdays(calendar: calendar).enumerated()), id: \.offset) { _, title in
                        Text(title).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted).frame(width: 36, height: 18)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    weekRow(week)
                }
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 12) {
                shortcut("Any date", id: "project-date-any", active: selection == nil && dateFilter == .anytime) {
                    onClear()
                    dismiss()
                }
                Spacer(minLength: 0)
                shortcut("Today", id: "project-date-today") { choose(today, mode: .day) }
                shortcut("This week", id: "project-date-this-week") { choose(today, mode: .week) }
            }
        }
        .padding(16).frame(width: 288)
        .background(Palette.surface).foregroundStyle(Palette.foreground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project date picker")
        .accessibilityIdentifier("project-date-picker")
        .onMoveCommand(perform: moveFocus)
        .onExitCommand(perform: dismiss)
        .onAppear { focusedDay = calendar.startOfDay(for: selection?.date() ?? today) }
    }

    private func modeButton(_ value: ProjectDateSelection.Mode, title: String) -> some View {
        let selected = mode == value
        return Button {
            mode = value
            hoveredDay = nil
        } label: {
            Text(title).font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 30)
                .foregroundStyle(selected ? accent : Palette.muted)
                .background(selected ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Palette.line : Color.clear, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).accessibilityLabel("Choose a \(title.lowercased())")
        .accessibilityHint(value == .day ? "Select one calendar day" : "Select a complete calendar week")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("project-date-mode-\(value.rawValue)")
    }

    private func monthButton(_ offset: Int) -> some View {
        Button {
            guard let next = calendar.date(byAdding: .month, value: offset, to: month) else { return }
            month = TimelineCalendarLayout.monthStart(next, calendar: calendar)
            hoveredDay = nil
            focusedDay = month
        } label: {
            Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
                .background(Palette.soft, in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(Palette.muted)
        .accessibilityLabel(offset < 0 ? "Previous month" : "Next month")
        .accessibilityIdentifier(offset < 0 ? "project-calendar-prev" : "project-calendar-next")
    }

    private func weekRow(_ week: [Date]) -> some View {
        let selected = mode == .week && week.contains { activeSelection?.includes(day: dayKey($0)) == true }
        let preview = mode == .week && week.contains { $0 == hoveredDay || $0 == focusedDay }
        return HStack(spacing: 0) {
            ForEach(week, id: \.self) { day in dayButton(day) }
        }
        .background(selected ? accent.opacity(0.18) : preview ? accent.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = activeSelection?.includes(day: dayKey(day)) == true
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let active = activityDays.contains(dayKey(day))
        return Button { choose(day, mode: mode) } label: {
            ZStack(alignment: .bottom) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: selected ? .bold : .medium)).monospacedDigit()
                    .frame(width: 34, height: 34)
                if active {
                    Circle().fill(accent).frame(width: 3, height: 3).padding(.bottom, 3)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? accent : inMonth ? Palette.foreground : Palette.muted.opacity(0.65))
            .background(mode == .day && selected ? accent.opacity(0.18)
                        : mode == .day && hoveredDay == day ? accent.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                focusedDay == day ? accent.opacity(0.9) : isToday ? accent.opacity(0.45) : Color.clear,
                lineWidth: focusedDay == day ? 1.5 : 1))
            .frame(width: 36, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focused($focusedDay, equals: day)
        .onHover { if $0 { hoveredDay = day } else if hoveredDay == day { hoveredDay = nil } }
        .accessibilityLabel(mode == .day ? day.formatted(date: .complete, time: .omitted)
                            : "\(day.formatted(date: .complete, time: .omitted)), \(ProjectDateSelection(date: day, mode: .week).accessibilityLabel)")
        .accessibilityValue([selected ? "Selected" : "", isToday ? "Today" : "", active ? "Has saved items" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(mode == .day ? "Show project items saved on this day" : "Show project items saved during this week")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("project-calendar-day-\(dayKey(day))")
    }

    private func shortcut(_ title: String, id: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: active ? .semibold : .medium))
                .frame(minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityIdentifier(id)
    }

    private func choose(_ day: Date, mode: ProjectDateSelection.Mode) {
        onSelect(ProjectDateSelection(date: day, mode: mode, calendar: calendar))
        dismiss()
    }

    private func dayKey(_ day: Date) -> String {
        CaptureCalendar.dayString(day, timeZone: calendar.timeZone)
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -7
        case .down: delta = 7
        default: return
        }
        let start = calendar.startOfDay(for: focusedDay ?? selection?.date() ?? month)
        guard let next = calendar.date(byAdding: .day, value: delta, to: start) else { return }
        month = TimelineCalendarLayout.monthStart(next, calendar: calendar)
        focusedDay = next
    }
}
