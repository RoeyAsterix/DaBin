import SwiftUI

@MainActor
struct BoardView: View {
    static let searchPlaceholder = "Search everything saved in DaBin"
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject var state: AppState
    @StateObject private var theme: ThemeSettings
    @StateObject private var dayExportController: DayExportActionController
    @StateObject private var tooltipController: TimelineTooltipController
    @State private var showCalendar = false
    @FocusState private var searchFocused: Bool

    init(state: AppState, theme: ThemeSettings? = nil,
         dayExportController: DayExportActionController? = nil,
         tooltipController: TimelineTooltipController? = nil) {
        self.state = state
        _theme = StateObject(wrappedValue: theme ?? ThemeSettings())
        _dayExportController = StateObject(wrappedValue: dayExportController ?? .live())
        _tooltipController = StateObject(wrappedValue: tooltipController ?? TimelineTooltipController())
    }

    private var accent: Color { theme.accent }
    private var isTimeline: Bool { state.route == .daily || state.route == .weekly }
    private var isPrimary: Bool { isTimeline || state.route == .inbox || state.route == .library || state.route == .reminders }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = state.notificationMessage {
                statusBanner(message)
            }
            if state.canUndoRemoval { undoBanner }
            if let error = state.draftPersistenceError {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.task).padding(8)
            }
            routeContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            BoardCaptureStatus(state: state, service: state.autoCapture, settings: state.autoCapture.settings)
        }
        .foregroundStyle(Palette.foreground).tint(accent).environment(\.daBinAccent, accent)
        .environment(\.daBinTooltipsEnabled, theme.showTooltips)
        .environment(\.timelineTooltipController, tooltipController)
        .environment(\.hoverTooltipActiveID, tooltipController.visible?.id)
        .background(Palette.background.opacity(ThemeSettings.effectiveBoardOpacity(
            preferred: theme.boardOpacity, reduceTransparency: reduceTransparency || colorSchemeContrast == .increased)))
        .preferredColorScheme(theme.darkModeEnabled ? .dark : .light)
        .clipShape(BoardWindowChrome.shape)
        .overlay(BoardWindowChrome.shape.strokeBorder(Palette.line, lineWidth: 1))
        .overlayPreferenceValue(HoverTooltipAnchorKey.self) { anchors in
            HoverTooltipOverlay(controller: tooltipController, anchors: anchors, isEnabled: theme.showTooltips)
        }
        .overlay {
            if state.isDailyDropTargeted && (state.route == .daily || state.route == .inbox
                || (state.route == .detail && state.selectedCapture?.isTask == true)) {
                BoardWindowChrome.shape.fill(accent.opacity(0.06))
                    .overlay(BoardWindowChrome.shape.strokeBorder(accent, lineWidth: 2))
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
        .onChange(of: state.route) { _, route in
            tooltipController.dismiss()
            searchFocused = route == .search
        }
        .onChange(of: theme.showTooltips, initial: true) { _, enabled in tooltipController.setEnabled(enabled) }
        .onAppear { tooltipController.setPresentationActive(true) }
        .onChange(of: state.isBoardVisible) { _, visible in tooltipController.setPresentationActive(visible) }
        .onDisappear { tooltipController.setPresentationActive(false) }
        .onChange(of: dayExportController.feedbackRevision) { _, _ in
            guard let feedback = dayExportController.visibleFeedback else { return }
            if case .failed = feedback { state.reportFailure(feedback.message) }
            else { state.status = AppStatusMessage(text: feedback.message, severity: .success) }
        }
        .onChange(of: state.notifications.revision) { _, _ in
            if let message = state.notificationMessage { AccessibilityAnnouncement.post(message.text) }
        }
        .background {
            Group {
                Button("Search captures") { state.performSearchCommand(); searchFocused = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Open Today") { state.showReminders() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }.frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var routeContent: some View {
        switch state.route {
        case .inbox: InboxScreen(state: state)
        case .daily: DailyScreen(state: state)
        case .weekly: WeeklyScreen(state: state)
        case .library: LibraryScreen(state: state)
        case .search: SearchScreen(state: state)
        case .searchNote: ScratchpadView(state: state, workspace: state.workspace, noteContext: state.selectedSearchNote)
        case .newTask: NewTaskScreen(state: state, draft: state.newTaskDraft)
        case .newNote: NewNoteScreen(state: state)
        case .detail:
            if let capture = state.selectedCapture, let draft = state.selectedDraft {
                DetailScreen(state: state, capture: capture, draft: draft).id(capture.id)
            } else {
                EmptyMessage(symbol: "tray", title: "Capture unavailable", message: "Open Projects to browse your saved captures.")
            }
        case .reminders: TodayPlanningScreen(state: state)
        case .settings: SettingsScreen(state: state, theme: theme)
        case .trash: TrashScreen(state: state)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                if state.route == .library {
                    ExplorerProjectPicker(state: state, workspace: state.workspace)
                        .frame(minWidth: 124, idealWidth: 160, maxWidth: 240).layoutPriority(1)
                } else {
                    DaBinLogo(variant: .compact).frame(width: 68, height: 28, alignment: .leading)
                        .overlay { WindowDragHandle(onDragStarted: { state.onBoardDragStarted?() },
                                                    onDragEnded: { state.onBoardDragEnded?($0) }).accessibilityHidden(true) }
                }
                AutoCaptureHeaderButton(service: state.autoCapture, weekly: state.route == .weekly,
                    statusText: state.autoCapture.overallStatusText, isVisible: state.isBoardVisible) { state.toggleAutoCaptureFromHeader() }
                WindowDragHandle(onDragStarted: { state.onBoardDragStarted?() },
                                 onDragEnded: { state.onBoardDragEnded?($0) })
                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 28).layoutPriority(-1)
                    .accessibilityHidden(true)
                newTaskButton
                if state.route != .search {
                    BuddyIconButton(symbol: "magnifyingglass", title: "Search captures", tooltipID: "board-search-tooltip") {
                        state.performSearchCommand(); searchFocused = true
                    }.accessibilityIdentifier("board-search")
                }
                BuddyIconButton(symbol: "gearshape", title: "Settings", tooltipID: "board-settings-tooltip") { state.showSettings() }
                    .accessibilityIdentifier("board-settings")
                moreMenu
                BuddyIconButton(symbol: "arrow.up.left.and.arrow.down.right", title: "Expand or restore window",
                                tooltipID: "window-expand-tooltip") {
                    state.onToggleExpandedWindow?()
                }.accessibilityIdentifier("window-expand")
                SmallIcon(symbol: "xmark", label: "Hide DaBin", size: 28) { state.onDismiss?() }
                    .accessibilityIdentifier("window-close")
            }
            if state.route == .search {
                HStack(spacing: 6) {
                    backButton
                    searchField
                    SearchFiltersControl(state: state)
                }
            } else if isPrimary {
                HStack(spacing: 4) {
                    navigationButton("Inbox", symbol: "tray", selected: state.isInboxRoute) { state.openInbox() }
                    navigationButton("Today", symbol: "sun.max", selected: state.route == .reminders) { state.showReminders() }
                    navigationButton("Projects", symbol: "folder", selected: state.route == .library,
                                     identifier: "primary-workspace") { state.openLibrary() }
                }.accessibilityElement(children: .contain).accessibilityLabel("Main views")
            } else {
                HStack(spacing: 8) {
                    backButton
                    Text(routeTitle).font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }.frame(minHeight: 28)
            }
            if state.isInboxRoute { timelineControls }
        }.padding(.horizontal, 12).padding(.vertical, 6)
            .fixedSize(horizontal: false, vertical: true)
            .background(Palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var backButton: some View {
        Button { state.back() } label: {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 12)).frame(minHeight: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(accent)
            .buddyHelp("Return to previous view").accessibilityIdentifier("board-back")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
                TextField(Self.searchPlaceholder, text: Binding(
                    get: { state.route == .search ? state.query : "" },
                    set: { state.updateGlobalSearch($0) }))
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityLabel("Search everything saved in DaBin, \(state.searchScopeTitle)").accessibilityIdentifier("global-search")
                    .onSubmit { state.submitSearch() }
                    .task(id: state.globalSearchFocusRequest) {
                        // Reopening can detach the native editor while SwiftUI
                        // still remembers this field as focused. Retry an actual
                        // focus transition after the editor is attached again.
                        searchFocused = false
                        await Task.yield()
                        guard !Task.isCancelled, state.route == .search else { return }
                        searchFocused = true
                    }
                if state.route == .search && !state.query.isEmpty {
                    Button {
                        state.updateGlobalSearch("")
                        state.globalSearchFocusRequest &+= 1
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .buddyHelp("Clear search").accessibilityLabel("Clear search")
                }
            }.padding(7).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
    }

    private func navigationButton(_ title: String, symbol: String, selected: Bool,
                                  identifier: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: selected ? .semibold : .medium))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity).frame(minHeight: 32)
                .overlay(alignment: .bottom) { if selected { Capsule().fill(accent).frame(height: 2).padding(.horizontal, 5) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? Palette.foreground : Palette.muted)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier(identifier ?? "primary-\(title.lowercased())")
    }

    private var newTaskButton: some View {
        Button {
            state.openNewTask()
        } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).frame(width: 28, height: 32) }
        .buttonStyle(.plain).fixedSize().buddyHelp("New task", id: "primary-tooltip-add")
        .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("New task").accessibilityIdentifier("timeline-action-add")
    }

    private var moreMenu: some View {
        let hasDay = DayExportDocument.hasCaptures(captures: state.store.captures, selectedDate: exportDay)
        let hasWeek = WeekExportDocument.hasCaptures(captures: state.store.captures, weekEndingDate: state.weekEndingDay)
        return Menu {
            if state.route == .weekly {
                Button("Search selected day", systemImage: "calendar") { state.openSearch(day: state.weeklyActionDay) }
                Button("Search selected week", systemImage: "rectangle.stack") { state.openSearch(week: state.weeklyDays) }
                Divider()
            }
            if state.route != .library {
                Menu {
                    Button("Copy day · \(exportDay.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "doc.on.doc") { dayExportController.copy(dayDocument) }.disabled(!hasDay)
                    Button("Export day · \(exportDay.formatted(.dateTime.month(.abbreviated).day()))…", systemImage: "doc.badge.arrow.up") { reportExport(dayExportController.save(dayDocument)) }.disabled(!hasDay)
                    Button("Copy selected week", systemImage: "doc.on.doc.fill") { dayExportController.copy(weekDocument) }.disabled(!hasWeek)
                    Button("Export selected week…", systemImage: "square.and.arrow.up") { reportExport(dayExportController.save(weekDocument)) }.disabled(!hasWeek)
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Divider()
            }
            Button("Recently Deleted", systemImage: "trash") { state.showTrash() }
            Button("Back up archive…", systemImage: "externaldrive") { state.exportArchiveBackup() }.disabled(state.isArchiveOperationRunning)
            Button("Restore archive backup…", systemImage: "arrow.counterclockwise") { state.restoreArchiveBackup() }.disabled(state.isArchiveOperationRunning)
        } label: { Image(systemName: "ellipsis.circle").font(.system(size: 16, weight: .semibold)).frame(width: 28, height: 32) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(accent).buddyHelp("More options")
        .accessibilityLabel("More options").accessibilityIdentifier("board-more")
    }

    private var exportDay: Date { state.route == .weekly ? state.weeklyActionDay : state.selectedDay }
    private var dayDocument: DayExportDocument { DayExportDocument.make(captures: state.store.captures, selectedDate: exportDay) }
    private var weekDocument: WeekExportDocument { WeekExportDocument.make(captures: state.store.captures, weekEndingDate: state.weekEndingDay) }
    private func reportExport(_ result: DayExportSaveOutcome) {
        if case .failed(let message) = result { state.reportFailure(message) }
    }

    private var timelineControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if state.route == .inbox {
                    Label("To organize", systemImage: "tray.full")
                        .font(.system(size: 12, weight: .medium)).frame(minHeight: 30)
                        .foregroundStyle(accent)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isSelected).accessibilityIdentifier("inbox-organize")
                    Spacer(minLength: 0)
                } else {
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
                                .hoverTooltips()
                        }
                    SmallIcon(symbol: "chevron.right", label: state.route == .weekly ? "Next week" : "Next day", size: 26) { moveTimeline(1) }
                        .disabled(Calendar.current.isDateInToday(state.route == .weekly ? state.weekEndingDay : state.selectedDay))
                    BuddyIconButton(symbol: "tray.full", title: "To organize") { state.openInbox() }
                        .accessibilityIdentifier("inbox-organize")
                }
                timelineModeToggle
                if isTimeline && !Calendar.current.isDateInToday(state.route == .weekly ? state.weekEndingDay : state.selectedDay) {
                    Button {
                        if state.route == .weekly { state.showCurrentWeek() } else { state.openDaily() }
                    } label: { Image(systemName: "arrow.uturn.backward").frame(width: 22, height: 28) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                        .accessibilityLabel("Return to today").buddyHelp("Return to today")
                }
            }
            if isTimeline { CaptureFilterStrip(selection: $state.filter) }
        }
    }

    private var timelineModeToggle: some View {
        HStack(spacing: 2) {
            ForEach([BoardTimelineMode.daily, .weekly], id: \.self) { mode in
                let selected = isTimeline && state.timelineMode == mode
                Button { state.selectTimelineMode(mode) } label: {
                    Text(mode == .daily ? "Day" : "Week")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: mode == .daily ? 44 : 50, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                    .foregroundStyle(selected ? accent : Palette.muted)
                    .background(selected ? accent.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(mode == .daily ? "Daily view" : "Weekly view")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier(mode == .daily ? "timeline-mode-daily" : "timeline-mode-weekly")
                    .buddyHelp(mode == .daily ? "Captures for the selected day" : "Browse the seven-day calendar",
                               id: "timeline-mode-tooltip-\(mode == .daily ? "daily" : "weekly")")
            }
        }.padding(2).background(Palette.soft, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .contain).accessibilityLabel("Inbox calendar view")
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
        case .search: return "Search"
        case .searchNote: return "Notes"
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
            Button { state.dismissNotification() } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).buddyHelp("Dismiss message").accessibilityLabel("Dismiss message")
        }.padding(10).background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("app-notification-banner")
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Auto Capture: \(service.overallStatusText)")
                .accessibilityIdentifier("auto-capture-status")
            Spacer(minLength: 0)
            if let project = state.libraryProject {
                Label("Destination: \(project)", systemImage: "folder.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent).lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Auto Capture destination: \(project)")
                    .accessibilityIdentifier("auto-capture-destination")
            } else {
                Label("Destination: Unfiled", systemImage: "tray")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Auto Capture destination: Unfiled")
                    .accessibilityIdentifier("auto-capture-destination")
            }
        }.padding(.horizontal, 16).padding(.vertical, 9)
            .background(Palette.background)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}
