import SwiftUI

@MainActor
struct BoardView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var state: AppState
    @StateObject private var theme: ThemeSettings
    @StateObject private var dayExportController: DayExportActionController
    @StateObject private var tooltipController: TimelineTooltipController
    @State private var showWeekCalendar = false
    @State private var settingsHovered = false
    @FocusState private var settingsFocused: Bool

    init(state: AppState, theme: ThemeSettings? = nil,
         dayExportController: DayExportActionController? = nil,
         tooltipController: TimelineTooltipController? = nil) {
        self.state = state
        _theme = StateObject(wrappedValue: theme ?? ThemeSettings())
        _dayExportController = StateObject(wrappedValue: dayExportController ?? .live())
        _tooltipController = StateObject(wrappedValue: tooltipController ?? TimelineTooltipController())
    }

    private var accent: Color { theme.accent }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = state.store.error.map({ AppStatusMessage(text: $0, severity: .error) }) ?? state.status {
                statusBanner(message)
            }
            switch state.route {
            case .daily: DailyScreen(state: state)
            case .weekly: WeeklyScreen(state: state)
            case .search: SearchScreen(state: state)
            case .newTask: NewTaskScreen(state: state, draft: state.newTaskDraft)
            case .detail:
                if let capture = state.selectedCapture, let draft = state.selectedDraft {
                    DetailScreen(state: state, capture: capture, draft: draft)
                        .id(capture.id)
                } else { EmptyMessage(symbol: "tray", title: "Capture unavailable", message: "Return to Daily to browse your captures.") }
            case .reminders: RemindersScreen(state: state)
            case .settings: SettingsScreen(state: state, theme: theme)
            }
        }
        .foregroundStyle(Palette.foreground)
        .tint(accent)
        .environment(\.daBinAccent, accent)
        .background(Palette.background.opacity(ThemeSettings.effectiveBoardOpacity(
            preferred: theme.boardOpacity,
            reduceTransparency: reduceTransparency
        )))
        .preferredColorScheme(theme.darkModeEnabled ? .dark : .light)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .overlay {
            if state.route == .daily && state.isDailyDropTargeted {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(accent.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(accent, lineWidth: 2))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .alert("Remove this capture?", isPresented: Binding(
            get: { state.pendingRemoval != nil },
            set: { if !$0 { state.pendingRemoval = nil } }
        ), presenting: state.pendingRemoval) { capture in
            Button("Cancel", role: .cancel) { state.pendingRemoval = nil }
            Button("Remove", role: .destructive) {
                state.pendingRemoval = nil
                Task { await state.removeCapture(capture) }
            }
        } message: { _ in
            Text("This removes the capture, its comments, reminder and saved copies from DaBin. Files at their original locations are kept. This cannot be undone.")
        }
        .onExitCommand { state.onDismiss?() }
        .onChange(of: state.status) { _, message in
            if let message { AccessibilityAnnouncement.post(message.text) }
        }
        .background {
            Group {
                Button("Search captures") {
                    state.performSearchCommand()
                }.keyboardShortcut("k", modifiers: .command)
                Button("Open Daily") { state.openDaily() }.keyboardShortcut("d", modifiers: [.command, .shift])
            }.frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    private var title: String {
        switch state.route {
        case .daily: return "Daily"
        case .weekly: return "Week"
        case .search: return "Search"
        case .newTask: return "New task"
        case .detail: return state.selectedCapture?.isTask == true ? "Task" : "Capture"
        case .reminders: return "Reminders"
        case .settings: return "Settings"
        }
    }

    @ViewBuilder
    private var header: some View {
        if state.route == .daily || state.route == .weekly {
            timelineHeader
        } else {
            routeHeader
        }
    }

    private var routeHeader: some View {
        HStack(spacing: 8) {
            SmallIcon(symbol: "chevron.left", label: "Back") { state.back() }
            HStack(spacing: 0) {
                Text(title).font(.system(size: 23, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .overlay {
                WindowDragHandle(onDragStarted: { state.onBoardDragStarted?() })
                    .accessibilityHidden(true)
            }
            SmallIcon(symbol: "xmark", label: "Hide DaBin") { state.onDismiss?() }
        }
        .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 10)
    }

    private var timelineHeader: some View {
        VStack(spacing: 0) {
            timelineNavigationRow
                .frame(height: TimelineIconRowMetrics.controlHeight)
                .padding(.horizontal, 12)
                .padding(.top, 5)
                .zIndex(2)
            timelinePrimaryActions
                .frame(height: 34)
            FilterBar(selection: $state.filter)
        }
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.timelineTooltipController, tooltipController)
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                if let tooltip = tooltipController.visible {
                    TimelineHoverTooltip(text: tooltip.text)
                        .position(x: tooltip.anchorX(in: proxy.size.width),
                                  y: tooltipY(tooltip, headerHeight: proxy.size.height))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .animation(.easeOut(duration: 0.12), value: tooltipController.visible)
        .zIndex(10)
        .onDisappear { tooltipController.dismiss() }
    }

    private func tooltipY(_ tooltip: TimelineTooltipDescriptor,
                          headerHeight: CGFloat) -> CGFloat {
        switch tooltip.row {
        case .navigation:
            return 52
        case .primary:
            // Point directly back to the primary icon and temporarily cover
            // the aligned filter beneath it instead of looking attached to it.
            return headerHeight - (TimelineIconRowMetrics.controlHeight + 4) + 15
        case .filters:
            return headerHeight + 15
        }
    }

    private var timelineNavigationRow: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .trailing) {
                DaBinLogo()
                    .scaleEffect(0.86, anchor: .leading)
                    .frame(width: 80, height: 30, alignment: .leading)
                if state.autoCapture.settings.isEnabled {
                    Circle()
                        .fill(autoCaptureIndicatorColor)
                        .frame(width: 7, height: 7)
                        .help(autoCaptureStatusText)
                        .accessibilityLabel(autoCaptureStatusText)
                }
            }
            .frame(width: 80, height: 30, alignment: .leading)
            .overlay {
                WindowDragHandle(onDragStarted: { state.onBoardDragStarted?() })
                    .accessibilityHidden(true)
            }
            .layoutPriority(3)

            SmallIcon(symbol: "chevron.left", label: previousDateLabel, size: 28) {
                moveTimeline(-1)
            }
            timelineDateButton
            SmallIcon(symbol: "chevron.right", label: nextDateLabel, size: 28) {
                moveTimeline(1)
            }
            .disabled(Calendar.current.isDateInToday(timelineExportDate))

            TimelineModeControl(state: state)
                .layoutPriority(2)
            Spacer(minLength: 2)
            SmallIcon(symbol: "xmark", label: "Hide DaBin", size: 28) { state.onDismiss?() }
                .accessibilityIdentifier("window-close")
        }
    }

    @ViewBuilder
    private var timelineDateButton: some View {
        if state.route == .weekly {
            Button { showWeekCalendar.toggle() } label: {
                HStack(spacing: 4) {
                    Text(weeklyRangeLabel)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 86, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose the last day of the week")
            .accessibilityLabel("Choose week, \(weeklyRangeLabel)")
            .accessibilityIdentifier("timeline-date")
            .popover(isPresented: $showWeekCalendar, arrowEdge: .bottom) {
                DatePicker("Week ending", selection: Binding(
                    get: { state.weekEndingDay },
                    set: { state.setWeekEndingDay($0) }
                ),
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(12)
                    .frame(width: 280)
                    .onChange(of: state.weekEndingDay) { _, _ in showWeekCalendar = false }
                    .onExitCommand { showWeekCalendar = false }
            }
        } else {
            Button { state.openWeekly() } label: {
                Text(state.selectedDay, format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 52, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the last seven days")
            .accessibilityLabel("Open weekly view ending \(state.selectedDay.formatted(date: .complete, time: .omitted))")
            .accessibilityIdentifier("timeline-date")
        }
    }

    private var timelinePrimaryActions: some View {
        HStack(spacing: TimelineIconRowMetrics.spacing(itemCount: TimelinePrimaryAction.allCases.count)) {
            AccentIconButton(symbol: TimelinePrimaryAction.add.symbol,
                             label: TimelinePrimaryAction.add.label,
                             tooltip: primaryTooltip(.add, index: 0),
                             accessibilityIdentifier: "timeline-action-add") {
                state.openNewTask()
            }
            if state.route == .weekly {
                WeeklySearchButton(state: state, isPresented: $state.weeklySearchActionsPresented)
            } else {
                AccentIconButton(symbol: TimelinePrimaryAction.search.symbol,
                                 label: TimelinePrimaryAction.search.label,
                                 tooltip: primaryTooltip(.search, index: 1),
                                 accessibilityIdentifier: "timeline-action-search") {
                    state.openSearch()
                }
            }
            TimelineExportButton(state: state, controller: dayExportController)
            AccentIconButton(symbol: TimelinePrimaryAction.notifications.symbol,
                             label: TimelinePrimaryAction.notifications.label,
                             tooltip: primaryTooltip(.notifications, index: 3),
                             accessibilityIdentifier: "timeline-action-notifications") {
                state.showReminders()
            }
            settingsMenu
        }
        .frame(width: TimelineIconRowMetrics.rowWidth,
               height: TimelineIconRowMetrics.controlHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary actions")
    }

    private var settingsMenu: some View {
        Menu {
            if state.autoCapture.settings.isEnabled {
                Text(autoCaptureStatusText)
                Button(state.autoCapture.settings.isPaused ? "Resume Auto Capture" : "Pause Auto Capture") {
                    state.autoCapture.setPaused(!state.autoCapture.settings.isPaused)
                }
                Divider()
            }
            Button("Settings…") { state.showSettings() }
        } label: {
            AccentIconMenuLabel(symbol: TimelinePrimaryAction.settings.symbol,
                                hovered: $settingsHovered, focused: settingsFocused)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: TimelineIconRowMetrics.controlWidth,
               height: TimelineIconRowMetrics.controlHeight)
        .focused($settingsFocused)
        // Menu owns AppKit's tracking region, so hover must be observed here
        // rather than on its SwiftUI label content.
        .onHover { isHovering in
            settingsHovered = isHovering
            updateSettingsTooltip(hovered: isHovering, focused: settingsFocused)
        }
        .onChange(of: settingsFocused) { _, isFocused in
            updateSettingsTooltip(hovered: settingsHovered, focused: isFocused)
        }
        .simultaneousGesture(TapGesture().onEnded {
            tooltipController.activate(id: "primary-tooltip-settings")
        })
        .onDisappear {
            settingsHovered = false
            tooltipController.end(id: "primary-tooltip-settings")
        }
        .accessibilityLabel(TimelinePrimaryAction.settings.label)
        .accessibilityIdentifier("timeline-action-settings")
    }

    private func updateSettingsTooltip(hovered: Bool, focused: Bool) {
        let tooltip = primaryTooltip(.settings, index: 4)
        if hovered || focused {
            tooltipController.begin(tooltip, immediate: focused && !hovered)
        } else {
            tooltipController.end(id: tooltip.id)
        }
    }

    private func primaryTooltip(_ action: TimelinePrimaryAction, index: Int) -> TimelineTooltipDescriptor {
        TimelineTooltipDescriptor(id: "primary-tooltip-\(action.rawValue)",
                                  text: action.tooltipLabel,
                                  index: index,
                                  itemCount: TimelinePrimaryAction.allCases.count)
    }

    private var timelineExportDate: Date {
        state.route == .weekly ? state.weekEndingDay : state.selectedDay
    }

    private var weeklyRangeLabel: String {
        guard let first = state.weeklyDays.first else { return "Last 7 days" }
        let start = first.formatted(.dateTime.month(.abbreviated).day())
        let end = state.weekEndingDay.formatted(.dateTime.month(.abbreviated).day())
        return "\(start)–\(end)"
    }

    private var previousDateLabel: String {
        state.route == .weekly ? "Previous seven days" : "Previous day"
    }

    private var nextDateLabel: String {
        state.route == .weekly ? "Next seven days" : "Next day"
    }

    private func moveTimeline(_ amount: Int) {
        if state.route == .weekly { state.moveWeek(amount) }
        else { state.moveDay(amount) }
    }

    private var autoCaptureStatusText: String {
        switch state.autoCapture.settings.status {
        case .disabled: return "Auto Capture off"
        case .paused: return "Auto Capture paused"
        case .ready: return "Auto Capture ready"
        case .monitoring: return "Auto Capture enabled"
        case .permissionRequired: return "Auto Capture needs a screenshot folder"
        case .permissionRevoked: return "Auto Capture permission needs attention"
        case .sourceApplicationExcluded(let name): return "Auto Capture is skipping \(name)"
        case .failed: return "Auto Capture needs attention"
        }
    }

    private var autoCaptureIndicatorColor: Color {
        switch state.autoCapture.settings.status {
        case .monitoring, .sourceApplicationExcluded: return accent
        case .paused: return .orange
        case .permissionRequired, .permissionRevoked, .failed: return Palette.task
        case .disabled, .ready: return Palette.muted
        }
    }

    private func statusBanner(_ message: AppStatusMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.symbol).foregroundStyle(message.severity == .error ? Palette.task : accent)
            Text(message.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { state.status = nil; state.store.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).help("Dismiss message").accessibilityLabel("Dismiss message")
        }.padding(10).background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 16).padding(.bottom, 8)
    }
}
