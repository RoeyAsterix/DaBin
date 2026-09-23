import SwiftUI

@MainActor
struct WeeklyScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCalendar = false
    @State private var columnsSettled = false

    private var rangeLabel: String {
        guard let first = state.weeklyDays.first else { return "Last seven days" }
        let start = first.formatted(.dateTime.month(.abbreviated).day())
        let end = state.weekEndingDay.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    HStack(spacing: 1) {
                        SmallIcon(symbol: "chevron.left", label: "Previous seven days") { state.moveWeek(-1) }
                        SmallIcon(symbol: "chevron.right", label: "Next seven days") { state.moveWeek(1) }
                            .disabled(Calendar.current.isDateInToday(state.weekEndingDay))
                    }
                    Spacer(minLength: 0)
                    Button("This Week") { state.showCurrentWeek() }
                        .font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
                        .foregroundStyle(accent).padding(.vertical, 7)
                        .help("Show the last seven days ending today")
                }
                Button { showCalendar.toggle() } label: {
                    HStack(spacing: 7) {
                        Text(rangeLabel).font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.padding(.horizontal, 9).padding(.vertical, 7)
                }.buttonStyle(.plain).help("Choose the last day of the week")
                    .accessibilityLabel("Choose week, \(rangeLabel)")
                    .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                        DatePicker("Week ending", selection: $state.weekEndingDay, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical).padding(12).frame(width: 280)
                            .onChange(of: state.weekEndingDay) { _, _ in showCalendar = false }
                    }
            }.padding(.horizontal, 17).padding(.bottom, 4)
            FilterBar(selection: $state.filter)
            GeometryReader { geometry in
                let columnWidth = max(170, (geometry.size.width - 32 - 48) / 7)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(Array(state.weeklyDays.enumerated()), id: \.element) { index, day in
                                WeeklyDayColumn(state: state, day: day)
                                    .frame(width: columnWidth, height: max(0, geometry.size.height - 20))
                                    .offset(x: columnsSettled || reduceMotion ? 0 : (state.weeklyExpansionDirection == .left ? 22 : -22))
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.24)
                                        .delay(Double(state.weeklyExpansionDirection == .left ? 6 - index : index) * 0.028), value: columnsSettled)
                                    .id(CaptureCalendar.dayString(day))
                            }
                        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
                    }
                    .onAppear {
                        columnsSettled = true
                        if let last = state.weeklyDays.last { proxy.scrollTo(CaptureCalendar.dayString(last), anchor: .trailing) }
                    }
                    .onChange(of: state.weekEndingDay) { _, _ in
                        if let last = state.weeklyDays.last { proxy.scrollTo(CaptureCalendar.dayString(last), anchor: .trailing) }
                    }
                }
            }
            HStack {
                Text("7 days")
                Spacer(minLength: 8)
                Text("Select a day to open Daily")
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 17).padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }
}

@MainActor
private struct WeeklyDayColumn: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    let day: Date

    private var captures: [Capture] { state.captures(for: day) }
    private var cards: [CaptureCardGroup] { CaptureCardGroup.cards(from: captures) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isSelected: Bool { Calendar.current.isDate(day, inSameDayAs: state.selectedDay) }

    var body: some View {
        VStack(spacing: 0) {
            Button { state.selectWeeklyDay(day) } label: {
                HStack(alignment: .center, spacing: 7) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 11, weight: .semibold)).textCase(.uppercase)
                            .foregroundStyle(isToday ? accent : Palette.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(day, format: .dateTime.day()).font(.system(size: 23, weight: .medium, design: .rounded))
                            Text(day, format: .dateTime.month(.abbreviated)).font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    if isToday {
                        Circle().fill(accent).frame(width: 5, height: 5).accessibilityHidden(true)
                    }
                    Text("\(captures.count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Palette.muted).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Palette.background.opacity(0.8), in: Capsule())
                }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open \(day.formatted(date: .complete, time: .omitted))")
                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(captures.count) captures, open Daily")
            Rectangle().fill(Palette.line).frame(height: 0.5)
            if captures.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: state.filter == .tasks ? "checkmark" : "tray")
                        .font(.system(size: 18, weight: .light)).foregroundStyle(accent.opacity(0.55))
                        .accessibilityHidden(true)
                    Text(state.filter == .all ? "No captures" : "No \(state.filter.title.lowercased())")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cards) { card in
                            if card.isImportedBatch {
                                GroupedCaptureCard(state: state, group: card, compact: true)
                            } else {
                                WeeklyCaptureCard(state: state, capture: card.primary,
                                                  taskAtTop: state.isTaskAtTop(card.primary, on: day))
                            }
                        }
                    }.padding(8)
                }.scrollIndicators(.automatic)
            }
        }.background(isSelected ? accent.opacity(0.045) : Palette.soft.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.32) : Palette.line.opacity(0.8), lineWidth: 0.75))
    }
}

@MainActor
private struct WeeklyCaptureCard: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let taskAtTop: Bool

    private var showsPreview: Bool { capture.kind != .text && capture.kind != .task }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if taskAtTop {
                Text("Created \(prettyDay(capture.captureDay, includeWeekday: false))")
                    .font(.system(size: 10)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 5) {
                CaptureControls(state: state, capture: capture)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(captureClock(capture)).font(.system(size: 12.65)).monospacedDigit().foregroundStyle(Palette.muted)
                    if capture.isTask {
                        TaskStatusButton(state: state, capture: capture)
                    } else {
                        Text(captureTypeLabel(capture.kind)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }.fixedSize(horizontal: true, vertical: false)
            }
            Button { state.openCapture(capture.id) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    if showsPreview && !capture.isMinimized {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(height: 82).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    if !capture.isMinimized, let host = captureLinkHost(capture) {
                        Text(host).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                        .font(.system(size: 16.1, weight: .medium)).lineLimit(capture.isMinimized ? 2 : 4)
                        .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    if !capture.isMinimized && !capture.previewDescription.isEmpty {
                        Text(capture.previewDescription).font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(capture.title), captured at \(captureClock(capture))")
            if !capture.isMinimized && !capture.comment.isEmpty {
                Text(capture.comment).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            HStack(spacing: 0) {
                Button { state.openCapture(capture.id, focus: "comment") } label: {
                    Image(systemName: capture.comment.isEmpty ? "text.bubble" : "text.bubble.fill")
                        .frame(width: 28, height: 26).contentShape(Rectangle())
                }.help("Comment").accessibilityLabel("Comment on \(capture.title)")
                Button { state.openCapture(capture.id, focus: "reminder") } label: {
                    Image(systemName: capture.reminderAt == nil ? "bell" : "bell.fill")
                        .frame(width: 28, height: 26).contentShape(Rectangle())
                }.help("Reminder").accessibilityLabel("Reminder for \(capture.title)")
                Spacer(minLength: 0)
                if !capture.isMinimized, let reminder = capture.reminderAt {
                    Text("\(capture.isTask && capture.isCompleted ? "Paused " : "")\(reminder.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).multilineTextAlignment(.trailing)
                }
            }.font(.system(size: 12)).foregroundStyle(accent).buttonStyle(.plain)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(taskAtTop ? accent.opacity(0.7) : Palette.line.opacity(0.7), lineWidth: taskAtTop ? 1 : 0.5))
    }
}
