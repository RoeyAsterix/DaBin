import AppKit
import Carbon
import Foundation

@MainActor private final class QuickAccessNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("Quick access QA never asks for permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Quick access QA never schedules reminders") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor private final class FakeShortcutRegistrar: ShortcutRegistering {
    var callback: ((UInt32) -> Void)?
    var installed = 0
    var registrations: [UInt32: (UInt32, UInt32)] = [:]
    var failID: UInt32?
    func install(_ onPress: @escaping (UInt32) -> Void) -> Bool { installed += 1; callback = onPress; return true }
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard id != failID else { return false }
        registrations[id] = (keyCode, modifiers); return true
    }
    func removeAll() { registrations.removeAll() }
    func uninstall() { removeAll(); callback = nil }
}

@main struct QuickAccessTests {
    /// Exercise the registered Search callback against the real navigation
    /// model without installing system hotkeys, opening a window or reading
    /// the user's clipboard.
    @MainActor private static func searchNavigationCases(
        expect: (Bool, String) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinQuickAccessSearchQA-\(UUID())")
        let name = "DaBinQuickAccessSearchQA.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        let pasteboard = NSPasteboard(name: .init(name))
        let clipboardRevision = pasteboard.changeCount
        defer {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureStore(root: root)
        let today = Date(), earlier = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        let alpha = try store.capture(text: "Shortcut archive beacon", at: today, projectName: "Alpha")[0]
        let beta = try store.capture(text: "Shortcut archive beacon", at: earlier, projectName: "Beta")[0]
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Quick access QA never reads the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: QuickAccessNotifications()),
            autoCapture: auto, captureClipboard: CaptureClipboardService(pasteboard: pasteboard))
        auto.projectProvider = { [weak state] in state?.libraryProject }
        defer {
            auto.shutdown(); previews.shutdown()
            state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
        }
        let registrar = FakeShortcutRegistrar()
        let shortcuts = GlobalShortcutService(settings: QuickAccessSettings(defaults: defaults), registrar: registrar,
            systemShortcuts: { [] },
            search: { state.performSearchCommand() }, capture: { fatalError("Search QA must not dispatch capture") })
        shortcuts.start()
        defer { shortcuts.stop() }
        state.libraryProject = "Alpha"
        state.workspace.selectedCaptureID = alpha.id
        state.workspace.sourceApplication = "Editor"
        state.route = .library
        state.filter = .tasks
        state.query = "shortcut archive beacon"
        state.searchProject = "Alpha"; state.searchSource = "Editor"
        state.setSearchDay(today); state.showSearchContext = true
        registrar.callback?(1)
        try expect(state.route == .search && state.filter == .all && state.searchScope == .all
            && state.searchProject == nil && !state.searchUnfiledOnly && state.searchSource == nil && !state.showSearchContext,
            "Registered global Search clears inherited project, date, source, type and context")
        let matches = Set(state.searchGroups.flatMap(\.entries).filter(\.isMatch).map { $0.capture.id })
        try expect(matches == [alpha.id, beta.id] && state.autoCapture.projectProvider() == "Alpha",
            "The shortcut finds an earlier client item while keeping the working capture destination")
        state.selectSearchProject("Beta"); state.filter = .text; state.setSearchDay(earlier)
        state.searchDateAnchor = beta.captureDay
        let focus = state.globalSearchFocusRequest
        registrar.callback?(1)
        try expect(state.globalSearchFocusRequest == focus + 1 && state.searchProject == "Beta"
            && state.filter == .text && state.searchScope == .day(beta.captureDay) && state.searchDateAnchor == beta.captureDay,
            "A repeated global shortcut refocuses the same Search and preserves deliberate refinements")
        state.back()
        try expect(state.route == .library && state.filter == .tasks && state.libraryProject == "Alpha"
            && state.workspace.selectedCaptureID == alpha.id && state.workspace.sourceApplication == "Editor",
            "Search Back restores Projects selection, content filter and source preference")
        state.openNewTask()
        state.newTaskDraft.text = "Unfinished client follow-up"
        let destination = state.newTaskDraft.destination
        registrar.callback?(1)
        try expect(state.route == .search && state.searchProject == nil && state.filter == .all
            && state.newTaskDraft.text == "Unfinished client follow-up" && state.newTaskDraft.destination == destination,
            "Fresh shortcut Search above a task composer preserves its pending text and capture destination")
        state.back()
        try expect(state.route == .newTask && state.newTaskDraft.destination == destination
            && state.newTaskDraft.text == "Unfinished client follow-up",
            "Back returns to the original task composer without a Search loop")
        try expect(Set(store.captures.map(\.id)) == [alpha.id, beta.id] && pasteboard.changeCount == clipboardRevision,
            "Search shortcut navigation changes neither saved items nor the isolated clipboard")
    }

    @MainActor private static func reservedShortcutCases(expect: (Bool, String) throws -> Void) throws {
        let name = "DaBinReservedShortcutTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = QuickAccessSettings(defaults: defaults)
        try expect(settings.shortcutStyle == .controlOptionShift
            && defaults.object(forKey: QuickAccessSettings.styleKey) == nil,
            "Missing shortcut preference defaults to Shift without writing a preference")
        defaults.set("unsupported", forKey: QuickAccessSettings.styleKey)
        try expect(QuickAccessSettings(defaults: defaults).shortcutStyle == .controlOptionShift,
            "An unsupported saved style uses the Shift fallback")
        settings.setShortcutStyle(.controlOption)
        try expect(QuickAccessSettings(defaults: defaults).shortcutStyle == .controlOption,
            "An explicitly saved original shortcut remains selected")
        settings.setShortcutStyle(.controlOptionShift)
        try expect(QuickAccessSettings(defaults: defaults).shortcutStyle == .controlOptionShift,
            "An explicitly saved Shift shortcut remains selected")

        let registrar = FakeShortcutRegistrar()
        let modifiers = GlobalShortcutStyle.controlOptionShift.modifiers
        var reserved: [SystemGlobalShortcut]? = [
            .init(keyCode: UInt32(kVK_Space), modifiers: modifiers, isEnabled: false),
            .init(keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers, isEnabled: true),
            .init(keyCode: UInt32(kVK_Space), modifiers: GlobalShortcutStyle.controlOption.modifiers, isEnabled: true)
        ]
        var searches = 0, captures = 0
        let service = GlobalShortcutService(settings: settings, registrar: registrar,
            systemShortcuts: { reserved }, search: { searches += 1 }, capture: { captures += 1 })
        service.start()
        defer { service.stop() }
        try expect(service.isRegistered && registrar.registrations.count == 2,
            "Disabled reservations and unrelated keys or modifiers allow both shortcuts")
        for code in [UInt32(kVK_Space), UInt32(kVK_ANSI_V)] {
            reserved = [.init(keyCode: code, modifiers: modifiers, isEnabled: true)]
            settings.setEnabled(false); settings.setEnabled(true)
            registrar.callback?(1); registrar.callback?(2)
            try expect(!service.isRegistered && registrar.registrations.isEmpty
                && settings.registrationError == "A shortcut is unavailable or used by another app. Choose the other key combination."
                && searches == 0 && captures == 0,
                "An enabled system reservation for key \(code) reports a conflict and prevents both actions")
        }
        reserved = nil
        settings.setEnabled(false); settings.setEnabled(true)
        registrar.callback?(1); registrar.callback?(2)
        try expect(!service.isRegistered && registrar.registrations.isEmpty
            && settings.registrationError != nil && searches == 0 && captures == 0,
            "An unavailable system shortcut read reports failure and prevents dispatch")
        reserved = []
        settings.setEnabled(false); settings.setEnabled(true)
        registrar.callback?(1); registrar.callback?(2)
        try expect(service.isRegistered && registrar.registrations.count == 2
            && settings.registrationError == nil && searches == 1 && captures == 1,
            "Successful reservation verification restores both shortcuts and clears the error")
    }

    @MainActor static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "QuickAccessTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let name = "DaBinQuickAccessTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = QuickAccessSettings(defaults: defaults)
        let registrar = FakeShortcutRegistrar()
        var searches = 0, captures = 0
        let service = GlobalShortcutService(settings: settings, registrar: registrar, systemShortcuts: { [] },
            search: { searches += 1 }, capture: { captures += 1 })
        try expect(registrar.registrations.isEmpty, "Construction registers no system key handlers")
        service.start(); service.start()
        try expect(registrar.installed == 1 && registrar.registrations.count == 2, "Start is idempotent with two explicit chords")
        registrar.callback?(1); registrar.callback?(2); registrar.callback?(999)
        try expect(searches == 1 && captures == 1, "Only registered actions dispatch")
        let originalModifiers = registrar.registrations[1]!.1
        settings.setShortcutStyle(.controlOption)
        try expect(registrar.registrations[1]!.1 != originalModifiers && registrar.registrations.count == 2, "Changing chord replaces both old registrations")
        settings.setEnabled(false)
        registrar.callback?(1)
        try expect(registrar.registrations.isEmpty && searches == 1, "Disabled shortcuts do not dispatch stale events")
        registrar.failID = 2
        settings.setEnabled(true)
        try expect(!service.isRegistered && registrar.registrations.isEmpty && settings.registrationError != nil, "Partial registration rolls back and reports the collision")
        registrar.callback?(1)
        try expect(searches == 1, "Failed registration cannot dispatch")
        registrar.failID = nil
        settings.setShortcutStyle(.controlOption)
        try expect(service.isRegistered && settings.registrationError == nil, "A valid new combination recovers")
        settings.setQuietMode(true)
        let reopened = QuickAccessSettings(defaults: defaults)
        try expect(reopened.isEnabled && reopened.quietMode && reopened.shortcutStyle == .controlOption, "Preferences survive relaunch")
        let lateCallback = registrar.callback
        service.stop(); service.stop(); lateCallback?(2)
        try expect(!service.isStarted && registrar.registrations.isEmpty && captures == 1, "Shutdown removes handlers and ignores late dispatch")
        try searchNavigationCases(expect: expect)
        try reservedShortcutCases(expect: expect)
        print("PASS: \(checks) quick access checks")
    }
}
