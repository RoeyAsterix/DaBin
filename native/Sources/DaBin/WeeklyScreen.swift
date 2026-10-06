import SwiftUI

/// A week is an overview: distribute the available width across populated
/// dates instead of imposing a zoom-scaled minimum that hides later columns.
struct WeeklyBoardLayout {
    let horizontalPadding: CGFloat
    let gap: CGFloat
    let columnWidth: CGFloat
    let contentWidth: CGFloat

    init(viewportWidth: CGFloat, dayCount: Int) {
        let width = viewportWidth.isFinite ? max(0, viewportWidth) : 0
        let count = max(1, dayCount)
        horizontalPadding = width < 1200 ? 8 : 16
        gap = width < 1200 ? 6 : 8
        // Manual Restore/resize can make the board much narrower than full
        // view. Keep its controls usable with a horizontal overflow fallback;
        // normal full view (976pt+) fits all seven columns without scrolling.
        columnWidth = min(680, max(132, (width - horizontalPadding * 2 - gap * CGFloat(count - 1)) / CGFloat(count)))
        contentWidth = max(width, columnWidth * CGFloat(count) + gap * CGFloat(count - 1) + horizontalPadding * 2)
    }
}

@MainActor
struct WeeklyScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnsSettled = false

    var body: some View {
        let days = state.weeklyVisibleDays
        VStack(spacing: 0) {
            if days.isEmpty {
                EmptyMessage(symbol: "calendar",
                    title: state.filter == .all ? "No captures in these days" : "No \(state.filter.title.lowercased()) in these days",
                    message: state.filter == .all ? "Choose other dates to see your captures." : "Try another filter or choose other dates.")
                    .accessibilityIdentifier("weekly-empty-state")
            } else {
            GeometryReader { geometry in
                let layout = WeeklyBoardLayout(viewportWidth: geometry.size.width, dayCount: days.count)
                ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: layout.gap) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        WeeklyDayColumn(state: state, day: day, columnWidth: layout.columnWidth)
                            .frame(width: layout.columnWidth, height: max(0, geometry.size.height - 16))
                            .opacity(columnsSettled || reduceMotion ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18)
                                .delay(Double(state.weeklyExpansionDirection == .left ? days.count - 1 - index : index) * 0.02), value: columnsSettled)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding).padding(.vertical, 8)
                .frame(width: layout.contentWidth, alignment: .center)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("weekly-columns")
                .onAppear { columnsSettled = true }
                }.scrollIndicators(.automatic)
            }
            }
            HStack {
                Text("\(days.count) of \(state.weeklyDays.count) days shown")
                Spacer(minLength: 8)
                Text(days.isEmpty ? "Choose dates in the calendar" : "Select a day to open Daily")
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
    let columnWidth: CGFloat

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
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).buddyHelp("Open \(day.formatted(date: .complete, time: .omitted))")
                .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(captures.count) captures, open Daily")
                .accessibilityIdentifier("weekly-day-" + CaptureCalendar.dayString(day))
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
                                    WeeklyCollectionCard(state: state, captures: captureCard.captures,
                                        title: "\(captureCard.captures.count) captures", subtitle: captureClock(captureCard.primary),
                                        isExpanded: !captureCard.isMinimized, isBatch: true, day: day,
                                        cardWidth: columnWidth - 12,
                                        toggle: { state.toggleMinimized(captureCard.captures) })
                                        .workspaceZoomItem("capture:" + captureCard.primary.id.uuidString)
                                        .id("capture:" + captureCard.primary.id.uuidString)
                                } else {
                                    WeeklyCaptureCard(state: state, capture: captureCard.primary,
                                                      taskAtTop: state.isTaskAtTop(captureCard.primary, on: day), cardWidth: columnWidth - 12)
                                        .id("capture:" + captureCard.primary.id.uuidString)
                                }
                            case .automaticHour(let group):
                                WeeklyCollectionCard(state: state, captures: group.captures,
                                    title: group.captureCountLabel, subtitle: group.id.rangeLabel + " · " + group.actionCountLabel,
                                    isExpanded: state.isHourlyGroupExpanded(group.id), isBatch: false, day: day, actions: group.actions,
                                    cardWidth: columnWidth - 12, toggle: { state.toggleHourlyGroup(group.id) })
                                    .workspaceZoomItem("capture:" + (group.captures.first?.id.uuidString ?? ""))
                                    .background {
                                        Color.clear.id("capture:" + (group.captures.first?.id.uuidString ?? ""))
                                            .allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                    // New arrivals update the history anchor without replacing a pending confirmation.
                                    .id(card.id)
                            }
                        }
                    }.padding(6)
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

/// Collections use the same narrow cards when opened, rather than embedding a
/// full Daily row with fixed-width toolbars inside one seventh of the screen.
@MainActor
private struct WeeklyCollectionCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    let captures: [Capture]
    let title: String
    let subtitle: String
    let isExpanded: Bool
    let isBatch: Bool
    let day: Date
    var actions: [AutomaticCaptureAction]? = nil
    let cardWidth: CGFloat
    let toggle: () -> Void
    @State private var confirmsRemoval = false
    @State private var removalCaptures: [Capture] = []

    private var hourIdentity: String {
        guard let capture = captures.first else { return "empty" }
        let key = AutomaticHourKey(capture: capture)
        return "\(key.captureDay)-\(key.hour)-\(key.utcOffsetSeconds)"
    }
    private var removalUnavailable: Bool { state.removingCaptureID != nil || state.isArchiveOperationRunning }

    private var projects: Set<String?> {
        Set(captures.map { ExplorerQuery.project(of: $0, in: state.store.captures) })
    }
    private var hasMixedProjects: Bool { projects.count > 1 }
    private var resolvedProject: String? { hasMixedProjects ? nil : (projects.first ?? nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 5) {
                    if !isExpanded {
                        CollectionPreviewMosaic(store: state.store, captures: captures, compact: true,
                                                height: min(140, max(72, cardWidth * 0.7)))
                    }
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? (isBatch ? "Collapse batch items" : "Collapse actions") : (isBatch ? "Expand batch items" : "Expand actions, " + subtitle))
                .accessibilityIdentifier(isBatch ? "collection-batch-summary" : "collection-hour-summary")
                .captureDragSource(state: state, captures: captures, label: title)
            HStack(spacing: 0) {
                CaptureCopyButton(state: state, captures: captures, compact: true)
                Spacer(minLength: 0)
                if isBatch {
                    BuddyIconButton(symbol: "trash", title: "Move batch to Recently Deleted", action: requestRemoval)
                        .disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning)
                        .accessibilityIdentifier("capture-trash-batch-" + (captures.first?.id.uuidString ?? ""))
                } else {
                    Menu {
                        Button("Delete \(captures.count) visible \(captures.count == 1 ? "capture" : "captures")…", systemImage: "trash", role: .destructive, action: requestRemoval)
                            .disabled(removalUnavailable)
                            .accessibilityIdentifier("capture-delete-hour-\(hourIdentity)")
                    } label: {
                        Text("More").font(.system(size: zoom.fontSize(11)))
                            .padding(.horizontal, 6).frame(minWidth: 32, minHeight: 32).contentShape(Rectangle())
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("More actions for \(title), \(subtitle)")
                        .accessibilityIdentifier("capture-more-hour-\(hourIdentity)")
                }
                BuddyIconButton(symbol: isExpanded ? "minus" : "chevron.down",
                                title: isExpanded ? (isBatch ? "Collapse batch items" : "Collapse actions") : (isBatch ? "Expand batch items" : "Expand actions"), action: toggle)
            }
            if isExpanded {
                if let actions {
                    ForEach(actions) { action in
                        if action.captures.count > 1 {
                            HStack(spacing: 2) {
                                Text(captureClock(action.primary)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Spacer(minLength: 0)
                                CaptureCopyButton(state: state, captures: action.captures, compact: true)
                            }
                        }
                        ForEach(action.cards) { card in
                            if card.isImportedBatch {
                                Text("\(card.captures.count) captures").font(.system(size: 11, weight: .medium))
                                ForEach(card.captures) { capture in childCard(capture) }
                            } else { childCard(card.primary) }
                        }
                    }
                } else {
                    ForEach(captures) { capture in childCard(capture) }
                }
            } else if isBatch, let primary = captures.first {
                ProjectChipLabel(name: hasMixedProjects ? "Multiple projects" : resolvedProject,
                                 colorHex: resolvedProject.map { state.workspace.projectColorHex(for: $0) ?? WorkspaceStore.defaultProjectColorHex })
                if !primary.comment.isEmpty {
                    Text(primary.comment).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                        .accessibilityIdentifier("capture-comment-" + primary.id.uuidString)
                        .readableTextDragSource(text: primary.comment, label: "Comment for " + primary.title, state: state)
                }
                HStack(spacing: 0) {
                    BuddyIconButton(symbol: primary.comment.isEmpty ? "text.bubble" : "text.bubble.fill", title: "Comment on " + primary.title) { state.openCapture(primary.id, focus: "comment") }
                    BuddyIconButton(symbol: primary.reminderAt == nil ? "bell" : "bell.fill", title: "Reminder for " + primary.title) { state.openCapture(primary.id, focus: "reminder") }
                }
            }
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.7))
            .alert("Delete \(removalCaptures.count) visible \(removalCaptures.count == 1 ? "capture" : "captures") from this \(isBatch ? "batch" : "hour")?", isPresented: $confirmsRemoval) {
                Button("Cancel", role: .cancel) { removalCaptures = [] }
                Button("Delete \(removalCaptures.count) visible \(removalCaptures.count == 1 ? "capture" : "captures")", role: .destructive) {
                    let selected = removalCaptures
                    removalCaptures = []
                    Task { await state.removeCaptures(selected) }
                }.disabled(removalUnavailable || removalCaptures.isEmpty)
            } message: {
                Text("Only these captures will move to Recently Deleted, where you can restore them. Hidden captures, other tasks and newly saved captures are kept. Files at their original locations are kept.")
            }
    }
    private func requestRemoval() {
        guard !removalUnavailable else { return }
        let liveIDs = Set(state.store.captures.map(\.id))
        removalCaptures = captures.filter { liveIDs.contains($0.id) }
        guard !removalCaptures.isEmpty else { return }
        confirmsRemoval = true
    }
    private func childCard(_ capture: Capture) -> some View {
        WeeklyCaptureCard(state: state, capture: capture,
            taskAtTop: state.isTaskAtTop(capture, on: day), cardWidth: cardWidth - 12)
    }

}

@MainActor
private struct WeeklyCaptureCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let taskAtTop: Bool
    let cardWidth: CGFloat
    @State private var showsFocus = false

    private var showsPreview: Bool { !capture.isTask && capture.kind != .text && capture.kind != .task }
    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CaptureProjectPickerButton(state: state, capture: capture)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(captureClock(capture)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                    if !capture.isTask {
                        Text(captureTypeLabel(capture.kind)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 0)
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
            }
            CaptureTaskPriorityTag(capture: capture)
            Button { state.openCapture(capture.id) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    if showsPreview && !capture.isMinimized {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(height: min(180, max(72, cardWidth * 0.72)))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    if !capture.isMinimized, let host = captureLinkHost(capture) {
                        Text(host).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                        .font(.system(size: zoom.fontSize(cardWidth < 175 ? 13 : 14), weight: .semibold))
                        .lineLimit(capture.isMinimized ? 2 : 4)
                        .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                        .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    if !capture.isMinimized, !capture.isTask, !capture.previewDescription.isEmpty {
                        Text(capture.previewDescription).font(.system(size: zoom.fontSize(11)))
                            .foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(capture.title), captured at \(captureClock(capture))")
                .captureDragSource(state: state, capture: capture)
            if !capture.isMinimized {
                CaptureTrailView(state: state, capture: capture)
                if !capture.comment.isEmpty {
                    Text(capture.comment).font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(2)
                        .accessibilityIdentifier("capture-comment-\(capture.id.uuidString)")
                        .readableTextDragSource(text: capture.comment, label: "Comment for \(capture.title)", state: state)
                }
                HStack(spacing: 0) {
                    BuddyIconButton(symbol: capture.comment.isEmpty ? "text.bubble" : "text.bubble.fill", title: "Comment on \(capture.title)") {
                        state.openCapture(capture.id, focus: "comment")
                    }
                    BuddyIconButton(symbol: capture.reminderAt == nil ? "bell" : "bell.fill", title: "Reminder for \(capture.title)") {
                        state.openCapture(capture.id, focus: "reminder")
                    }
                    if capture.isTask {
                        BuddyIconButton(symbol: "timer", title: "Focus and schedule task") { showsFocus = true }
                            .popover(isPresented: $showsFocus, arrowEdge: .bottom) {
                                TaskFocusControls(state: state, capture: capture, compact: false)
                                    .padding(16).frame(width: 280).hoverTooltips()
                            }
                    }
                }
                if let reminder = capture.reminderAt {
                    Text("\(capture.isTask && capture.isCompleted ? "Paused · " : "")\(reminder.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                CaptureConversionUndo(state: state, capture: capture)
            }
            HStack(spacing: 0) {
                CaptureCopyButton(state: state, captures: [capture], compact: true)
                Spacer(minLength: 0)
                CaptureTrashButton(state: state, capture: capture)
                CaptureControls(state: state, capture: capture)
            }.padding(.top, 3).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.5) }
        }.padding(6).workspaceZoomItem("capture:" + capture.id.uuidString)
            .frame(maxWidth: .infinity, alignment: .leading)
            .projectCardBackground(workspace: state.workspace, projectName: projectName)
            .projectCardFrame(workspace: state.workspace, projectName: projectName, activeProject: nil,
                              fallbackColor: taskAtTop ? accent.opacity(0.55) : Palette.line)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("weekly-card-" + capture.id.uuidString)
            .contextMenu {
                CaptureTaskConversionMenu(state: state, capture: capture)
                Button(capture.isMinimized ? "Expand capture" : "Minimize capture", systemImage: capture.isMinimized ? "chevron.down" : "chevron.up") { state.toggleMinimized(capture) }
            }
    }
}
