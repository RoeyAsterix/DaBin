import AppKit

/// Native macOS commands use the responder chain for editing, so text editors
/// retain standard cut/copy/paste, undo and keyboard behavior.
@MainActor
final class ApplicationMenu: NSObject {
    private let openDailyAction: () -> Void
    private let openSearchAction: () -> Void
    private let focusRobotAction: () -> Void
    private let checkForUpdatesAction: () -> Void
    private let showSettingsAction: () -> Void
    private var installedMenu: NSMenu?

    init(openDaily: @escaping () -> Void, openSearch: @escaping () -> Void,
         focusRobot: @escaping () -> Void, checkForUpdates: @escaping () -> Void = {},
         showSettings: @escaping () -> Void) {
        openDailyAction = openDaily
        openSearchAction = openSearch
        focusRobotAction = focusRobot
        checkForUpdatesAction = checkForUpdates
        showSettingsAction = showSettings
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
    }

    private func add(_ title: String, _ selector: Selector, key: String,
                     modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
    }

    @objc private func openDaily() { openDailyAction() }
    @objc private func openSearch() { openSearchAction() }
    @objc private func focusRobot() { focusRobotAction() }
    @objc private func checkForUpdates() { checkForUpdatesAction() }
    @objc private func showSettings() { showSettingsAction() }
}
