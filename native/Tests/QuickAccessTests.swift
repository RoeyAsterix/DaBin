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
        let shortcuts = GlobalShortcutService(settings: QuickAccessSettings(defaults: defaults, systemShortcuts: { [] }), registrar: registrar,
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
        let settings = QuickAccessSettings(defaults: defaults, systemShortcuts: { [] })
        try expect(settings.shortcutStyle == .controlOption
            && defaults.object(forKey: QuickAccessSettings.styleKey) == nil,
            "Missing shortcut preference retains the original modifiers without writing a preference")
        defaults.set("unsupported", forKey: QuickAccessSettings.styleKey)
        try expect(QuickAccessSettings(defaults: defaults, systemShortcuts: { [] }).shortcutStyle == .controlOption,
            "An unsupported saved style uses the original modifier fallback")
        settings.setShortcutStyle(.controlOption)
        try expect(QuickAccessSettings(defaults: defaults, systemShortcuts: { [] }).shortcutStyle == .controlOption,
            "An explicitly saved original shortcut remains selected")
        settings.setShortcutStyle(.controlOptionShift)
        try expect(QuickAccessSettings(defaults: defaults, systemShortcuts: { [] }).shortcutStyle == .controlOptionShift,
            "An explicitly saved Shift shortcut remains selected")
        try expect(GlobalShortcutStyle.controlOption.searchLabel == "⌃⌥K"
            && GlobalShortcutStyle.controlOptionShift.searchLabel == "⌃⌥⇧K"
            && GlobalShortcutStyle.controlOption.captureLabel == "⌃⌥V"
            && GlobalShortcutStyle.controlOptionShift.captureLabel == "⌃⌥⇧V",
            "Both styles advertise K for Search and preserve V for clipboard capture")

        let registrar = FakeShortcutRegistrar()
        let modifiers = GlobalShortcutStyle.controlOptionShift.modifiers
        var reserved: [SystemGlobalShortcut]? = [
            .init(keyCode: UInt32(kVK_ANSI_K), modifiers: modifiers, isEnabled: false),
            .init(keyCode: UInt32(kVK_ANSI_C), modifiers: modifiers, isEnabled: true),
            .init(keyCode: UInt32(kVK_ANSI_K), modifiers: GlobalShortcutStyle.controlOption.modifiers, isEnabled: true),
            .init(keyCode: UInt32(kVK_Space), modifiers: GlobalShortcutStyle.controlOption.modifiers, isEnabled: true),
            .init(keyCode: UInt32(kVK_Space), modifiers: modifiers, isEnabled: true)
        ]
        var searches = 0, captures = 0
        let service = GlobalShortcutService(settings: settings, registrar: registrar,
            systemShortcuts: { reserved }, search: { searches += 1 }, capture: { captures += 1 })
        service.start()
        defer { service.stop() }
        try expect(service.isRegistered && registrar.registrations.count == 4,
            "Disabled, unrelated and legacy Space reservations allow the K/V shortcuts")
        for code in [UInt32(kVK_ANSI_K), UInt32(kVK_ANSI_V)] {
            reserved = [.init(keyCode: code, modifiers: modifiers, isEnabled: true)]
            settings.setEnabled(false); settings.setEnabled(true)
            registrar.callback?(1); registrar.callback?(2)
            try expect(!service.isRegistered && registrar.registrations.isEmpty
                && settings.registrationError?.contains(code == UInt32(kVK_ANSI_K) ? "Search shortcut" : "Save clipboard shortcut") == true
                && settings.registrationError?.contains("other Search/Save clipboard combination in Settings") == true
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
        try expect(service.isRegistered && registrar.registrations.count == 4
            && settings.registrationError == nil && searches == 1 && captures == 1,
            "Successful reservation verification restores both shortcuts and clears the error")
    }

    @MainActor private static func configurableShortcutCases(expect: (Bool, String) throws -> Void) throws {
        let name = "DaBinActionShortcutTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var reserved: [SystemGlobalShortcut]? = []
        let settings = QuickAccessSettings(defaults: defaults, systemShortcuts: { reserved })
        let registrar = FakeShortcutRegistrar()
        var searches = 0, captures = 0, expansions = 0, recordings = 0
        let service = GlobalShortcutService(settings: settings, registrar: registrar,
            systemShortcuts: { reserved }, search: { searches += 1 }, capture: { captures += 1 },
            fullScreen: { expansions += 1 }, recording: { recordings += 1 })
        service.start(); defer { service.stop() }
        let original = settings.actionShortcuts
        try expect(original.fullScreen == .fullScreenDefault && original.recording == .recordingDefault
            && GlobalShortcutBinding.fullScreenDefault.label == "⌃⌥F"
            && GlobalShortcutBinding.recordingDefault.label == "⌃⌥R",
            "New action preferences have readable independent F/R defaults")
        for action in ConfigurableShortcutAction.allCases {
            let saved = defaults.data(forKey: QuickAccessSettings.actionShortcutsKey)
            let binding = GlobalShortcutBinding(keyCode: UInt32(action == .fullScreen ? kVK_ANSI_G : kVK_ANSI_H),
                modifiers: UInt32(controlKey | optionKey | shiftKey), keyLabel: action == .fullScreen ? "G" : "H")
            reserved = [.init(keyCode: binding.keyCode, modifiers: binding.modifiers, isEnabled: true)]
            try expect(!settings.setShortcut(binding, for: action) && settings.actionShortcuts == original
                && defaults.data(forKey: QuickAccessSettings.actionShortcutsKey) == saved
                && registrar.registrations.count == 4 && service.isRegistered
                && settings.shortcutEditError?.contains(action.title) == true,
                "A reserved \(action.title) assignment preserves saved choices and all working registrations")
            reserved = [.init(keyCode: binding.keyCode, modifiers: binding.modifiers, isEnabled: false)]
            try expect(settings.setShortcut(binding, for: action) && settings.binding(for: action) == binding
                && service.isRegistered && settings.shortcutEditError == nil,
                "An inactive system reservation permits the assigned \(action.title) chord")
            let prior = action == .fullScreen ? original.fullScreen : original.recording
            try expect(settings.setShortcut(prior, for: action), "The original action chord can be restored")
        }
        let savedBeforeUnavailableRead = defaults.data(forKey: QuickAccessSettings.actionShortcutsKey)
        reserved = nil
        try expect(!settings.setShortcut(.init(keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(controlKey | optionKey), keyLabel: "G"), for: .fullScreen)
            && settings.actionShortcuts == original && service.isRegistered && registrar.registrations.count == 4
            && defaults.data(forKey: QuickAccessSettings.actionShortcutsKey) == savedBeforeUnavailableRead
            && settings.shortcutEditError != nil,
            "An unavailable macOS reservation check rejects assignment without stopping working shortcuts")
        reserved = []
        settings.resetActionShortcuts()
        try expect(settings.shortcutEditError == nil, "A successful reset clears the reservation-check error")
        try expect(!settings.setShortcut(.recordingDefault, for: .fullScreen)
            && settings.actionShortcuts == original && settings.shortcutEditError != nil,
            "Duplicate action chords are rejected without replacing saved bindings")
        for code in [kVK_ANSI_K, kVK_ANSI_V] {
            try expect(!settings.setShortcut(.init(keyCode: UInt32(code),
                modifiers: GlobalShortcutStyle.controlOption.modifiers, keyLabel: "K"), for: .fullScreen)
                && settings.actionShortcuts == original,
                "An action cannot take an existing Search or Save clipboard chord")
        }
        let invalid: [GlobalShortcutBinding] = [
            .init(keyCode: UInt32(kVK_ANSI_F), modifiers: 0, keyLabel: "F"),
            .init(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(shiftKey), keyLabel: "F"),
            .init(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey) | (1 << 31), keyLabel: "F"),
            .init(keyCode: 500, modifiers: UInt32(controlKey), keyLabel: "F"),
            .init(keyCode: UInt32(kVK_Escape), modifiers: UInt32(controlKey), keyLabel: "Escape"),
            .init(keyCode: UInt32(kVK_Tab), modifiers: UInt32(controlKey), keyLabel: "Tab"),
            .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey), keyLabel: "C"),
            .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey), keyLabel: "V"),
            .init(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey), keyLabel: "Q"),
            .init(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey), keyLabel: "H"),
            .init(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(cmdKey), keyLabel: ","),
            .init(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | optionKey), keyLabel: "H"),
            .init(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: UInt32(cmdKey), keyLabel: "["),
            .init(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(cmdKey), keyLabel: "="),
            .init(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey), keyLabel: "F"),
            .init(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey), keyLabel: "\n")
        ]
        for binding in invalid {
            try expect(binding.validationError != nil && !settings.setShortcut(binding, for: .fullScreen)
                && settings.actionShortcuts == original,
                "Invalid or built-in chords leave preferences and registrations intact")
        }
        for binding in [
            GlobalShortcutBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "H"),
            GlobalShortcutBinding(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(cmdKey | optionKey), keyLabel: ",")
        ] {
            try expect(binding.validationError == nil, "Only the exact Hide and Settings app chords are reserved")
        }
        let custom = GlobalShortcutBinding(keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(controlKey | optionKey | shiftKey), keyLabel: "G")
        try expect(settings.setShortcut(custom, for: .fullScreen)
            && registrar.registrations[3]?.0 == custom.keyCode && registrar.registrations[3]?.1 == custom.modifiers,
            "A valid custom chord immediately replaces its registration")
        try expect(settings.setShortcut(nil, for: .recording) && registrar.registrations.count == 3
            && registrar.registrations[4] == nil && service.isRegistered,
            "Disabling one action retains all other selected registered shortcuts")
        registrar.callback?(4); registrar.callback?(3)
        try expect(recordings == 0 && expansions == 1, "A stale disabled-action callback cannot toggle recording")
        let customized = settings.actionShortcuts
        let customizedData = defaults.data(forKey: QuickAccessSettings.actionShortcutsKey)
        let defaultFullScreen = GlobalShortcutBinding.fullScreenDefault
        reserved = [.init(keyCode: defaultFullScreen.keyCode, modifiers: defaultFullScreen.modifiers, isEnabled: true)]
        settings.resetActionShortcuts()
        try expect(settings.actionShortcuts == customized && service.isRegistered && registrar.registrations.count == 3
            && defaults.data(forKey: QuickAccessSettings.actionShortcutsKey) == customizedData
            && settings.shortcutEditError?.contains(ConfigurableShortcutAction.fullScreen.title) == true,
            "Reset rejects a reserved default without replacing working custom choices")
        reserved = []
        let restored = QuickAccessSettings(defaults: defaults, systemShortcuts: { [] })
        try expect(restored.binding(for: .fullScreen) == custom && restored.binding(for: .recording) == nil,
            "Custom and disabled action bindings both survive relaunch")
        let futureLegacy = GlobalShortcutBinding(keyCode: UInt32(kVK_ANSI_K),
            modifiers: GlobalShortcutStyle.controlOptionShift.modifiers, keyLabel: "K")
        try expect(settings.setShortcut(futureLegacy, for: .fullScreen), "A nonconflicting alternate-style K chord can be assigned")
        settings.setShortcutStyle(.controlOptionShift)
        try expect(settings.shortcutStyle == .controlOption && settings.binding(for: .fullScreen) == futureLegacy
            && settings.shortcutEditError != nil && registrar.registrations[1]?.1 == GlobalShortcutStyle.controlOption.modifiers,
            "A conflicting legacy-style change retains the prior style and action bindings")
        settings.resetActionShortcuts()
        try expect(settings.actionShortcuts == original && settings.shortcutEditError == nil
            && registrar.registrations.count == 4 && QuickAccessSettings(defaults: defaults, systemShortcuts: { [] }).actionShortcuts == original,
            "Reset restores and persists both defaults while clearing the editing error")
        settings.isEditingShortcut = true
        registrar.callback?(1); registrar.callback?(2); registrar.callback?(3); registrar.callback?(4)
        try expect(!service.isRegistered && registrar.registrations.isEmpty
            && searches == 0 && captures == 0 && expansions == 1 && recordings == 0,
            "Recorder focus suspends every own hotkey including pending callbacks")
        settings.isEditingShortcut = false
        try expect(service.isRegistered && registrar.registrations.count == 4,
            "Leaving recorder focus restores all current registrations")
        for action in ConfigurableShortcutAction.allCases {
            let binding = settings.binding(for: action)!
            reserved = [.init(keyCode: binding.keyCode, modifiers: binding.modifiers, isEnabled: true)]
            settings.setEnabled(false); settings.setEnabled(true)
            registrar.callback?(action.rawValue)
            try expect(!service.isRegistered && registrar.registrations.isEmpty
                && settings.registrationError?.contains(action.title) == true
                && settings.registrationError?.contains("Change or disable it in Settings") == true
                && expansions == 1 && recordings == 0,
                "A system reservation for \(action.title) prevents every atomic registration and dispatch")
            reserved = []
            settings.setEnabled(false); settings.setEnabled(true)
            registrar.failID = action.rawValue
            settings.setEnabled(false); settings.setEnabled(true)
            registrar.callback?(action.rawValue)
            try expect(!service.isRegistered && registrar.registrations.isEmpty
                && settings.registrationError?.contains(action.title) == true
                && settings.registrationError?.contains("Change or disable it in Settings") == true
                && expansions == 1 && recordings == 0,
                "A registrar failure for \(action.title) rolls back all partially registered shortcuts")
            registrar.failID = nil
            settings.setEnabled(false); settings.setEnabled(true)
            try expect(service.isRegistered && settings.registrationError == nil && registrar.registrations.count == 4,
                "A corrected \(action.title) registration recovers all actions")
        }
        let lateCallback = registrar.callback
        service.stop(); lateCallback?(3); lateCallback?(4)
        try expect(expansions == 1 && recordings == 0 && registrar.registrations.isEmpty,
            "Shutdown ignores late expansion and recording callbacks")
        var latch = ShortcutPressLatch()
        try expect(latch.accept(id: 3, isPressed: true) && !latch.accept(id: 3, isPressed: true),
            "One held key can dispatch only its first press")
        try expect(latch.accept(id: 4, isPressed: true) && !latch.accept(id: 3, isPressed: false)
            && latch.accept(id: 3, isPressed: true), "Independent keys and release permit a new deliberate press")
        latch.reset()
        try expect(latch.accept(id: 3, isPressed: true) && latch.accept(id: 4, isPressed: true),
            "Reconfiguration reset removes held-key state")
        func key(_ code: UInt16, text: String, repeatPress: Bool = false,
                 flags: NSEvent.ModifierFlags = [.control, .option]) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: repeatPress, keyCode: code)!
        }
        let printable = GlobalShortcutBinding.from(event: key(UInt16(kVK_ANSI_F), text: "f"))
        try expect(printable?.keyCode == UInt32(kVK_ANSI_F)
            && printable?.modifiers == UInt32(controlKey | optionKey) && printable?.validationError == nil,
            "Recorder derives an unmodified printable label and explicit Carbon flags")
        for (code, text, label) in [(UInt16(49), " ", "Space"), (UInt16(123), "\u{F702}", "←"),
                                   (UInt16(120), "\u{F705}", "F2")] {
            try expect(GlobalShortcutBinding.from(event: key(code, text: text))?.keyLabel == label,
                "Recorder supports a readable \(label) chord")
        }
        try expect(GlobalShortcutBinding.from(event: key(UInt16(kVK_ANSI_F), text: "f", repeatPress: true)) == nil
            && GlobalShortcutBinding.from(event: key(UInt16(kVK_Escape), text: "\u{1b}")) == nil
            && GlobalShortcutBinding.from(event: key(UInt16(kVK_Tab), text: "\t")) == nil
            && GlobalShortcutBinding.from(event: key(UInt16(kVK_Command), text: "")) == nil,
            "Recorder ignores repeats, Escape, Tab and modifier-only keys")
        let nonKey = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
            timestamp: 1, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        try expect(GlobalShortcutBinding.from(event: nonKey) == nil,
            "Recorder ignores non-key events without accessing key-only properties")
        let invalidSaved = GlobalActionShortcutBindings(fullScreen: .recordingDefault, recording: .recordingDefault)
        defaults.set(try JSONEncoder().encode(invalidSaved), forKey: QuickAccessSettings.actionShortcutsKey)
        let conflicting = QuickAccessSettings(defaults: defaults, systemShortcuts: { [] })
        try expect(conflicting.binding(for: .fullScreen) == nil && conflicting.binding(for: .recording) == nil
            && conflicting.shortcutEditError != nil,
            "Duplicate persisted bindings are not silently registered on relaunch")
        defaults.set(Data("unreadable".utf8), forKey: QuickAccessSettings.actionShortcutsKey)
        let damaged = QuickAccessSettings(defaults: defaults, systemShortcuts: { [] })
        try expect(damaged.binding(for: .fullScreen) == nil && damaged.binding(for: .recording) == nil
            && damaged.shortcutEditError != nil && damaged.shortcutStyle == .controlOption,
            "Malformed saved action data leaves legacy choices intact and new actions safely disabled")
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
        let settings = QuickAccessSettings(defaults: defaults, systemShortcuts: { [] })
        let registrar = FakeShortcutRegistrar()
        var searches = 0, captures = 0, expansions = 0, recordings = 0
        let service = GlobalShortcutService(settings: settings, registrar: registrar, systemShortcuts: { [] },
            search: { searches += 1 }, capture: { captures += 1 },
            fullScreen: { expansions += 1 }, recording: { recordings += 1 })
        try expect(registrar.registrations.isEmpty, "Construction registers no system key handlers")
        service.start(); service.start()
        try expect(registrar.installed == 1 && registrar.registrations.count == 4, "Start is idempotent with four explicit chords")
        try expect(registrar.registrations[1]?.0 == UInt32(kVK_ANSI_K)
            && registrar.registrations[2]?.0 == UInt32(kVK_ANSI_V)
            && registrar.registrations[1]?.1 == GlobalShortcutStyle.controlOption.modifiers,
            "Default global registration uses Control+Option+K for Search and Control+Option+V for capture")
        registrar.callback?(1); registrar.callback?(2); registrar.callback?(3); registrar.callback?(4); registrar.callback?(999)
        try expect(searches == 1 && captures == 1 && expansions == 1 && recordings == 1,
                   "Only the four registered actions dispatch once")
        try expect(registrar.registrations[3]?.0 == UInt32(kVK_ANSI_F)
            && registrar.registrations[4]?.0 == UInt32(kVK_ANSI_R)
            && registrar.registrations[3]?.1 == GlobalShortcutStyle.controlOption.modifiers,
            "Default action shortcuts use Control+Option+F and Control+Option+R")
        let originalModifiers = registrar.registrations[1]!.1
        settings.setShortcutStyle(.controlOptionShift)
        try expect(registrar.registrations[1]!.1 != originalModifiers && registrar.registrations.count == 4, "Changing legacy chords retains both independently configured action shortcuts")
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
        let reopened = QuickAccessSettings(defaults: defaults, systemShortcuts: { [] })
        try expect(reopened.isEnabled && reopened.quietMode && reopened.shortcutStyle == .controlOption, "Preferences survive relaunch")
        let lateCallback = registrar.callback
        service.stop(); service.stop(); lateCallback?(2)
        try expect(!service.isStarted && registrar.registrations.isEmpty && captures == 1, "Shutdown removes handlers and ignores late dispatch")
        try searchNavigationCases(expect: expect)
        try reservedShortcutCases(expect: expect)
        try configurableShortcutCases(expect: expect)
        print("PASS: \(checks) quick access checks")
    }
}
