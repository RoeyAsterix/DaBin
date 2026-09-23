import AppKit
import SwiftUI

@MainActor
struct SettingsScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var theme: ThemeSettings
    @ObservedObject private var updates: SoftwareUpdateService
    @State private var showPrivacyPolicy = false

    init(state: AppState, theme: ThemeSettings) {
        self.state = state
        self.theme = theme
        updates = state.updates
    }

    private var selectedName: String {
        ThemePreset.allCases.first(where: { $0.hex == theme.selectedHex })?.name ?? "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                    Text("Reach any screen corner to reveal DaBin. Drop onto the robot, or hover over it and press ⌃V or ⌘V. Double-click opens Daily.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 16).padding(.bottom, 20)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicySheet(dataFolder: state.store.root)
                .environment(\.daBinAccent, accent)
        }
    }
}
