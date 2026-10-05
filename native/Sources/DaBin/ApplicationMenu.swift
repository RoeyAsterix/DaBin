import AppKit
import Combine

/// Native macOS commands use the responder chain for editing, so text editors
/// retain standard cut/copy/paste, undo and keyboard behavior.
@MainActor
final class ApplicationMenu: NSObject, NSMenuItemValidation {
    private let openDailyAction: () -> Void
    private let openSearchAction: () -> Void
    private let focusRobotAction: () -> Void
    private let checkForUpdatesAction: () -> Void
    private let showSettingsAction: () -> Void
    private weak var autoCapture: AutoCaptureService?
    private weak var workspaceZoom: WorkspaceZoomSettings?
    private weak var zoomPercentageItem: NSMenuItem?
    private var installedMenu: NSMenu?
    private weak var autoCaptureItem: NSMenuItem?
    private var subscriptions = Set<AnyCancellable>()

    init(openDaily: @escaping () -> Void, openSearch: @escaping () -> Void,
         focusRobot: @escaping () -> Void, checkForUpdates: @escaping () -> Void = {},
         showSettings: @escaping () -> Void, autoCapture: AutoCaptureService? = nil,
         workspaceZoom: WorkspaceZoomSettings? = nil) {
        openDailyAction = openDaily
        openSearchAction = openSearch
        focusRobotAction = focusRobot
        checkForUpdatesAction = checkForUpdates
        showSettingsAction = showSettings
        self.autoCapture = autoCapture
        self.workspaceZoom = workspaceZoom
    }

    func install() {
        guard installedMenu == nil else { return }
        let menu = NSMenu()
        let appRoot = menu.addItem(withTitle: "DaBin", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "DaBin")
        appMenu.addItem(withTitle: "About DaBin", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        #if DABIN_DIRECT_UPDATES
        add("Check for Updates…", #selector(checkForUpdates), key: "", to: appMenu)
        #endif
        appMenu.addItem(.separator())
        add("Open DaBin", #selector(openDaily), key: "o", to: appMenu)
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
        let viewRoot = menu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Back", action: #selector(DailyCapturePanel.navigateBack(_:)), keyEquivalent: "[")
        view.addItem(withTitle: "Forward", action: #selector(DailyCapturePanel.navigateForward(_:)), keyEquivalent: "]")
        view.addItem(.separator())
        zoomPercentageItem = view.addItem(withTitle: "Workspace Zoom: \(workspaceZoom?.percentage ?? 100)%", action: nil, keyEquivalent: "")
        add("Zoom Workspace In", #selector(zoomWorkspaceIn), key: "", to: view)
        add("Zoom Workspace Out", #selector(zoomWorkspaceOut), key: "", to: view)
        add("Reset Workspace Zoom", #selector(resetWorkspaceZoom), key: "", to: view)
        // Generic zoom keys are handled after document/editor first refusal at
        // the content window. Explicit menu commands never target a document.
        viewRoot.submenu = view
        if let workspaceZoom {
            workspaceZoom.$factor.sink { [weak self] factor in
                self?.zoomPercentageItem?.title = "Workspace Zoom: \(Int((factor * 100).rounded()))%"
            }.store(in: &subscriptions)
        }
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

    private var workspacePanel: DailyCapturePanel? {
        NSApp.windows.compactMap { $0 as? DailyCapturePanel }.first { $0.isVisible }
    }
    @objc private func zoomWorkspaceIn() { workspacePanel?.dispatch(.zoomIn) }
    @objc private func zoomWorkspaceOut() { workspacePanel?.dispatch(.zoomOut) }
    @objc private func resetWorkspaceZoom() { workspacePanel?.dispatch(.resetZoom) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(zoomWorkspaceIn): return workspacePanel?.canPerformWorkspaceCommand(.zoomIn) == true
        case #selector(zoomWorkspaceOut): return workspacePanel?.canPerformWorkspaceCommand(.zoomOut) == true
        case #selector(resetWorkspaceZoom): return workspacePanel?.canPerformWorkspaceCommand(.resetZoom) == true
        case #selector(toggleAutoCapturePause): return autoCapture?.settings.isEnabled == true
        default: return true
        }
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
