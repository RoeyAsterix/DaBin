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
    @StateObject private var tutorial = DaBinTutorialController()
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
            routeContent
                .environment(\.workspaceZoom, state.route == .settings ? WorkspaceZoomLayout() :
                    WorkspaceZoomLayout(factor: state.workspaceZoom.factor,
                        isInteracting: state.workspaceZoom.isInteracting))
                .background(WorkspaceInputRegion())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .daBinTutorialAnchor(.routeBody)
            BoardCaptureStatus(state: state, service: state.autoCapture, settings: state.autoCapture.settings)
        }
        .foregroundStyle(Palette.foreground).tint(accent).environment(\.daBinAccent, accent)
        .environment(\.daBinTooltipsEnabled, theme.showTooltips)
        .environment(\.timelineTooltipController, tooltipController)
        .environment(\.hoverTooltipActiveID, tooltipController.visible?.id)
        .environment(\.daBinTutorialTargets, tutorial.isPresented ? Set(tutorial.step.targetCandidates) : [])
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
        .overlayPreferenceValue(DaBinTutorialAnchorKey.self) { anchors in
            if tutorial.isPresented {
                DaBinTutorialOverlay(tutorial: tutorial, state: state, anchors: anchors)
                    .transition(.opacity)
                    .zIndex(100)
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
            if tutorial.isPresented { tutorial.finish(in: state) }
            else if searchFocused { searchFocused = false }
            else { state.onDismiss?() }
        }
        .onChange(of: state.route) { _, route in
            tooltipController.dismiss()
            guard tutorial.isPresented else {
                searchFocused = route == .search
                return
            }
            searchFocused = false
            if route != tutorial.step.destination {
                Task { @MainActor in
                    guard tutorial.isPresented, state.route != tutorial.step.destination else { return }
                    tutorial.restoreCurrentStep(in: state)
                }
            }
        }
        .onChange(of: theme.showTooltips, initial: true) { _, enabled in tooltipController.setEnabled(enabled) }
        .onAppear { [weak state, weak tutorial] in
            tooltipController.setPresentationActive(true)
            state?.onTutorialEscape = { [weak state, weak tutorial] in
                guard let state, let tutorial, tutorial.isPresented else { return false }
                tutorial.finish(in: state)
                return true
            }
        }
        .onChange(of: state.isBoardVisible) { _, visible in
            tooltipController.setPresentationActive(visible)
        }
        .onDisappear {
            tooltipController.setPresentationActive(false)
            if tutorial.isPresented { tutorial.finish(in: state) }
            state.onTutorialEscape = nil
        }
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
        case .settings: SettingsScreen(state: state, theme: theme, runTutorial: { tutorial.start(in: state) })
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
                exportManagementMenu
                BuddyIconButton(symbol: "arrow.up.left.and.arrow.down.right", title: "Expand or restore window",
                                tooltipID: "window-expand-tooltip") {
                    state.onToggleExpandedWindow?()
                }.accessibilityIdentifier("window-expand")
                SmallIcon(symbol: "xmark", label: "Hide DaBin", size: 28) { state.onDismiss?() }
                    .accessibilityIdentifier("window-close")
            }
            if state.route == .search {
                HStack(spacing: 6) {
                    historyControls
                    searchField
                    SearchFiltersControl(state: state)
                }
            } else if isPrimary {
                HStack(spacing: 4) {
                    historyControls
                    navigationButton("Inbox", symbol: "tray", selected: state.isInboxRoute) { state.openInbox() }
                    navigationButton("Today", symbol: "sun.max", selected: state.route == .reminders) { state.showReminders() }
                    navigationButton("Projects", symbol: "folder", selected: state.route == .library,
                                     identifier: "primary-workspace") { state.openLibrary() }
                }.accessibilityElement(children: .contain).accessibilityLabel("Main views")
            } else {
                HStack(spacing: 8) {
                    historyControls
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

    private var historyControls: some View {
        HStack(spacing: 1) {
            Button { state.back() } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }.disabled(!state.canGoBack || state.isNavigationBlocked)
                .buddyHelp("Back (⌘[)").accessibilityLabel("Back")
                .accessibilityIdentifier("board-back")
            Button { state.forward() } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }.disabled(!state.canGoForward || state.isNavigationBlocked)
                .buddyHelp("Forward (⌘])").accessibilityLabel("Forward")
                .accessibilityIdentifier("board-forward")
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityElement(children: .contain).accessibilityLabel("View history")
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
                .daBinTutorialAnchor(.searchField)
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

    private var exportManagementMenu: some View {
        let hasDay = DayExportDocument.hasCaptures(captures: state.store.captures, selectedDate: exportDay)
        let hasWeek = WeekExportDocument.hasCaptures(captures: state.store.captures, selectedDays: state.weeklyDays)
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
        } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).frame(width: 28, height: 32) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(accent).buddyHelp("Export Management")
        .accessibilityLabel("Export Management").accessibilityIdentifier("board-more")
        .daBinTutorialAnchor(.boardMore)
    }

    private var exportDay: Date { state.route == .weekly ? state.weeklyActionDay : state.selectedDay }
    private var dayDocument: DayExportDocument { DayExportDocument.make(captures: state.store.captures, selectedDate: exportDay) }
    private var weekDocument: WeekExportDocument { WeekExportDocument.make(captures: state.store.captures, selectedDays: state.weeklyDays) }
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
                        HStack(spacing: 5) {
                            Image(systemName: "calendar").foregroundStyle(accent)
                            Text(timelineDateLabel).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted)
                        }.font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityLabel("Choose date, \(timelineDateLabel)").accessibilityIdentifier("timeline-date")
                        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                            TimelineCalendarPicker(state: state, weekly: state.route == .weekly) { showCalendar = false }
                                .environment(\.daBinAccent, accent)
                                .preferredColorScheme(theme.darkModeEnabled ? .dark : .light)
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
                    .buddyHelp(mode == .daily ? "Captures for the selected day" : "Choose up to seven days with activity",
                               id: "timeline-mode-tooltip-\(mode == .daily ? "daily" : "weekly")")
            }
        }.padding(2).background(Palette.soft, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .contain).accessibilityLabel("Inbox calendar view")
            .daBinTutorialAnchor(.timelineModes)
    }

    private var timelineDateLabel: String {
        if state.route == .weekly, state.isCustomWeekSelection {
            let count = state.weeklyDays.count
            return count == 1 ? state.weeklyDays[0].formatted(.dateTime.month(.abbreviated).day()) : "\(count) selected days"
        }
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

enum DaBinTutorialTarget: Hashable {
    case routeBody
    case settingsTutorial
    case inboxComposer
    case inboxActions
    case captureFeed
    case timelineModes
    case captureFilters
    case captureActions
    case todayControls
    case projectPicker
    case projectModes
    case searchField
    case automaticCapture
    case captureDestination
    case boardMore
}

private struct DaBinTutorialTargetsEnvironmentKey: EnvironmentKey {
    static let defaultValue: Set<DaBinTutorialTarget> = []
}

extension EnvironmentValues {
    var daBinTutorialTargets: Set<DaBinTutorialTarget> {
        get { self[DaBinTutorialTargetsEnvironmentKey.self] }
        set { self[DaBinTutorialTargetsEnvironmentKey.self] = newValue }
    }
}

private struct DaBinTutorialAnchorKey: PreferenceKey {
    static var defaultValue: [DaBinTutorialTarget: [Anchor<CGRect>]] = [:]

    static func reduce(value: inout [DaBinTutorialTarget: [Anchor<CGRect>]],
                       nextValue: () -> [DaBinTutorialTarget: [Anchor<CGRect>]]) {
        for (target, anchors) in nextValue() {
            value[target, default: []].append(contentsOf: anchors)
        }
    }
}

private struct DaBinTutorialAnchorModifier: ViewModifier {
    @Environment(\.daBinTutorialTargets) private var activeTargets
    let target: DaBinTutorialTarget

    func body(content: Content) -> some View {
        content.anchorPreference(key: DaBinTutorialAnchorKey.self, value: .bounds) { anchor in
            activeTargets.contains(target) ? [target: [anchor]] : [:]
        }
    }
}

extension View {
    func daBinTutorialAnchor(_ target: DaBinTutorialTarget) -> some View {
        modifier(DaBinTutorialAnchorModifier(target: target))
    }
}

enum DaBinTutorialStep: String, CaseIterable, Identifiable {
    case welcome, capture, inbox, day, week, captureActions, today, projects, projectRecording
    case search, automation, localControl, finish

    static let ordered: [Self] = [
        .welcome, .capture, .projectRecording, .inbox, .day, .week, .captureActions,
        .today, .projects, .search, .automation, .localControl, .finish
    ]

    var id: String { rawValue }

    var destination: BoardRoute {
        switch self {
        case .welcome, .automation, .localControl, .finish: return .settings
        case .capture, .inbox, .captureActions: return .inbox
        case .day: return .daily
        case .week: return .weekly
        case .today: return .reminders
        case .projects, .projectRecording: return .library
        case .search: return .search
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Welcome to DaBin"
        case .capture: return "Capture anything"
        case .inbox: return "Start in Inbox"
        case .day: return "Review your Day"
        case .week: return "See the whole Week"
        case .captureActions: return "Keep every capture useful"
        case .today: return "Plan in Today"
        case .projects: return "Build a project workspace"
        case .projectRecording: return "Record to a project"
        case .search: return "Find it again"
        case .automation: return "Choose what runs automatically"
        case .localControl: return "Stay local and in control"
        case .finish: return "You’re ready"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Hi, I’m DaBin. I’ll walk across the real app and show you the complete capture-to-project loop."
        case .capture:
            return "This is the drop and quick-capture area. After the tour, drop text, links, files, images, or video here—or hover over me and paste."
        case .inbox:
            return "Inbox is the landing zone. These controls are where you paste the clipboard, import files, jot a note, or create a task."
        case .day:
            return "Day keeps captures in their real timeline. Use the highlighted switch to move between one day and the seven-day view."
        case .week:
            return "Week lays out seven days together. The highlighted filters narrow both views to text, links, files, media, or tasks."
        case .captureActions:
            return "The highlighted More control appears on every card. It opens copy, notes, reminders, pinning, projects, task conversion, minimizing, and removal."
        case .today:
            return "Today brings tasks and reminders together. Add priorities, deadlines, checklists, repeat rules, and focus timers as work develops."
        case .projects:
            return "Projects hold captures, files, links, tasks, and notes. Switch between Library, Clipboard, Shelf, and Notes; select, reorder, convert, copy, or export together."
        case .projectRecording:
            return "This live strip shows capture state and destination. After the tour, choose a project above and enable Clipboard or Screenshots to file new items there."
        case .search:
            return "Search every saved item—including local text found inside images, PDFs, and supported documents. Refine by project, date, type, or source."
        case .automation:
            return "Automatic capture starts off. Clipboard and Screenshots are separate, pausable choices, and excluded apps stay unread."
        case .localControl:
            return "Your archive stays on this Mac. Export Management offers exports, Recently Deleted, backup, and restore; Settings opens the archive and controls shortcuts, appearance, and privacy."
        case .finish:
            return "That’s the loop: capture, find, plan, and move work into a project. Run this tutorial again anytime from Settings."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "sparkles"
        case .capture: return "arrow.down.doc"
        case .inbox: return "tray.full"
        case .day: return "calendar.day.timeline.left"
        case .week: return "calendar"
        case .captureActions: return "ellipsis.circle"
        case .today: return "sun.max"
        case .projects: return "folder"
        case .projectRecording: return "record.circle"
        case .search: return "magnifyingglass"
        case .automation: return "bolt.badge.clock"
        case .localControl: return "lock.macwindow"
        case .finish: return "checkmark.circle.fill"
        }
    }

    var targetCandidates: [DaBinTutorialTarget] {
        switch self {
        case .welcome, .finish: return [.settingsTutorial, .routeBody]
        case .capture: return [.inboxComposer, .routeBody]
        case .projectRecording: return [.captureDestination, .projectPicker, .routeBody]
        case .inbox: return [.inboxActions, .inboxComposer, .routeBody]
        case .day: return [.timelineModes, .routeBody]
        case .week: return [.captureFilters, .timelineModes, .routeBody]
        case .captureActions: return [.captureActions, .captureFeed, .routeBody]
        case .today: return [.todayControls, .routeBody]
        case .projects: return [.projectModes, .projectPicker, .routeBody]
        case .search: return [.searchField, .routeBody]
        case .automation: return [.automaticCapture, .routeBody]
        case .localControl: return [.boardMore, .routeBody]
        }
    }

    fileprivate var robotPose: DaBinTutorialRobotPose {
        switch self {
        case .capture: return .capture
        case .inbox, .day, .week, .automation: return .working
        case .welcome, .projects, .projectRecording, .search, .localControl: return .curious
        case .captureActions, .today, .finish: return .celebrate
        }
    }
}

@MainActor
final class DaBinTutorialController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var stepIndex = 0
    private var returnRoute: BoardRoute?
    private var returnSearchDateAnchor: String?
    private var returnDropTargeted = false

    var step: DaBinTutorialStep { DaBinTutorialStep.ordered[stepIndex] }
    var stepCount: Int { DaBinTutorialStep.ordered.count }
    var canGoBack: Bool { stepIndex > 0 }
    var isLastStep: Bool { stepIndex == stepCount - 1 }

    func start(in state: AppState) {
        if !isPresented {
            returnRoute = state.route
            returnSearchDateAnchor = state.searchDateAnchor
            returnDropTargeted = state.isDailyDropTargeted
        }
        stepIndex = 0
        isPresented = true
        state.setTutorialPresented(true)
        presentCurrentStep(in: state)
    }

    func goBack(in state: AppState) {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        presentCurrentStep(in: state)
    }

    func advance(in state: AppState) {
        guard !isLastStep else { finish(in: state); return }
        stepIndex += 1
        presentCurrentStep(in: state)
    }

    func finish(in state: AppState) {
        let destination = returnRoute ?? .settings
        let searchDateAnchor = returnSearchDateAnchor
        let dropTargeted = returnDropTargeted
        isPresented = false
        returnRoute = nil
        state.setTutorialPresented(false)
        state.route = destination
        state.searchDateAnchor = searchDateAnchor
        state.isDailyDropTargeted = dropTargeted
    }

    func restoreCurrentStep(in state: AppState) {
        applyCurrentStep(in: state)
    }

    private func presentCurrentStep(in state: AppState) {
        applyCurrentStep(in: state)
        AccessibilityAnnouncement.post("\(step.title). \(step.message)")
    }

    private func applyCurrentStep(in state: AppState) {
        state.route = step.destination
        state.isDailyDropTargeted = step == .capture
    }
}

private enum DaBinTutorialRobotPose: Equatable {
    case curious, capture, working, celebrate
}

@MainActor
private struct DaBinTutorialOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var tutorial: DaBinTutorialController
    @ObservedObject var state: AppState
    let anchors: [DaBinTutorialTarget: [Anchor<CGRect>]]

    var body: some View {
        GeometryReader { geometry in
            let focus = resolvedFocus(in: geometry)
            let layout = DaBinTutorialStageLayout(container: geometry.size, focus: focus)
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture { }.accessibilityHidden(true)
                DaBinTutorialScrim(focus: focus)
                    .fill(Color.black.opacity(0.32), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false).accessibilityHidden(true)
                if let focus {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent, lineWidth: 2.5)
                        .frame(width: focus.width, height: focus.height)
                        .position(x: focus.midX, y: focus.midY)
                        .shadow(color: accent.opacity(0.42), radius: 7)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    connector(from: focus, to: layout.robotCenter(in: geometry.size))
                        .stroke(accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5,
                            lineCap: .round, lineJoin: .round, dash: [5, 4]))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    if layout.panelAtBottom { Spacer(minLength: 0) }
                    tutorialCluster(layout: layout)
                        .frame(maxWidth: .infinity,
                               alignment: layout.clusterAtLeading ? .leading : .trailing)
                    if !layout.panelAtBottom { Spacer(minLength: 0) }
                }
                .padding(layout.margin)
                .id(tutorial.step.id)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityLabel("DaBin tutorial")
                .accessibilityHint("Highlighted controls are demonstrations and remain inactive until you exit the tutorial")
                .accessibilityIdentifier("dabin-tutorial-overlay")
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84),
                       value: tutorial.stepIndex)
        }
    }

    private func resolvedFocus(in geometry: GeometryProxy) -> CGRect? {
        let visible = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 8, dy: 8)
        for target in tutorial.step.targetCandidates {
            for anchor in anchors[target] ?? [] {
                let raw = geometry[anchor]
                guard !raw.isNull, !raw.isInfinite, raw.width.isFinite, raw.height.isFinite,
                      raw.intersects(visible) else { continue }
                let clipped = raw.intersection(visible)
                guard clipped.width > 1, clipped.height > 1 else { continue }
                return clipped.insetBy(dx: -6, dy: -6).intersection(visible)
            }
        }
        return nil
    }

    private func connector(from focus: CGRect, to robot: CGPoint) -> Path {
        let start = CGPoint(x: min(max(robot.x, focus.minX), focus.maxX),
                            y: min(max(robot.y, focus.minY), focus.maxY))
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: robot,
                          control: CGPoint(x: (start.x + robot.x) / 2,
                                           y: (start.y + robot.y) / 2 - 12))
        return path
    }

    @ViewBuilder private func tutorialCluster(layout: DaBinTutorialStageLayout) -> some View {
        HStack(alignment: layout.panelAtBottom ? .bottom : .top, spacing: layout.gap) {
            if layout.clusterAtLeading {
                tutorialBubble(width: layout.cardWidth)
                tutorialRobot(size: layout.robotSize)
            } else {
                tutorialRobot(size: layout.robotSize)
                tutorialBubble(width: layout.cardWidth)
            }
        }
    }

    private func tutorialRobot(size: CGSize) -> some View {
        DaBinTutorialRobotView(pose: tutorial.step.robotPose, reduceMotion: reduceMotion)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }

    private func tutorialBubble(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: tutorial.step.symbol).foregroundStyle(accent).accessibilityHidden(true)
                Text(tutorial.step.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text("\(tutorial.stepIndex + 1) of \(tutorial.stepCount)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).monospacedDigit()
            }
            Text(tutorial.step.message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(tutorial.stepIndex + 1), total: Double(tutorial.stepCount))
                .controlSize(.small).accessibilityLabel("Tutorial progress")
                .accessibilityValue("Step \(tutorial.stepIndex + 1) of \(tutorial.stepCount)")
            HStack(spacing: 9) {
                Button("Exit") { tutorial.finish(in: state) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("tutorial-exit")
                Spacer(minLength: 4)
                Button("Back") { tutorial.goBack(in: state) }
                    .disabled(!tutorial.canGoBack).accessibilityIdentifier("tutorial-back")
                Button(tutorial.isLastStep ? "Finish" : "Next") { tutorial.advance(in: state) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("tutorial-next")
            }.controlSize(.small)
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.72), lineWidth: 1.25)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }
}

private struct DaBinTutorialScrim: Shape {
    let focus: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let focus {
            path.addRoundedRect(in: focus, cornerSize: CGSize(width: 12, height: 12))
        }
        return path
    }
}

struct DaBinTutorialStageLayout {
    let margin: CGFloat
    let gap: CGFloat
    let robotSize: CGSize
    let cardWidth: CGFloat
    let panelAtBottom: Bool
    let clusterAtLeading: Bool

    init(container: CGSize, focus: CGRect?) {
        let compact = container.width < 560 || container.height < 520
        margin = compact ? 10 : 16
        gap = compact ? 4 : 6
        robotSize = compact ? CGSize(width: 58, height: 72) : CGSize(width: 78, height: 96)
        let availableCardWidth = max(210, container.width - (margin * 2) - robotSize.width - gap)
        cardWidth = min(compact ? 300 : 420, availableCardWidth)
        panelAtBottom = (focus?.midY ?? 0) < container.height / 2
        clusterAtLeading = (focus?.midX ?? 0) > container.width / 2
    }

    func robotCenter(in container: CGSize) -> CGPoint {
        let x = clusterAtLeading
            ? margin + cardWidth + gap + robotSize.width / 2
            : container.width - margin - cardWidth - gap - robotSize.width / 2
        let y = panelAtBottom
            ? container.height - margin - robotSize.height / 2
            : margin + robotSize.height / 2
        return CGPoint(x: x, y: y)
    }
}

@MainActor
private struct DaBinTutorialRobotView: NSViewRepresentable {
    let pose: DaBinTutorialRobotPose
    let reduceMotion: Bool

    final class Coordinator {
        var reduceMotion = false
        var pose: DaBinTutorialRobotPose?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> RobotCharacterView {
        context.coordinator.reduceMotion = reduceMotion
        let coordinator = context.coordinator
        let character = RobotCharacterView(frame: .zero, reduceMotion: { coordinator.reduceMotion })
        character.configureQuietOrbit(false)
        character.send(.reveal(.top))
        return character
    }

    func updateNSView(_ character: RobotCharacterView, context: Context) {
        let changedMotionPreference = context.coordinator.reduceMotion != reduceMotion
        context.coordinator.reduceMotion = reduceMotion
        if changedMotionPreference { character.refreshMotionPreference() }
        guard context.coordinator.pose != pose else { return }
        context.coordinator.pose = pose
        character.send(.feedbackExpired)
        character.send(.saving(false))
        character.send(.acceptedDrag(false))
        character.send(.hover(false))
        switch pose {
        case .curious: character.send(.hover(true, pointer: CGPoint(x: 0.45, y: -0.2)))
        case .capture: character.send(.acceptedDrag(true))
        case .working: character.send(.saving(true))
        case .celebrate: character.send(.result(.success))
        }
    }

    static func dismantleNSView(_ character: RobotCharacterView, coordinator: Coordinator) {
        character.stopMotion()
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
            .daBinTutorialAnchor(.captureDestination)
    }
}
