import AppKit
import Combine

/// A compact, persistent indication that DaBin is running. The status item is
/// intentionally menu-only: opening it does not activate DaBin or take focus
/// from the application the user is working in.
@MainActor
final class StatusBarController: NSObject {
    enum Indicator: Equatable {
        case off
        case enabled
        case paused
        case attention

        var symbolName: String {
            switch self {
            case .off: return "archivebox"
            case .enabled: return "archivebox.fill"
            case .paused: return "pause.circle.fill"
            case .attention: return "exclamationmark.triangle.fill"
            }
        }
    }

    struct Presentation: Equatable {
        let indicator: Indicator
        let statusTitle: String

        var accessibilityValue: String {
            statusTitle.replacingOccurrences(of: "Auto Capture: ", with: "")
        }

        static func make(enabled: Bool, paused: Bool, status: AutoCaptureStatus) -> Presentation {
            guard enabled else {
                return Presentation(indicator: .off, statusTitle: "Auto Capture: Off")
            }
            if paused || status == .paused {
                return Presentation(indicator: .paused, statusTitle: "Auto Capture: Paused")
            }
            switch status {
            case .permissionRequired:
                return Presentation(indicator: .attention,
                                    statusTitle: "Auto Capture: Choose a screenshot folder")
            case .permissionRevoked:
                return Presentation(indicator: .attention,
                                    statusTitle: "Auto Capture: Permission needs attention")
            case .failed:
                return Presentation(indicator: .attention,
                                    statusTitle: "Auto Capture: Needs attention")
            case .sourceApplicationExcluded(let name):
                return Presentation(indicator: .enabled,
                                    statusTitle: "Auto Capture: Skipping \(name)")
            case .disabled, .ready:
                return Presentation(indicator: .enabled, statusTitle: "Auto Capture: Ready")
            case .monitoring:
                return Presentation(indicator: .enabled, statusTitle: "Auto Capture: Enabled")
            case .paused:
                return Presentation(indicator: .paused, statusTitle: "Auto Capture: Paused")
            }
        }
    }

    private let openDailyAction: () -> Void
    private let showSettingsAction: () -> Void
    private let quitAction: () -> Void
    private let autoCapture: AutoCaptureService
    private let statusBar: NSStatusBar
    private var subscriptions = Set<AnyCancellable>()

    private(set) var statusItem: NSStatusItem?
    private(set) var statusMenuItem: NSMenuItem?
    private(set) var pauseMenuItem: NSMenuItem?
    private(set) var presentation: Presentation

    init(openDaily: @escaping () -> Void,
         showSettings: @escaping () -> Void,
         quit: @escaping () -> Void,
         autoCapture: AutoCaptureService,
         statusBar: NSStatusBar = .system) {
        openDailyAction = openDaily
        showSettingsAction = showSettings
        quitAction = quit
        self.autoCapture = autoCapture
        self.statusBar = statusBar
        presentation = Presentation.make(enabled: autoCapture.settings.isEnabled,
                                         paused: autoCapture.settings.isPaused,
                                         status: autoCapture.settings.status)
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }
        let item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        let menu = NSMenu(title: "DaBin")
        add("Open Daily", #selector(openDaily), to: menu)
        menu.addItem(.separator())
        let status = menu.addItem(withTitle: presentation.statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        pauseMenuItem = add("Pause Auto Capture", #selector(toggleAutoCapturePause), to: menu)
        menu.addItem(.separator())
        add("Settings…", #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("Quit DaBin", #selector(quitDaBin), to: menu)
        item.menu = menu
        statusItem = item

        let settings = autoCapture.settings
        Publishers.CombineLatest3(settings.$isEnabled, settings.$isPaused, settings.$status)
            .sink { [weak self] enabled, paused, status in
                self?.refresh(enabled: enabled, paused: paused, status: status)
            }
            .store(in: &subscriptions)
        refresh(enabled: settings.isEnabled, paused: settings.isPaused, status: settings.status)
    }

    func uninstall() {
        guard let item = statusItem else { return }
        subscriptions.removeAll()
        item.menu = nil
        statusBar.removeStatusItem(item)
        statusItem = nil
        statusMenuItem = nil
        pauseMenuItem = nil
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refresh(enabled: Bool, paused: Bool, status: AutoCaptureStatus) {
        let next = Presentation.make(enabled: enabled, paused: paused, status: status)
        presentation = next
        statusMenuItem?.title = next.statusTitle
        pauseMenuItem?.isHidden = !enabled
        pauseMenuItem?.title = paused ? "Resume Auto Capture" : "Pause Auto Capture"

        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: next.indicator.symbolName,
                            accessibilityDescription: next.accessibilityValue)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "DaBin — \(next.accessibilityValue)"
        button.setAccessibilityLabel("DaBin menu")
        button.setAccessibilityValue(next.accessibilityValue)
        button.setAccessibilityHelp("Open DaBin controls and view Auto Capture status")
    }

    @objc private func openDaily() { openDailyAction() }
    @objc private func showSettings() { showSettingsAction() }
    @objc private func quitDaBin() { quitAction() }
    @objc private func toggleAutoCapturePause() {
        guard autoCapture.settings.isEnabled else { return }
        autoCapture.setPaused(!autoCapture.settings.isPaused)
    }
}
