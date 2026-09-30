import SwiftUI

@MainActor
struct BoardView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var state: AppState
    @StateObject private var theme: ThemeSettings
    @StateObject private var dayExportController: DayExportActionController
    @State private var showCalendar = false
    @FocusState private var searchFocused: Bool

    init(state: AppState, theme: ThemeSettings? = nil,
         dayExportController: DayExportActionController? = nil,
         tooltipController: TimelineTooltipController? = nil) {
        self.state = state
        _theme = StateObject(wrappedValue: theme ?? ThemeSettings())
        _dayExportController = StateObject(wrappedValue: dayExportController ?? .live())
    }

    private var accent: Color { theme.accent }
    private var isTimeline: Bool { state.route == .daily || state.route == .weekly }
    private var isPrimary: Bool { isTimeline || state.route == .library || state.route == .reminders }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = state.store.error.map({ AppStatusMessage(text: $0, severity: .error) }) ?? state.status {
                statusBanner(message)
            }
            if state.canUndoRemoval { undoBanner }
            routeContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            BoardCaptureStatus(state: state, service: state.autoCapture, settings: state.autoCapture.settings)
        }
        .foregroundStyle(Palette.foreground).tint(accent).environment(\.daBinAccent, accent)
        .environment(\.daBinTooltipsEnabled, theme.showTooltips)
        .background(Palette.background.opacity(ThemeSettings.effectiveBoardOpacity(
            preferred: theme.boardOpacity, reduceTransparency: reduceTransparency)))
        .preferredColorScheme(theme.darkModeEnabled ? .dark : .light)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .overlay {
            if state.route == .daily && state.isDailyDropTargeted {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(accent.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(accent, lineWidth: 2))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .alert("Move this capture to Recently Deleted?", isPresented: Binding(
            get: { state.pendingRemoval != nil }, set: { if !$0 { state.pendingRemoval = nil } }
        ), presenting: state.pendingRemoval) { capture in
            Button("Cancel", role: .cancel) { state.pendingRemoval = nil }
            Button("Move to Recently Deleted", role: .destructive) {
                state.pendingRemoval = nil
                Task { await state.removeCapture(capture) }
            }
        } message: { _ in
            Text("You can restore it from Recently Deleted. Files at their original locations are kept.")
        }
        .onExitCommand {
            if searchFocused { searchFocused = false } else { state.onDismiss?() }
        }
        .onChange(of: state.route) { _, route in searchFocused = route == .search }
        .onChange(of: state.globalSearchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: dayExportController.feedback) { _, feedback in
            guard let feedback else { return }
            if case .failed = feedback { state.reportFailure(feedback.message) }
            else { state.status = AppStatusMessage(text: feedback.message, severity: .success) }
        }
        .onChange(of: state.status) { _, message in
            if let message { AccessibilityAnnouncement.post(message.text) }
        }
        .background {
            Group {
                Button("Search all captures") { state.performSearchCommand(); searchFocused = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Open Today") { state.openDaily() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }.frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var routeContent: some View {
        switch state.route {
        case .daily: DailyScreen(state: state)
        case .weekly: WeeklyScreen(state: state)
        case .library: LibraryScreen(state: state)
        case .search: SearchScreen(state: state)
        case .newTask: NewTaskScreen(state: state, draft: state.newTaskDraft)
        case .newNote: NewNoteScreen(state: state)
        case .detail:
            if let capture = state.selectedCapture, let draft = state.selectedDraft {
                DetailScreen(state: state, capture: capture, draft: draft).id(capture.id)
            } else {
                EmptyMessage(symbol: "tray", title: "Capture unavailable", message: "Open Library to browse your saved captures.")
            }
        case .reminders: RemindersScreen(state: state)
        case .settings: SettingsScreen(state: state, theme: theme)
        case .trash: TrashScreen(state: state)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                DaBinLogo(variant: .compact).frame(width: 68, height: 28, alignment: .leading)
                    .overlay { WindowDragHandle(onDragStarted: { state.onBoardDragStarted?() }).accessibilityHidden(true) }
                AutoCaptureHeaderButton(service: state.autoCapture, weekly: state.route == .weekly,
                    statusText: state.autoCapture.overallStatusText, isVisible: state.isBoardVisible) { state.toggleAutoCaptureFromHeader() }
                Spacer(minLength: 0)
                addMenu
                BuddyIconButton(symbol: "gearshape", title: "Settings") { state.showSettings() }
                    .accessibilityIdentifier("board-settings")
                moreMenu
                BuddyIconButton(symbol: "arrow.up.left.and.arrow.down.right", title: "Expand or restore window") {
                    state.onToggleExpandedWindow?()
                }.accessibilityIdentifier("window-expand")
                SmallIcon(symbol: "xmark", label: "Hide DaBin", size: 28) { state.onDismiss?() }
                    .accessibilityIdentifier("window-close")
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
                TextField("Search all captures", text: Binding(
                    get: { state.route == .search ? state.query : "" },
                    set: { state.updateGlobalSearch($0) }))
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityLabel("Search all captures across all dates").accessibilityIdentifier("global-search")
                    .onSubmit { state.performSearchCommand() }
                if state.route == .search && !state.query.isEmpty {
                    Button { state.updateGlobalSearch("") } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .buddyHelp("Clear search").accessibilityLabel("Clear search")
                }
            }.padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
            HStack(spacing: 4) {
                navigationButton("Today", symbol: "sun.max", selected: isTimeline) { state.openDaily() }
                navigationButton("Library", symbol: "square.stack", selected: state.route == .library) { state.openLibrary() }
                navigationButton("Follow-ups", symbol: "checkmark.circle", selected: state.route == .reminders) { state.showReminders() }
            }.accessibilityElement(children: .contain).accessibilityLabel("Main views")
            if isTimeline { timelineControls }
            else if !isPrimary {
                HStack(spacing: 8) {
                    Button { state.back() } label: { Label("Back", systemImage: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(accent)
                    Text(routeTitle).font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }.font(.system(size: 12))
            }
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func navigationButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: selected ? .semibold : .medium))
                .lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(selected ? accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? accent : Palette.muted)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("primary-\(title.lowercased())")
    }

    private var addMenu: some View {
        Menu {
            Button("Paste clipboard", systemImage: "doc.on.clipboard") { state.pasteClipboard() }
            Button("New note", systemImage: "square.and.pencil") { state.openNewNote() }
            Button("Import files…", systemImage: "folder.badge.plus") { state.importFiles() }
            Divider()
            Button("New task", systemImage: "checkmark.circle") { state.openNewTask() }
        } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).frame(width: 28, height: 32) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().buddyHelp("Add capture")
        .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Add capture").accessibilityIdentifier("timeline-action-add").disabled(state.isImporting)
    }

    private var moreMenu: some View {
        Menu {
            Menu {
                Button("Copy selected day", systemImage: "doc.on.doc") { dayExportController.copy(dayDocument) }.disabled(dayDocument.isEmpty)
                Button("Export selected day…", systemImage: "doc.badge.arrow.up") { reportExport(dayExportController.save(dayDocument)) }.disabled(dayDocument.isEmpty)
                Button("Copy selected week", systemImage: "doc.on.doc.fill") { dayExportController.copy(weekDocument) }.disabled(weekDocument.isEmpty)
                Button("Export selected week…", systemImage: "square.and.arrow.up") { reportExport(dayExportController.save(weekDocument)) }.disabled(weekDocument.isEmpty)
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            Divider()
            Button("Recently Deleted", systemImage: "trash") { state.showTrash() }
            Button("Back up archive…", systemImage: "externaldrive") { state.exportArchiveBackup() }.disabled(state.isArchiveOperationRunning)
            Button("Restore archive backup…", systemImage: "arrow.counterclockwise") { state.restoreArchiveBackup() }.disabled(state.isArchiveOperationRunning)
        } label: { Image(systemName: "ellipsis.circle").font(.system(size: 16, weight: .semibold)).frame(width: 28, height: 32) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(accent).buddyHelp("More options")
        .accessibilityLabel("More options").accessibilityIdentifier("board-more")
    }

    private var dayDocument: DayExportDocument { DayExportDocument.make(captures: state.store.captures, selectedDate: state.selectedDay) }
    private var weekDocument: WeekExportDocument { WeekExportDocument.make(captures: state.store.captures, weekEndingDate: state.weekEndingDay) }
    private func reportExport(_ result: DayExportSaveOutcome) {
        if case .failed(let message) = result { state.reportFailure(message) }
    }

    private var timelineControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                SmallIcon(symbol: "chevron.left", label: state.route == .weekly ? "Previous week" : "Previous day", size: 26) { moveTimeline(-1) }
                Button { showCalendar.toggle() } label: {
                    Label(timelineDateLabel, systemImage: "calendar").font(.system(size: 12, weight: .medium))
                        .lineLimit(1).frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("Choose date, \(timelineDateLabel)").accessibilityIdentifier("timeline-date")
                    .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                        DatePicker(state.route == .weekly ? "Week ending" : "Day", selection: Binding(
                            get: { state.route == .weekly ? state.weekEndingDay : state.selectedDay },
                            set: { date in
                                if state.route == .weekly { state.setWeekEndingDay(date) } else { state.selectWeeklyDay(date) }
                                showCalendar = false
                            }), in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical).padding(12).frame(width: 280)
                    }
                SmallIcon(symbol: "chevron.right", label: state.route == .weekly ? "Next week" : "Next day", size: 26) { moveTimeline(1) }
                    .disabled(Calendar.current.isDateInToday(state.route == .weekly ? state.weekEndingDay : state.selectedDay))
                ForEach([BoardTimelineMode.daily, .weekly], id: \.self) { mode in
                    BuddyIconButton(symbol: mode == .daily ? "1.calendar" : "7.calendar",
                        title: mode == .daily ? "Daily view" : "Weekly view",
                        isActive: state.timelineMode == mode) { state.selectTimelineMode(mode) }
                        .accessibilityIdentifier(mode == .daily ? "timeline-mode-daily" : "timeline-mode-weekly")
                }
                if !Calendar.current.isDateInToday(state.route == .weekly ? state.weekEndingDay : state.selectedDay) {
                    Button {
                        if state.route == .weekly { state.showCurrentWeek() } else { state.openDaily() }
                    } label: { Image(systemName: "arrow.uturn.backward").frame(width: 22, height: 28) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                        .accessibilityLabel("Return to today").buddyHelp("Return to today")
                }
            }
            CaptureFilterStrip(selection: $state.filter)
        }
    }

    private var timelineDateLabel: String {
        if state.route == .weekly, let first = state.weeklyDays.first {
            return "\(first.formatted(.dateTime.month(.abbreviated).day()))–\(state.weekEndingDay.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return state.selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    private func moveTimeline(_ amount: Int) {
        if state.route == .weekly { state.moveWeek(amount) } else { state.moveDay(amount) }
    }
    private var routeTitle: String {
        switch state.route {
        case .search: return "All captures"
        case .newTask: return "New task"
        case .newNote: return "New note"
        case .detail: return state.selectedCapture?.isTask == true ? "Task" : "Capture"
        case .settings: return "Settings"
        case .trash: return "Recently Deleted"
        default: return "DaBin"
        }
    }
    private var undoBanner: some View {
        HStack {
            Text("Moved to Recently Deleted").font(.system(size: 12))
            Spacer(minLength: 4)
            Button("Undo") { Task { await state.undoLastRemoval() } }.buttonStyle(.plain).foregroundStyle(accent)
        }.padding(9).background(Palette.soft).accessibilityElement(children: .contain)
    }
    private func statusBanner(_ message: AppStatusMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.symbol).foregroundStyle(message.severity == .error ? Palette.task : accent)
            Text(message.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { state.status = nil; state.store.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).buddyHelp("Dismiss message").accessibilityLabel("Dismiss message")
        }.padding(10).background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 14).padding(.vertical, 6)
    }
}

@MainActor
struct CaptureFilterMenu: View {
    @Binding var selection: CaptureFilter
    var body: some View {
        Menu {
            Picker("Capture type", selection: $selection) {
                ForEach(CaptureFilter.allCases) { filter in Label(filter.title, systemImage: filter.buddySymbol).tag(filter) }
            }
        } label: {
            Label(selection == .all ? "Filters" : selection.title, systemImage: "line.3.horizontal.decrease").font(.system(size: 11))
        }.menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Filters, \(selection == .all ? "all capture types" : selection.title)")
    }
}

@MainActor
private struct BoardCaptureStatus: View {
    @ObservedObject var state: AppState
    @ObservedObject var service: AutoCaptureService
    @ObservedObject var settings: AutoCaptureSettings
    @Environment(\.daBinAccent) private var accent
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: settings.isPaused || !settings.isEnabled ? "pause.circle" : "circle.fill")
                .font(.system(size: 8)).foregroundStyle(accent).accessibilityHidden(true)
            Text(service.overallStatusText).font(.system(size: 11)).foregroundStyle(Palette.muted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if settings.isEnabled {
                Button(settings.isPaused ? "Resume" : "Pause") { state.autoCapture.setPaused(!settings.isPaused) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
            } else {
                Button("Set up") { state.showSettings() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
            }
        }.padding(.horizontal, 16).padding(.vertical, 9)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }.accessibilityElement(children: .contain)
    }
}
