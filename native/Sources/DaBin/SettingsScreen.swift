import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var theme: ThemeSettings
    @ObservedObject private var updates: SoftwareUpdateService
    @ObservedObject private var robotPlacement: RobotPlacementSettings
    @ObservedObject private var autoCapture: AutoCaptureService
    @ObservedObject private var autoCaptureSettings: AutoCaptureSettings
    @State private var showPrivacyPolicy = false
    @State private var showAutoCaptureExplanation = false
    @State private var showExcludedApplications = false

    init(state: AppState, theme: ThemeSettings) {
        self.state = state
        self.theme = theme
        updates = state.updates
        robotPlacement = state.robotPlacement
        autoCapture = state.autoCapture
        autoCaptureSettings = state.autoCapture.settings
    }

    private var selectedName: String {
        ThemePreset.allCases.first(where: { $0.hex == theme.selectedHex })?.name ?? "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Capture").font(.system(size: 14, weight: .medium))
                    Toggle("Auto Capture", isOn: Binding(
                        get: { autoCaptureSettings.isEnabled },
                        set: { requested in
                            if requested {
                                if !autoCaptureSettings.hasAcknowledgedPrivacyExplanation {
                                    showAutoCaptureExplanation = true
                                } else if autoCaptureSettings.screenshotFolderBookmark == nil {
                                    DispatchQueue.main.async { chooseScreenshotFolder(enableAfterSelection: true) }
                                } else {
                                    autoCapture.setEnabled(true)
                                }
                            } else {
                                autoCapture.setEnabled(false)
                            }
                        }
                    ))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 13, weight: .medium))
                    Text("Automatically save screenshots and copied content to DaBin.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        Circle().fill(autoCaptureStatusColor).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(autoCaptureStatusText).font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    if let folder = autoCaptureSettings.screenshotFolderDisplayName {
                        Label("Screenshots: \(folder)", systemImage: "folder")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    if autoCaptureSettings.isEnabled {
                        HStack(spacing: 14) {
                            Button(autoCaptureSettings.isPaused ? "Resume Auto Capture" : "Pause Auto Capture") {
                                autoCapture.setPaused(!autoCaptureSettings.isPaused)
                            }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                            if needsScreenshotPermission {
                                Button("Choose screenshot folder…") {
                                    chooseScreenshotFolder(enableAfterSelection: false)
                                }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                            }
                        }
                    }
                    Button("Excluded applications…") { showExcludedApplications = true }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                    Text("DaBin and common password managers are excluded by default. Copied content and screenshot copies stay in your local archive and are not shared.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance").font(.system(size: 14, weight: .medium))
                    Toggle("Dark mode", isOn: Binding(
                        get: { theme.darkModeEnabled },
                        set: { theme.setDarkMode($0) }
                    ))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 13))
                    .accessibilityHint("Switches DaBin between dark and light appearance")
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Transparency").font(.system(size: 13))
                            Spacer()
                            Text("\(Int((theme.boardOpacity * 100).rounded()))% opacity")
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
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
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Software updates").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(updates.versionLabel).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Text(updates.message)
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if updates.isDirectChannel {
                        HStack(spacing: 14) {
                            Button(updates.phase == .checking ? "Checking…" : "Check for updates") {
                                updates.checkForUpdates()
                            }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                            .disabled(!updates.canCheck)
                            if updates.canInstall {
                                Button("Download & install") { updates.downloadAndInstall() }
                                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                            }
                            if updates.isBusy { ProgressView().controlSize(.small) }
                        }
                        if let release = updates.releasePageURL {
                            Link("View release on GitHub", destination: release)
                                .font(.system(size: 12)).foregroundStyle(accent)
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Theme color").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(selectedName).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    HStack(spacing: 10) {
                        ForEach(ThemePreset.allCases) { preset in
                            let selected = theme.selectedHex == preset.hex
                            Button { theme.select(preset) } label: {
                                Circle().fill(preset.swatch)
                                    .padding(4)
                                    .overlay {
                                        Circle().strokeBorder(selected ? accent : .clear, lineWidth: 2)
                                    }
                                    .frame(width: 28, height: 28)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                            .accessibilityLabel("\(preset.name) theme")
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityRemoveTraits(selected ? [] : .isSelected)
                        }
                    }
                    HStack(spacing: 12) {
                        ColorPicker("Custom color", selection: Binding(get: { theme.selection }, set: { theme.setColor($0) }), supportsOpacity: false)
                            .font(.system(size: 12)).controlSize(.small)
                            .accessibilityLabel("Custom theme color")
                        Button("Reset") { theme.select(.purple) }
                            .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent)
                            .disabled(theme.selectedHex == ThemeSettings.defaultHex)
                            .help("Reset theme color to Purple")
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local archive").font(.system(size: 14, weight: .medium))
                    Text("Saved on this Mac, organized by year, month and day. Each capture keeps its content, comments and reminder together.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Button { state.showArchiveFolder() } label: { Label("Open local archive", systemImage: "folder") }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Fetch link previews", isOn: Binding(get: { state.previews.enabled }, set: { state.setLinkPreviews($0) }))
                        .toggleStyle(.switch).controlSize(.small).font(.system(size: 14, weight: .medium))
                    Text("Off by default. Turning this on contacts websites for earlier saved links that need previews and for new links. Websites receive the requested URL and your IP address. Links still save without previews. Turn it off to stop further preview requests.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & your data").font(.system(size: 14, weight: .medium))
                    Text("No account or analytics. Your captures stay in your local archive until you remove them.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Button { showPrivacyPolicy = true } label: {
                        Label("Privacy policy & data controls", systemImage: "hand.raised")
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                    if let url = PrivacyInformation.configuredURL(for: PrivacyInformation.supportURLKey) {
                        Link("Contact & support", destination: url)
                            .font(.system(size: 12)).foregroundStyle(accent)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications").font(.system(size: 14, weight: .medium))
                    Text(state.reminders.status ?? "Permission is requested when you first save a reminder. Alerts keep capture contents private.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Button("Open notification settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your quiet corner").font(.system(size: 14, weight: .medium))
                    Picker("Robot home", selection: Binding(
                        get: { robotPlacement.home },
                        set: { robotPlacement.setHome($0) }
                    )) {
                        ForEach(RobotHome.allCases) { home in Text(home.title).tag(home) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Choose whether DaBin appears from screen corners or below a built-in camera island")
                    Text(robotHomeDescription)
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Drop onto the robot, or hover over it and press ⌃V or ⌘V. Double-click opens Daily.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 16).padding(.bottom, 20)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicySheet(dataFolder: state.store.root)
                .environment(\.daBinAccent, accent)
        }
        .sheet(isPresented: $showAutoCaptureExplanation) {
            AutoCaptureExplanationSheet {
                showAutoCaptureExplanation = false
                DispatchQueue.main.async { chooseScreenshotFolder(enableAfterSelection: true) }
            } cancel: {
                showAutoCaptureExplanation = false
            }
            .environment(\.daBinAccent, accent)
        }
        .sheet(isPresented: $showExcludedApplications) {
            ExcludedApplicationsSheet(settings: autoCaptureSettings)
                .environment(\.daBinAccent, accent)
        }
    }

    private var needsScreenshotPermission: Bool {
        switch autoCaptureSettings.status {
        case .permissionRequired, .permissionRevoked: return true
        default: return false
        }
    }

    private var autoCaptureStatusText: String {
        switch autoCaptureSettings.status {
        case .disabled: return "Off"
        case .paused: return "Paused · existing captures remain"
        case .ready: return "Enabled · ready"
        case .monitoring: return "Enabled · monitoring future copies and screenshots"
        case .permissionRequired: return "Enabled · choose a screenshot folder"
        case .permissionRevoked: return "Enabled · screenshot folder permission was revoked"
        case .sourceApplicationExcluded(let name): return "Enabled · skipping \(name)"
        case .failed(let message): return "Needs attention · \(message)"
        }
    }

    private var autoCaptureStatusColor: Color {
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
                autoCapture.setEnabled(true)
            }
        } catch {
            state.reportFailure("Could not authorize the screenshot folder: \(error.localizedDescription)")
        }
    }

    private var robotHomeDescription: String {
        switch robotPlacement.home {
        case .corners:
            return "Reach any screen corner to reveal DaBin."
        case .cameraIsland:
            if NSScreen.screens.contains(where: { CornerGeometry.cameraIslandRect(on: $0) != nil }) {
                return "Move the pointer to the built-in camera island and DaBin peeks out below it. Displays without an island keep their screen corners."
            }
            return "No camera island is currently detected, so DaBin keeps using screen corners. Your choice stays ready for a compatible display."
        }
    }
}

@MainActor
private struct AutoCaptureExplanationSheet: View {
    @Environment(\.daBinAccent) private var accent
    let continueAction: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 28)).foregroundStyle(accent).accessibilityHidden(true)
            Text("Turn on Auto Capture?")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
            Text("DaBin will watch future clipboard changes and new screenshots in a folder you choose. It will not import what is already on your clipboard.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Label("Everything is stored only in DaBin’s local archive on this Mac.", systemImage: "lock.fill")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("macOS folder access is requested next so DaBin can notice new images saved there. Use a dedicated screenshot folder. DaBin does not share copied or captured content with anyone.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not now", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose screenshot folder…", action: continueAction)
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
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(settings.excludedBundleIdentifiers.sorted(), id: \.self) { identifier in
                        HStack(spacing: 9) {
                            Image(systemName: identifier == ownBundleIdentifier ? "shippingbox.fill" : "lock.app.dashed")
                                .foregroundStyle(accent).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(applicationName(for: identifier)).font(.system(size: 12, weight: .medium))
                                Text(identifier).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 6)
                            if identifier == ownBundleIdentifier {
                                Text("Always").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            } else {
                                Button {
                                    settings.setApplication(bundleIdentifier: identifier, excluded: false)
                                } label: {
                                    Image(systemName: "minus.circle").frame(width: 26, height: 26)
                                }
                                .buttonStyle(.plain).help("Remove exclusion")
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
            .font(.system(size: 12, weight: .medium))
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
