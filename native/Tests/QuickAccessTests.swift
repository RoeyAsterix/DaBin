import Foundation

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
        let service = GlobalShortcutService(settings: settings, registrar: registrar,
            search: { searches += 1 }, capture: { captures += 1 })
        try expect(registrar.registrations.isEmpty, "Construction registers no system key handlers")
        service.start(); service.start()
        try expect(registrar.installed == 1 && registrar.registrations.count == 2, "Start is idempotent with two explicit chords")
        registrar.callback?(1); registrar.callback?(2); registrar.callback?(999)
        try expect(searches == 1 && captures == 1, "Only registered actions dispatch")
        let originalModifiers = registrar.registrations[1]!.1
        settings.setShortcutStyle(.controlOptionShift)
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
        print("PASS: \(checks) quick access checks")
    }
}
