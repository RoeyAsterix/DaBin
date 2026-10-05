import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsScreen: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject var state: AppState
    @ObservedObject var theme: ThemeSettings
    @ObservedObject private var updates: SoftwareUpdateService
    @ObservedObject private var robotPlacement: RobotPlacementSettings
    @ObservedObject private var autoCapture: AutoCaptureService
    @ObservedObject private var autoCaptureSettings: AutoCaptureSettings
    @ObservedObject private var workspaceZoom: WorkspaceZoomSettings
    private let quitApplication: @MainActor () -> Void
    private let runTutorial: @MainActor () -> Void
    @State private var showPrivacyPolicy = false
    @State private var showAutoCaptureExplanation = false
    @State private var pendingCaptureChannel: AutoCaptureChannel = .clipboard
    @State private var showExcludedApplications = false

    init(state: AppState, theme: ThemeSettings,
         quitApplication: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) },
         runTutorial: @escaping @MainActor () -> Void = {}) {
        self.state = state
        self.theme = theme
        self.quitApplication = quitApplication
        self.runTutorial = runTutorial
        updates = state.updates
        robotPlacement = state.robotPlacement
        autoCapture = state.autoCapture
        autoCaptureSettings = state.autoCapture.settings
        workspaceZoom = state.workspaceZoom
    }

    private var selectedName: String {
        ThemePreset.allCases.first(where: { $0.hex == theme.selectedHex })?.name ?? "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSoftwareUpdateSection(updates: updates)
                SettingsTutorialSection(runTutorial: runTutorial)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Navigation and zoom", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Toggle("Trackpad Back and Forward", isOn: $workspaceZoom.trackpadNavigationEnabled)
                        .toggleStyle(.switch).controlSize(.small)
                        .accessibilityIdentifier("settings-trackpad-navigation")
                    Text("Use your Mac's page-swipe gesture to revisit views.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Resize window with workspace zoom", isOn: $workspaceZoom.resizeWindowWithZoom)
                        .toggleStyle(.switch).controlSize(.small)
                        .accessibilityIdentifier("settings-workspace-resize")
                    Text("Make room as content gets larger. Expanded windows keep their size.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pinch or use ⌘+ and ⌘− in the workspace. Reset with ⌘0.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.system(size: 14))
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Automatic capture").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Choose what to save. Both are off until you turn them on.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Clipboard", isOn: Binding(
                        get: { autoCaptureSettings.isClipboardEnabled },
                        set: { requestCapture(.clipboard, enabled: $0) }
                    ))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityIdentifier("settings-capture-clipboard")
                    Text("Save future copied text, links, images and files.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Toggle("Screenshots", isOn: Binding(
                        get: { autoCaptureSettings.isScreenshotsEnabled },
                        set: { requestCapture(.screenshots, enabled: $0) }
                    ))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 14, weight: .medium))
                    .accessibilityIdentifier("settings-capture-screenshots")
                    Text("Save new images from the screenshot folder you choose.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        Circle().fill(autoCaptureStatusColor).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(autoCaptureStatusText).font(.system(size: 12, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    if autoCaptureSettings.isScreenshotsEnabled {
                        HStack(spacing: 8) {
                            if let folder = autoCaptureSettings.screenshotFolderDisplayName {
                                Label(folder, systemImage: "folder")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Button {
                                chooseScreenshotFolder(enableAfterSelection: false)
                            } label: {
                                Text(needsScreenshotPermission ? "Choose screenshot folder…" : "Change folder…")
                                    .frame(minHeight: 32).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(accent)
                        }
                    }
                    if autoCaptureSettings.isEnabled {
                        Button {
                            autoCapture.setPaused(!autoCaptureSettings.isPaused)
                        } label: {
                            Text(autoCaptureSettings.isPaused ? "Resume capture" : "Pause capture")
                                .frame(minHeight: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
                        .buddyHelp("Pause or resume your selected capture sources together")
                    }
                    Button { showExcludedApplications = true } label: {
                        Text("Excluded applications…").frame(minHeight: 32).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(accent)
                    Text("Existing clipboard contents and screenshots are never imported when capture starts. DaBin and common password managers are excluded by default. Captures stay in your local archive.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .daBinTutorialAnchor(.automaticCapture)
                Divider()
                ClipboardRetentionSettings(service: state.clipboardRetention, store: state.store)
                Divider()
                quickAccessSection
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Toggle("Dark mode", isOn: Binding(
                        get: { theme.darkModeEnabled },
                        set: { theme.setDarkMode($0) }
                    ))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 14))
                    .accessibilityHint("Switches DaBin between dark and light appearance")
                    Toggle("Show tooltips", isOn: Binding(
                        get: { theme.showTooltips },
                        set: { theme.setShowTooltips($0) }
                    ))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 14))
                    .accessibilityIdentifier("settings-show-tooltips")
                    .accessibilityHint("Shows names when hovering over icons; accessibility labels are always available")
                    Text("Show helpful labels when hovering over controls. Turn off to hide them; accessibility labels stay available.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Transparency").font(.system(size: 14))
                            Spacer()
                            Text("\(Int((theme.boardOpacity * 100).rounded()))% opacity")
                                .font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        Slider(value: Binding(
                            get: { theme.boardOpacity },
                            set: { theme.setBoardOpacity($0) }
                        ), in: ThemeSettings.minimumBoardOpacity...ThemeSettings.maximumBoardOpacity, step: 0.05) {
                            Text("Background opacity")
                        } minimumValueLabel: {
                            Image(systemName: "circle.dotted").accessibilityLabel("More transparent")
                        } maximumValueLabel: {
                            Image(systemName: "circle.fill").accessibilityLabel("More solid")
                        }
                        .controlSize(.small)
                        .accessibilityValue("\(Int((theme.boardOpacity * 100).rounded())) percent opaque")
                        if reduceTransparency || colorSchemeContrast == .increased {
                            Text("macOS accessibility contrast or transparency settings are using a solid background. Your opacity preference is kept.")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Lower opacity lets the desktop show through and can make text harder to read. Cards and navigation stay solid.")
                            .font(.system(size: 14)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if theme.boardOpacity < 1 {
                            Button { theme.setBoardOpacity(1) } label: {
                                Label("Use solid background", systemImage: "circle.fill")
                                    .frame(minHeight: 32).contentShape(Rectangle())
                            }
                                .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(accent)
                                .accessibilityIdentifier("settings-solid-background")
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Theme color").font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Text(selectedName).font(.system(size: 14)).foregroundStyle(Palette.muted)
                    }
                    HStack(spacing: 8) {
                        ForEach(ThemePreset.allCases) { preset in
                            let selected = theme.selectedHex == preset.hex
                            Button { theme.select(preset) } label: {
                                Circle().fill(preset.swatch)
                                    .padding(4)
                                    .overlay {
                                        Circle().strokeBorder(selected ? accent : .clear, lineWidth: 2)
                                    }
                                    .frame(width: 28, height: 28)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .buddyHelp(preset.name)
                            .accessibilityLabel("\(preset.name) theme")
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityRemoveTraits(selected ? [] : .isSelected)
                        }
                    }
                    HStack(spacing: 8) {
                        ColorPicker("Custom color", selection: Binding(get: { theme.selection }, set: { theme.setColor($0) }), supportsOpacity: false)
                            .font(.system(size: 14)).controlSize(.small)
                            .accessibilityLabel("Custom theme color")
                        Button { theme.select(.purple) } label: {
                            Text("Reset").frame(minHeight: 32).contentShape(Rectangle())
                        }
                            .font(.system(size: 14)).buttonStyle(.plain).foregroundStyle(accent)
                            .disabled(theme.selectedHex == ThemeSettings.defaultHex)
                            .buddyHelp("Reset theme color to Purple")
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local archive").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Saved on this Mac, organized by year, month and day. Images, PDFs and supported text documents are made searchable on this Mac; recognized text is never sent to a service.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { localArchiveActions }
                        VStack(alignment: .leading, spacing: 8) { localArchiveActions }
                    }
                    .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(accent)
                    if let index = state.contentIndex, index.isBusy {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(index.pendingCount == 1
                                 ? "Making 1 capture searchable…"
                                 : "Making \(index.pendingCount) captures searchable…")
                        }
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .accessibilityElement(children: .combine)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Fetch link previews", isOn: Binding(get: { state.previews.enabled }, set: { state.setLinkPreviews($0) }))
                        .toggleStyle(.switch).controlSize(.small).font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Off by default. Turning this on contacts websites for earlier manually saved links that need previews and for new manual links. Websites receive the requested URL and your IP address. Automatically captured links never fetch previews. Links still save without previews. Turn it off to stop further preview requests.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & your data").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("No account or analytics. Your captures stay in your local archive until you remove them.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Button { showPrivacyPolicy = true } label: {
                        Label("Privacy policy & data controls", systemImage: "hand.raised")
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(accent)
                    if let url = PrivacyInformation.configuredURL(for: PrivacyInformation.supportURLKey) {
                        Link(destination: url) {
                            Text("Contact & support").frame(minHeight: 32).contentShape(Rectangle())
                        }
                            .font(.system(size: 14)).foregroundStyle(accent)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(state.reminders.visibleStatus ?? "Permission is requested when you first save a reminder. Alerts keep capture contents private.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings-reminder-feedback")
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    } label: {
                        Text("Open notification settings").frame(minHeight: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(accent)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your quiet corner").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Picker("Robot home", selection: Binding(
                        get: { robotPlacement.home },
                        set: { robotPlacement.setHome($0) }
                    )) {
                        ForEach(RobotHome.allCases) { home in Text(home.title).tag(home) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Choose whether DaBin appears from screen corners or around a built-in camera island")
                    Text(robotHomeDescription)
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Drop onto the robot, or hover over it and press ⌃V or ⌘V. Double-click opens DaBin.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                SettingsQuitSection(quitApplication: quitApplication)
            }.padding(12)
                .frame(maxWidth: 680, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.75))
                .padding(.horizontal, 12).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicySheet(dataFolder: state.store.root)
                .environment(\.daBinAccent, accent)
                .hoverTooltips()
        }
        .sheet(isPresented: $showAutoCaptureExplanation) {
            AutoCaptureExplanationSheet(channel: pendingCaptureChannel) {
                autoCaptureSettings.acknowledgePrivacyExplanation()
                showAutoCaptureExplanation = false
                let channel = pendingCaptureChannel
                DispatchQueue.main.async { enableCapture(channel) }
            } cancel: {
                showAutoCaptureExplanation = false
            }
            .environment(\.daBinAccent, accent)
            .hoverTooltips()
        }
        .sheet(isPresented: $showExcludedApplications) {
            ExcludedApplicationsSheet(settings: autoCaptureSettings)
                .environment(\.daBinAccent, accent)
                .hoverTooltips()
        }
        .onAppear { beginRequestedAutoCaptureSetup() }
    }

    @ViewBuilder
    private var localArchiveActions: some View {
        Button { state.showArchiveFolder() } label: {
            Label("Open local archive", systemImage: "folder")
                .frame(minHeight: 32).contentShape(Rectangle())
        }.accessibilityIdentifier("settings-open-local-archive")
        if let index = state.contentIndex {
            Button { state.rebuildContentIndex() } label: {
                Label("Rebuild text search", systemImage: "arrow.clockwise")
                    .frame(minHeight: 32).contentShape(Rectangle())
            }
            .disabled(index.isBusy)
            .buddyHelp(index.isBusy ? "Local text search is already running" : "Recognize text in saved images and documents again")
        }
    }

    private var needsScreenshotPermission: Bool {
        guard autoCaptureSettings.isScreenshotsEnabled else { return false }
        switch autoCapture.screenshotStatus {
        case .permissionRequired, .permissionRevoked: return true
        default: return autoCaptureSettings.screenshotFolderBookmark == nil
        }
    }

    private var autoCaptureStatusText: String {
        if case .sourceApplicationExcluded(let name) = autoCaptureSettings.status {
            return "\(autoCapture.overallStatusText) · skipping \(name)"
        }
        return autoCapture.overallStatusText
    }

    private var autoCaptureStatusColor: Color {
        if needsScreenshotPermission && !autoCaptureSettings.isPaused { return .orange }
        switch autoCaptureSettings.status {
        case .monitoring, .sourceApplicationExcluded: return accent
        case .paused: return .orange
        case .permissionRequired, .permissionRevoked, .failed: return Palette.task
        case .disabled, .ready: return Palette.muted
        }
    }

    private func chooseScreenshotFolder(enableAfterSelection: Bool) {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Folder"
        panel.message = "Choose the folder selected in macOS Screenshot Options. DaBin treats new image files there as screenshots, so use a dedicated screenshot folder."
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try autoCapture.authorizeScreenshotFolder(url)
            if enableAfterSelection {
                autoCaptureSettings.acknowledgePrivacyExplanation()
                autoCapture.setScreenshotsEnabled(true)
            }
        } catch {
            state.reportFailure("Could not authorize the screenshot folder: \(error.localizedDescription)")
        }
    }

    private func beginRequestedAutoCaptureSetup() {
        // Opening setup shows the two independent choices; it never selects a
        // source or requests folder access on the user's behalf.
        _ = state.consumeAutoCaptureSetupRequest()
    }

    private func requestCapture(_ channel: AutoCaptureChannel, enabled: Bool) {
        guard enabled else {
            switch channel {
            case .clipboard: autoCapture.setClipboardEnabled(false)
            case .screenshots: autoCapture.setScreenshotsEnabled(false)
            }
            return
        }
        if !autoCaptureSettings.hasAcknowledgedPrivacyExplanation {
            pendingCaptureChannel = channel
            showAutoCaptureExplanation = true
        } else {
            enableCapture(channel)
        }
    }

    private func enableCapture(_ channel: AutoCaptureChannel) {
        switch channel {
        case .clipboard:
            autoCapture.setClipboardEnabled(true)
        case .screenshots:
            if autoCaptureSettings.screenshotFolderBookmark == nil || needsScreenshotPermission {
                chooseScreenshotFolder(enableAfterSelection: true)
            } else {
                autoCapture.setScreenshotsEnabled(true)
            }
        }
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick access").font(.system(size: 16, weight: .semibold, design: .rounded))
            Toggle("Global shortcuts", isOn: Binding(
                get: { state.quickAccessSettings.isEnabled },
                set: { state.quickAccessSettings.setEnabled($0) }
            ))
            .toggleStyle(.switch).controlSize(.small).font(.system(size: 14))
            Picker("Search and clipboard keys", selection: Binding(
                get: { state.quickAccessSettings.shortcutStyle },
                set: { state.quickAccessSettings.setShortcutStyle($0) }
            )) {
                ForEach(GlobalShortcutStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .font(.system(size: 14)).controlSize(.small)
            Text("Search: \(state.quickAccessSettings.shortcutStyle.searchLabel) · Save clipboard: \(state.quickAccessSettings.shortcutStyle.captureLabel)")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ConfigurableShortcutAction.allCases) { action in
                HStack(spacing: 8) {
                    Text(action.title).font(.system(size: 13))
                    Spacer(minLength: 0)
                    ShortcutRecorderControl(
                        shortcut: state.quickAccessSettings.binding(for: action),
                        actionTitle: action.title,
                        identifier: action == .fullScreen ? "settings-shortcut-full-screen" : "settings-shortcut-recording",
                        onCommit: { state.quickAccessSettings.setShortcut($0, for: action) },
                        onEditingChanged: {
                            state.quickAccessSettings.isEditingShortcut = $0
                            if $0 { state.quickAccessSettings.shortcutEditError = nil }
                        },
                        onInvalidKey: {
                            state.quickAccessSettings.shortcutEditError = "Use a key with Command, Control or Option. Esc cancels."
                        }
                    ).frame(width: 126, height: 32)
                    Button {
                        _ = state.quickAccessSettings.setShortcut(nil, for: action)
                    } label: {
                        Image(systemName: "xmark.circle").frame(width: 32, height: 32)
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .disabled(state.quickAccessSettings.binding(for: action) == nil)
                        .accessibilityLabel("Disable \(action.title.lowercased()) shortcut")
                        .accessibilityIdentifier(action == .fullScreen ? "settings-shortcut-disable-full-screen" : "settings-shortcut-disable-recording")
                        .buddyHelp("Disable this shortcut")
                }
            }
            Text("Click a shortcut and press your new keys. Esc cancels. Full screen expands or restores the window. Recording uses your selected capture sources.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { state.quickAccessSettings.resetActionShortcuts() } label: {
                Text("Reset these shortcuts").frame(minHeight: 32).contentShape(Rectangle())
            }
                .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent)
                .accessibilityIdentifier("settings-shortcut-reset-actions")
            if let error = state.quickAccessSettings.shortcutEditError {
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.task)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-shortcut-edit-error")
            }
            if let error = state.quickAccessSettings.registrationError {
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.task)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Quiet mode", isOn: Binding(
                get: { state.quickAccessSettings.quietMode },
                set: { state.quickAccessSettings.setQuietMode($0) }
            ))
            .toggleStyle(.switch).controlSize(.small).font(.system(size: 14))
            Text("Open quickly and skip automatic capture celebrations.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }

    private var robotHomeDescription: String {
        switch robotPlacement.home {
        case .corners:
            return "Reach any screen corner to reveal DaBin."
        case .cameraIsland:
            if NSScreen.screens.contains(where: { CornerGeometry.cameraIslandRect(on: $0) != nil }) {
                return "Approach the camera island to meet DaBin. He follows your approach around its edges, then quietly tucks away. Displays without an island use the top-right corner."
            }
            return "No camera island is detected, so DaBin uses the top-right corner. Your choice stays ready for a compatible display."
        }
    }
}

@MainActor
private struct SettingsTutorialSection: View {
    @Environment(\.daBinAccent) private var accent
    let runTutorial: @MainActor () -> Void

    var body: some View {
        Button(action: runTutorial) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Run tutorial")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Let the robot guide you through capture, planning, search, and projects on the real interface.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(11)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.75)
        }
        .accessibilityLabel("Run DaBin tutorial")
        .accessibilityHint("Shows an animated guide over the real DaBin interface")
        .accessibilityIdentifier("settings-run-tutorial")
        .buddyHelp("Learn DaBin with the robot")
        .daBinTutorialAnchor(.settingsTutorial)
    }
}

@MainActor
struct SettingsSoftwareUpdateSection: View {
    static let title = "Get updates"
    static let accessibilityIdentifier = "settings-software-updates"
    static let checkAccessibilityLabel = "Check for DaBin updates"
    static let installAccessibilityLabel = "Download and install the DaBin update"
    static let releaseAccessibilityLabel = "View the latest DaBin release on GitHub"

    @Environment(\.daBinAccent) private var accent
    @ObservedObject var updates: SoftwareUpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(Self.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(updates.versionLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .accessibilityLabel("Installed version, \(updates.versionLabel)")
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(updates.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Update status: \(updates.message)")
            }

            if updates.isDirectChannel {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { updateButtons }
                    VStack(alignment: .leading, spacing: 7) { updateButtons }
                }
                if let release = updates.releasePageURL {
                    Link(destination: release) {
                        Label("Latest release on GitHub", systemImage: "arrow.up.right.square")
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .accessibilityLabel(Self.releaseAccessibilityLabel)
                    .buddyHelp("Open the latest DaBin release on GitHub")
                }
            }
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.background)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    @ViewBuilder
    private var updateButtons: some View {
        Button {
            updates.checkForUpdates()
        } label: {
            Text(updates.phase == .checking ? "Checking…" : "Check for updates")
                .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!updates.canCheck)
        .accessibilityLabel(Self.checkAccessibilityLabel)
        .accessibilityHint("Checks DaBin’s official GitHub release feed")
        .buddyHelp("Check GitHub for a newer DaBin release")

        if updates.canInstall {
            Button { updates.downloadAndInstall() } label: {
                Text("Download & install").frame(minHeight: 32).contentShape(Rectangle())
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(Self.installAccessibilityLabel)
                .accessibilityHint("Downloads, verifies, and opens the DaBin updater")
                .buddyHelp("Download and install this verified DaBin update")
        }

        if updates.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(updates.phase == .checking ? "Checking for updates" : "Downloading update")
        }
    }

    private var statusColor: Color {
        switch updates.phase {
        case .updateAvailable: return accent
        case .installerOpened, .upToDate: return .green
        case .failed: return Palette.task
        case .checking, .downloading: return accent
        case .idle, .storeManaged: return Palette.muted
        }
    }
}

@MainActor
struct SettingsQuitSection: View {
    static let buttonTitle = "Quit DaBin"
    static let accessibilityLabel = "Quit DaBin completely"
    static let accessibilityHint = "Stops Auto Capture and closes DaBin so it is no longer running in the background"

    let quitApplication: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Application").font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Quit DaBin to stop Auto Capture and remove the robot from every screen. Your local archive and saved reminders remain available when you open DaBin again.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive, action: quitApplication) {
                Label(Self.buttonTitle, systemImage: "power")
                    .frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Self.accessibilityLabel)
            .accessibilityHint(Self.accessibilityHint)
            .accessibilityIdentifier("settings-quit-dabin")
            .buddyHelp("Quit DaBin completely")
        }
    }
}

private enum AutoCaptureChannel {
    case clipboard
    case screenshots
}

@MainActor
private struct AutoCaptureExplanationSheet: View {
    @Environment(\.daBinAccent) private var accent
    let channel: AutoCaptureChannel
    let continueAction: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 28)).foregroundStyle(accent).accessibilityHidden(true)
            Text(channel == .clipboard ? "Turn on clipboard capture?" : "Turn on screenshot capture?")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
            Text(channel == .clipboard
                 ? "DaBin will save future copied text, links, images and files. It will not import what is already on your clipboard. Screenshot capture stays as you set it."
                 : "DaBin will save new images from a folder you choose. Existing files will not be imported. Clipboard capture stays as you set it.")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Label("Everything is stored only in DaBin’s local archive on this Mac.", systemImage: "lock.fill")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(channel == .clipboard
                 ? "DaBin and common password managers are excluded by default. You can add exclusions or pause capture at any time. No folder access is needed."
                 : "Choose the folder set in macOS Screenshot Options. DaBin treats new images there as screenshots, so use a dedicated folder. You can pause capture at any time.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not now", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(channel == .clipboard ? "Turn on clipboard capture" : "Choose screenshot folder…", action: continueAction)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 390)
    }
}

@MainActor
private struct ExcludedApplicationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var settings: AutoCaptureSettings

    private var ownBundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.dabin.mac" }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Excluded applications")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("DaBin consumes clipboard changes from these apps without reading their contents.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(settings.excludedBundleIdentifiers.sorted(), id: \.self) { identifier in
                        HStack(spacing: 9) {
                            Image(systemName: identifier == ownBundleIdentifier ? "shippingbox.fill" : "lock.app.dashed")
                                .foregroundStyle(accent).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(applicationName(for: identifier)).font(.system(size: 13, weight: .medium))
                                Text(identifier).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 6)
                            if identifier == ownBundleIdentifier {
                                Text("Always").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            } else {
                                Button {
                                    settings.setApplication(bundleIdentifier: identifier, excluded: false)
                                } label: {
                                    Image(systemName: "minus.circle").frame(width: 26, height: 26)
                                }
                                .buttonStyle(.plain).buddyHelp("Remove exclusion")
                                .accessibilityLabel("Remove \(applicationName(for: identifier)) from excluded applications")
                            }
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
                    }
                }
            }
            HStack {
                Button("Add application…", action: addApplication)
                    .buttonStyle(.plain).foregroundStyle(accent)
                Spacer()
                Button("Restore defaults") {
                    settings.replaceExcludedBundleIdentifiers(with: AutoCaptureSettings.defaultExcludedBundleIdentifiers)
                }
                .buttonStyle(.plain).foregroundStyle(accent)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(18).frame(width: 430, height: 420)
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Exclude an Application"
        panel.message = "Choose an app whose clipboard changes DaBin should ignore."
        panel.prompt = "Exclude"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        settings.setApplication(bundleIdentifier: identifier, excluded: true)
    }

    private func applicationName(for identifier: String) -> String {
        if identifier == ownBundleIdentifier { return "DaBin" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           let value = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return value
        }
        return identifier.split(separator: ".").last.map(String.init) ?? identifier
    }
}

/// Key capture exists only while this explicit Settings control owns focus.
/// DaBin's global hotkeys remain suspended until the recorded key is released.
private struct ShortcutRecorderControl: NSViewRepresentable {
    let shortcut: GlobalShortcutBinding?
    let actionTitle: String
    let identifier: String
    let onCommit: (GlobalShortcutBinding?) -> Bool
    let onEditingChanged: (Bool) -> Void
    let onInvalidKey: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(frame: .zero)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.displayTitle = shortcut?.label ?? "Set shortcut"
        button.actionTitle = actionTitle
        button.setAccessibilityIdentifier(identifier)
        button.onCommit = onCommit
        button.onEditingChanged = onEditingChanged
        button.onInvalidKey = onInvalidKey
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.cancelRecording()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var displayTitle = "Set shortcut"
    var actionTitle = "Shortcut"
    var onCommit: ((GlobalShortcutBinding?) -> Bool)?
    var onEditingChanged: ((Bool) -> Void)?
    var onInvalidKey: (() -> Void)?
    private(set) var isRecording = false
    private var pendingReleaseKey: UInt16?
    private var monitor: Any?
    private var keyWindowObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }
    // Shortcut entry is a form input, so it belongs to the native key loop
    // even when macOS limits ordinary button navigation to text fields.
    override var canBecomeKeyView: Bool {
        isEnabled && !isHiddenOrHasHiddenAncestor && window != nil
    }
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(126, size.width), height: max(32, size.height))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureButton()
    }

    private func configureButton() {
        bezelStyle = .rounded
        controlSize = .small
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(beginRecording)
        setAccessibilityHelp("Click and press a shortcut. Escape cancels; Delete clears it.")
        refreshTitle()
    }

    func refreshTitle() {
        title = isRecording ? (pendingReleaseKey == nil ? "Press shortcut…" : "Release keys…") : displayTitle
        setAccessibilityLabel("\(actionTitle) shortcut, \(title)")
    }

    @objc func beginRecording() {
        guard !isRecording, let window, window.isKeyWindow,
              window.makeFirstResponder(self) else { return }
        isRecording = true
        pendingReleaseKey = nil
        onEditingChanged?(true)
        refreshTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.isRecording, let window = self.window,
                  window.isKeyWindow, window.firstResponder === self,
                  event.windowNumber == window.windowNumber else { return event }
            return self.handleRecordingEvent(event) ? nil : event
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
    }

    /// Use AppKit's eligible key views for Tab navigation; a button's default
    /// handling can restart the window's loop instead of leaving this input.
    private func handleRecordingEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyUp {
            if pendingReleaseKey == event.keyCode { cancelRecording() }
            return true
        }
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat, pendingReleaseKey == nil else { return true }
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return true }
        if event.keyCode == UInt16(kVK_Tab) {
            let targetWindow = window
            let next = event.modifierFlags.contains(.shift) ? previousValidKeyView : nextValidKeyView
            cancelRecording()
            guard let next else { return false }
            return targetWindow?.makeFirstResponder(next) == true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty && (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
            if onCommit?(nil) == true {
                displayTitle = "Set shortcut"
                pendingReleaseKey = event.keyCode
                refreshTitle()
            }
            return true
        }
        guard let binding = GlobalShortcutBinding.from(event: event) else { onInvalidKey?(); return true }
        guard onCommit?(binding) == true else { return true }
        displayTitle = binding.label
        pendingReleaseKey = event.keyCode
        refreshTitle()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !isRecording || !handleRecordingEvent(event) { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if !isRecording || !handleRecordingEvent(event) { super.keyUp(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording, window?.firstResponder === self {
            return handleRecordingEvent(event)
        }
        return super.performKeyEquivalent(with: event)
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingReleaseKey = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
        keyWindowObserver = nil
        refreshTitle()
        onEditingChanged?(false)
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
}
