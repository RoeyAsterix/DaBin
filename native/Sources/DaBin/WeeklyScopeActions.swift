import SwiftUI

/// Weekly keeps the compact header while exposing the range choice in a small
/// anchored popover. The selected day is always one of the seven fixed local
/// calendar days, including days hidden from the activity-only week columns.
@MainActor
struct WeeklySearchButton: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    var body: some View {
        AccentIconButton(symbol: TimelinePrimaryAction.search.symbol,
                         label: "Search a day or week",
                         selected: isPresented,
                         accessibilityIdentifier: "timeline-action-search") {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            WeeklySearchPopover(state: state, isPresented: $isPresented)
        }
        .onChange(of: state.weekEndingDay) { _, _ in isPresented = false }
        .onDisappear { isPresented = false }
    }
}

@MainActor
struct WeeklySearchPopover: View {
    private enum Choice: Hashable { case day, week }

    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool
    @FocusState private var focusedChoice: Choice?

    private var daySelection: Binding<Date> {
        Binding(get: { state.weeklyActionDay }, set: { state.selectWeeklyActionDay($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            WeeklyDayPicker(days: state.weeklyDays, selection: daySelection)

            scopeButton(title: "Search Day", symbol: "calendar",
                        choice: .day,
                        shortcut: "1", shortcutLabel: "⌘1",
                        hint: "Search only \(state.weeklyActionDay.formatted(date: .complete, time: .omitted))") {
                let day = state.weeklyActionDay
                isPresented = false
                state.openSearch(day: day)
            }

            scopeButton(title: "Search Week", symbol: "rectangle.stack",
                        choice: .week,
                        shortcut: "7", shortcutLabel: "⌘7",
                        hint: "Search all seven days in the displayed week") {
                let days = state.weeklyDays
                isPresented = false
                state.openSearch(week: days)
            }
        }
        .padding(12)
        .frame(width: 238)
        .onAppear { DispatchQueue.main.async { focusedChoice = .day } }
        .onExitCommand { isPresented = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search day or week actions")
    }

    private func scopeButton(title: String, symbol: String, choice: Choice,
                             shortcut: KeyEquivalent, shortcutLabel: String,
                             hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(shortcutLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(focusedChoice == choice ? accent.opacity(0.16) : Palette.soft,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(focusedChoice == choice ? accent : .clear, lineWidth: 1.25)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .focused($focusedChoice, equals: choice)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

@MainActor
struct WeeklyDayPicker: View {
    let days: [Date]
    @Binding var selection: Date

    var body: some View {
        Picker("Day", selection: $selection) {
            ForEach(days, id: \.self) { day in
                Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .tag(day)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Choose the day used by day actions")
        .accessibilityLabel("Day for weekly actions")
        .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
    }
}
