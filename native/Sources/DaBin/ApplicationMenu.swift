import AppKit
import Combine

/// Native macOS commands use the responder chain for editing, so text editors
/// retain standard cut/copy/paste, undo and keyboard behavior.
@MainActor
final class ApplicationMenu: NSObject {
    private let openDailyAction: () -> Void
    private let openSearchAction: () -> Void
    private let focusRobotAction: () -> Void
    private let checkForUpdatesAction: () -> Void
    private let showSettingsAction: () -> Void
    private weak var autoCapture: AutoCaptureService?
    private var installedMenu: NSMenu?
    private weak var autoCaptureItem: NSMenuItem?
    private var subscriptions = Set<AnyCancellable>()

    init(openDaily: @escaping () -> Void, openSearch: @escaping () -> Void,
         focusRobot: @escaping () -> Void, checkForUpdates: @escaping () -> Void = {},
         showSettings: @escaping () -> Void, autoCapture: AutoCaptureService? = nil) {
        openDailyAction = openDaily
        openSearchAction = openSearch
        focusRobotAction = focusRobot
        checkForUpdatesAction = checkForUpdates
        showSettingsAction = showSettings
        self.autoCapture = autoCapture
    }

    func install() {
        guard installedMenu == nil else { return }
        let menu = NSMenu()
        let appRoot = menu.addItem(withTitle: "DaBin", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "DaBin")
        appMenu.addItem(withTitle: "About DaBin", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        add("Check for Updates…", #selector(checkForUpdates), key: "", to: appMenu)
        appMenu.addItem(.separator())
        add("Open Daily", #selector(openDaily), key: "o", to: appMenu)
        add("Focus robot for paste", #selector(focusRobot), key: "v", modifiers: [.command, .shift], to: appMenu)
        add("Search", #selector(openSearch), key: "k", to: appMenu)
        autoCaptureItem = add("Auto Capture Off", #selector(toggleAutoCapturePause), key: "", to: appMenu)
        refreshAutoCaptureItem()
        if let autoCapture {
            autoCapture.settings.$isEnabled.combineLatest(autoCapture.settings.$isPaused)
                .sink { [weak self] _, _ in self?.refreshAutoCaptureItem() }
                .store(in: &subscriptions)
            autoCapture.$isRunning.sink { [weak self] _ in self?.refreshAutoCaptureItem() }
                .store(in: &subscriptions)
        }
        appMenu.addItem(.separator())
        add("Settings…", #selector(showSettings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DaBin", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DaBin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appRoot.submenu = appMenu

        let editRoot = menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = edit
        installedMenu = menu
        NSApp.mainMenu = menu
    }

    func uninstall() {
        if let installedMenu, NSApp.mainMenu === installedMenu { NSApp.mainMenu = nil }
        installedMenu = nil
        autoCaptureItem = nil
        subscriptions.removeAll()
    }

    @discardableResult private func add(_ title: String, _ selector: Selector, key: String,
                                        modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func openDaily() { openDailyAction() }
    @objc private func openSearch() { openSearchAction() }
    @objc private func focusRobot() { focusRobotAction() }
    @objc private func checkForUpdates() { checkForUpdatesAction() }
    @objc private func showSettings() { showSettingsAction() }
    @objc private func toggleAutoCapturePause() {
        guard let autoCapture, autoCapture.settings.isEnabled else { return }
        autoCapture.setPaused(!autoCapture.settings.isPaused)
        refreshAutoCaptureItem()
    }

    private func refreshAutoCaptureItem() {
        guard let item = autoCaptureItem else { return }
        guard let autoCapture, autoCapture.settings.isEnabled else {
            item.title = "Auto Capture Off"
            item.isEnabled = false
            return
        }
        item.isEnabled = true
        item.title = autoCapture.settings.isPaused ? "Resume Auto Capture" : "Pause Auto Capture"
    }
}
