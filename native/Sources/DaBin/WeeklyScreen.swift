import SwiftUI

@MainActor
struct WeeklyScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnsSettled = false

    var body: some View {
        VStack(spacing: 0) {
            if state.weeklyVisibleDays.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    BoredRobotView(isActive: state.isBoardVisible).frame(width: 56, height: 68)
                    Text(emptyTitle).font(.system(size: 14, weight: .medium))
                    Text(emptyMessage).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(emptyTitle). \(emptyMessage)")
            } else {
                GeometryReader { geometry in
                    let days = state.weeklyVisibleDays
                    let gaps = CGFloat(max(0, days.count - 1)) * 8
                    let available = max(0, geometry.size.width - 32 - gaps)
                    let columnWidth = min(zoom.value(680), max(zoom.value(170), available / CGFloat(max(1, days.count))))
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                    WeeklyDayColumn(state: state, day: day)
                                        .frame(width: columnWidth, height: max(0, geometry.size.height - 20))
                                        .workspaceZoomItem("week-day:" + CaptureCalendar.dayString(day), axis: .horizontal)
                                        .offset(x: columnsSettled || reduceMotion ? 0 : (state.weeklyExpansionDirection == .left ? 22 : -22))
                                        .animation(reduceMotion ? nil : .easeOut(duration: 0.24)
                                            .delay(Double(state.weeklyExpansionDirection == .left ? days.count - 1 - index : index) * 0.028), value: columnsSettled)
                                        .id(CaptureCalendar.dayString(day))
                                }
                            }
                            .frame(minWidth: max(0, geometry.size.width - 32), alignment: .center)
                            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
                        }
                        .onAppear {
                            columnsSettled = true
                            scrollToLatestVisibleDay(proxy)
                        }
                        .onChange(of: state.weeklyDays) { _, _ in scrollToLatestVisibleDay(proxy) }
                        .onChange(of: state.weeklyVisibleDays) { _, _ in scrollToLatestVisibleDay(proxy) }
                        .onChange(of: state.filter) { _, _ in scrollToLatestVisibleDay(proxy) }
                    }
                }
            }
            HStack {
                Text(footerCount)
                Spacer(minLength: 8)
                Text(state.weeklyVisibleDays.isEmpty ? "Choose other dates" : "Select a day to open Daily")
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 17).padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }

    private var emptyTitle: String {
        "No captures or tasks on these dates"
    }

    private var emptyMessage: String {
        "Choose up to 7 dates. Days without activity stay hidden."
    }

    private var footerCount: String {
        let count = state.weeklyVisibleDays.count
        return "\(count) of \(state.weeklyDays.count) \(state.weeklyDays.count == 1 ? "day" : "days") with activity"
    }

    private func scrollToLatestVisibleDay(_ proxy: ScrollViewProxy) {
        guard let last = state.weeklyVisibleDays.last else { return }
        proxy.scrollTo(CaptureCalendar.dayString(last), anchor: .trailing)
    }
}

@MainActor
private struct WeeklyDayColumn: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    let day: Date

    private var allCaptures: [Capture] { state.allCaptures(for: day) }
    private var captures: [Capture] { allCaptures.filter { state.filter.includes($0) } }
    private var cards: [CaptureFeedCard] {
        HourlyCaptureFeed.cards(from: allCaptures, filter: state.filter)
    }
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
            }.buttonStyle(.plain).buddyHelp("Open \(day.formatted(date: .complete, time: .omitted))")
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
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(cards) { card in
                            switch card {
                            case .capture(let captureCard):
                                if captureCard.isImportedBatch {
                                    GroupedCaptureCard(state: state, group: captureCard, compact: true)
                                        .workspaceZoomItem("capture:" + captureCard.primary.id.uuidString)
                                        .id("capture:" + captureCard.primary.id.uuidString)
                                } else {
                                    WeeklyCaptureCard(state: state, capture: captureCard.primary,
                                                      taskAtTop: state.isTaskAtTop(captureCard.primary, on: day))
                                        .id("capture:" + captureCard.primary.id.uuidString)
                                }
                            case .automaticHour(let group):
                                HourlyCaptureCard(state: state, group: group, compact: true)
                                    .workspaceZoomItem("capture:" + (group.captures.first?.id.uuidString ?? ""))
                                    .id("capture:" + (group.captures.first?.id.uuidString ?? ""))
                            }
                        }
                    }.padding(8)
                }.scrollIndicators(.automatic)
                    .background {
                        WorkspaceScrollHistory(anchor: state.weeklyColumnViewports[CaptureCalendar.dayString(day)],
                            contextID: "weekly-" + CaptureCalendar.dayString(day),
                            onAnchor: { state.weeklyColumnViewports[CaptureCalendar.dayString(day)] = $0 })
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .onAppear {
                        if let anchor = state.weeklyColumnViewports[CaptureCalendar.dayString(day)] { proxy.scrollTo(anchor.itemID, anchor: .top) }
                    }
                    .onChange(of: state.navigationRestorationRevision) { _, _ in
                        if let anchor = state.weeklyColumnViewports[CaptureCalendar.dayString(day)] { proxy.scrollTo(anchor.itemID, anchor: .top) }
                    }
                }
            }
        }.background(isSelected ? accent.opacity(0.045) : Palette.soft.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.32) : Palette.line.opacity(0.8), lineWidth: 0.75))
    }
}

@MainActor
private struct WeeklyCaptureCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let taskAtTop: Bool

    private var showsPreview: Bool { !capture.isTask && capture.kind != .text && capture.kind != .task }
    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptureProjectPickerButton(state: state, capture: capture)
                .frame(maxWidth: .infinity, alignment: .leading)
            CaptureReceiptView(capture: capture, category: captureTypeLabel(capture.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
            CaptureTaskPriorityTag(capture: capture)
            HStack(spacing: 3) {
                Spacer(minLength: 0)
                CaptureCopyButton(state: state, captures: [capture], compact: true)
                CaptureTrashButton(state: state, capture: capture)
                CaptureControls(state: state, capture: capture)
            }
            if !capture.isMinimized { CaptureTrailView(state: state, capture: capture) }
            HStack(alignment: .top, spacing: 5) {
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                Button { state.openCapture(capture.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        if showsPreview && !capture.isMinimized {
                            CaptureThumbnail(store: state.store, capture: capture)
                                .frame(height: zoom.value(104)).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if capture.isTask {
                            Text(capture.isCompleted ? "COMPLETED" : "TASK")
                                .font(.system(size: zoom.fontSize(10), weight: .medium)).tracking(0.5).foregroundStyle(Palette.muted)
                        }
                        if !capture.isMinimized, let host = captureLinkHost(capture) {
                            Text(host).font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                            .font(.system(size: zoom.fontSize(16), weight: .semibold)).lineLimit(capture.isMinimized ? 2 : 4)
                            .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                            .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        if !capture.isMinimized, !capture.isTask, !capture.previewDescription.isEmpty {
                            Text(capture.previewDescription).font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open \(capture.title), captured at \(captureClock(capture))")
                    .captureDragSource(state: state, capture: capture)
            }
            if !capture.isMinimized {
                if !capture.comment.isEmpty {
                    Text(capture.comment).font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted).lineLimit(2)
                        .accessibilityIdentifier("capture-comment-\(capture.id.uuidString)")
                        .readableTextDragSource(text: capture.comment, label: "Comment for \(capture.title)", state: state)
                }
                if capture.isTask { TaskFocusControls(state: state, capture: capture) }
                CaptureConversionUndo(state: state, capture: capture)
                HStack(spacing: 0) {
                    if !capture.isTask {
                        CaptureTaskConversionButton(state: state, capture: capture)
                    }
                    BuddyIconButton(symbol: capture.comment.isEmpty ? "text.bubble" : "text.bubble.fill", title: "Comment on \(capture.title)") {
                        state.openCapture(capture.id, focus: "comment")
                    }
                    BuddyIconButton(symbol: capture.reminderAt == nil ? "bell" : "bell.fill", title: "Reminder for \(capture.title)") {
                        state.openCapture(capture.id, focus: "reminder")
                    }
                    Spacer(minLength: 0)
                }.padding(.top, 6).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.7) }
                if let reminder = capture.reminderAt {
                    Label("\(capture.isTask && capture.isCompleted ? "Paused · " : "")\(reminder.formatted(.dateTime.month(.abbreviated).day().hour().minute()))", systemImage: "bell")
                        .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(zoom.value(10)).workspaceZoomItem("capture:" + capture.id.uuidString).frame(maxWidth: .infinity, alignment: .leading)
            .projectCardBackground(workspace: state.workspace, projectName: projectName)
            .projectCardFrame(workspace: state.workspace, projectName: projectName, activeProject: nil,
                              fallbackColor: taskAtTop ? accent.opacity(0.55) : Palette.line)
            .contextMenu {
                CaptureTaskConversionMenu(state: state, capture: capture)
                Button(capture.isMinimized ? "Expand capture" : "Minimize capture", systemImage: capture.isMinimized ? "chevron.down" : "chevron.up") { state.toggleMinimized(capture) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: capture.isTask)
    }
}
