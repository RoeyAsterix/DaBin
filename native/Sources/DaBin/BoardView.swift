import SwiftUI

@MainActor
struct BoardView: View {
    @ObservedObject var state: AppState
    @StateObject private var theme: ThemeSettings

    init(state: AppState, theme: ThemeSettings? = nil) {
        self.state = state
        _theme = StateObject(wrappedValue: theme ?? ThemeSettings())
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
        .background(Palette.background.opacity(theme.boardOpacity))
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
        .background {
            Group {
                Button("Search captures") { state.openSearch() }.keyboardShortcut("k", modifiers: .command)
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
        case .detail: return state.selectedCapture?.kind == .task ? "Task" : "Capture"
        case .reminders: return "Reminders"
        case .settings: return "Settings"
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if state.route != .daily {
                SmallIcon(symbol: "chevron.left", label: "Back") { state.back() }
            }
            HStack(spacing: 0) {
                if state.route == .daily || state.route == .weekly {
                    DaBinLogo()
                    if state.autoCapture.settings.isEnabled {
                        Circle()
                            .fill(autoCaptureIndicatorColor)
                            .frame(width: 7, height: 7)
                            .padding(.leading, 7)
                            .help(autoCaptureStatusText)
                            .accessibilityLabel(autoCaptureStatusText)
                    }
                    if state.route == .weekly {
                        Text("Week").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.muted).padding(.leading, 13)
                            .accessibilityAddTraits(.isHeader)
                    }
                } else {
                    Text(title).font(.system(size: 23, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .overlay {
                WindowDragHandle(onDragStarted: { state.onBoardDragStarted?() })
                    .accessibilityHidden(true)
            }
            if state.route == .daily || state.route == .weekly {
                SmallIcon(symbol: "plus", label: "Add task", tint: accent) { state.openNewTask() }
                SmallIcon(symbol: "magnifyingglass", label: "Search captures, Command K") { state.openSearch() }
                SmallIcon(symbol: "bell", label: "Reminders") { state.showReminders() }
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
                    Image(systemName: "ellipsis").frame(width: 28, height: 30)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More options").accessibilityLabel("More options")
            }
            SmallIcon(symbol: "xmark", label: "Hide DaBin") { state.onDismiss?() }
        }
        .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 10)
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
