import AppKit
import Carbon
import Combine

enum GlobalShortcutStyle: String, CaseIterable, Identifiable {
    case controlOption, controlOptionShift
    var id: String { rawValue }
    var title: String { self == .controlOption ? "Control + Option" : "Control + Option + Shift" }
    var searchLabel: String { self == .controlOption ? "⌃⌥K" : "⌃⌥⇧K" }
    var captureLabel: String { self == .controlOption ? "⌃⌥V" : "⌃⌥⇧V" }
    var modifiers: UInt32 {
        UInt32(controlKey | optionKey | (self == .controlOptionShift ? shiftKey : 0))
    }
}

@MainActor
final class QuickAccessSettings: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var shortcutStyle: GlobalShortcutStyle
    @Published private(set) var quietMode: Bool
    @Published var registrationError: String?
    private let defaults: UserDefaults?
    static let enabledKey = "DaBin.quickAccess.enabled.v1"
    static let styleKey = "DaBin.quickAccess.style.v1"
    static let quietKey = "DaBin.quickAccess.quiet.v1"

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        isEnabled = defaults?.object(forKey: Self.enabledKey) as? Bool ?? true
        shortcutStyle = defaults?.string(forKey: Self.styleKey).flatMap(GlobalShortcutStyle.init(rawValue:)) ?? .controlOption
        quietMode = defaults?.bool(forKey: Self.quietKey) ?? false
    }
    func setEnabled(_ enabled: Bool) { isEnabled = enabled; defaults?.set(enabled, forKey: Self.enabledKey) }
    func setShortcutStyle(_ style: GlobalShortcutStyle) { shortcutStyle = style; defaults?.set(style.rawValue, forKey: Self.styleKey) }
    func setQuietMode(_ quiet: Bool) { quietMode = quiet; defaults?.set(quiet, forKey: Self.quietKey) }
}

struct SystemGlobalShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let isEnabled: Bool

    /// Carbon registration can succeed for an already-used, non-exclusive
    /// chord. Read the user's enabled macOS shortcuts before registering.
    /// Nil means the reservation check could not be completed safely.
    @MainActor static func current() -> [SystemGlobalShortcut]? {
        var copied: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&copied)
        let hotKeys = copied?.takeRetainedValue()
        guard status == noErr, let entries = hotKeys as? [[String: Any]] else { return nil }
        var result: [SystemGlobalShortcut] = []
        for entry in entries {
            guard let keyCode = entry[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? NSNumber,
                  let enabled = entry[kHISymbolicHotKeyEnabled as String] as? NSNumber else { return nil }
            result.append(SystemGlobalShortcut(keyCode: keyCode.uint32Value,
                                               modifiers: modifiers.uint32Value,
                                               isEnabled: enabled.boolValue))
        }
        return result
    }
}

/// Registers only explicit key chords. This does not observe general typing or
/// require Accessibility/Screen Recording permission.
@MainActor
protocol ShortcutRegistering: AnyObject {
    func install(_ onPress: @escaping (UInt32) -> Void) -> Bool
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool
    func removeAll()
    func uninstall()
}

@MainActor
final class CarbonShortcutRegistrar: ShortcutRegistering {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private var onPress: ((UInt32) -> Void)?
    private static let signature: OSType = 0x4441424E // DABN

    func install(_ onPress: @escaping (UInt32) -> Void) -> Bool {
        self.onPress = onPress
        guard handler == nil else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == 0x4441424E else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<CarbonShortcutRegistrar>.fromOpaque(context).takeUnretainedValue()
            let identifier = identity.id
            Task { @MainActor in registrar.onPress?(identifier) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        return status == noErr
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        keys.append(reference)
        return true
    }
    func removeAll() { keys.forEach { UnregisterEventHotKey($0) }; keys.removeAll() }
    func uninstall() {
        removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
    }
}

@MainActor
final class GlobalShortcutService {
    private let settings: QuickAccessSettings
    private let registrar: ShortcutRegistering
    private let systemShortcuts: @MainActor () -> [SystemGlobalShortcut]?
    private let search: () -> Void
    private let capture: () -> Void
    private var subscription: AnyCancellable?
    private(set) var isStarted = false
    private(set) var isRegistered = false

    init(settings: QuickAccessSettings, registrar: ShortcutRegistering? = nil,
         systemShortcuts: @escaping @MainActor () -> [SystemGlobalShortcut]? = { SystemGlobalShortcut.current() },
         search: @escaping () -> Void, capture: @escaping () -> Void) {
        self.settings = settings
        self.registrar = registrar ?? CarbonShortcutRegistrar()
        self.systemShortcuts = systemShortcuts
        self.search = search
        self.capture = capture
    }
    func start() {
        guard !isStarted else { return }
        isStarted = true
        guard registrar.install({ [weak self] identifier in self?.handle(identifier) }) else {
            settings.registrationError = "macOS could not register DaBin’s shortcuts. Menu bar access still works."
            isStarted = false
            registrar.uninstall()
            return
        }
        subscription = settings.$isEnabled.combineLatest(settings.$shortcutStyle)
            .sink { [weak self] enabled, style in self?.configure(enabled: enabled, style: style) }
    }
    private func configure(enabled: Bool, style: GlobalShortcutStyle) {
        registrar.removeAll()
        isRegistered = false
        settings.registrationError = nil
        guard isStarted, enabled else { return }
        let error = "A shortcut is unavailable or used by another app. Choose the other key combination."
        guard let reserved = systemShortcuts(), !reserved.contains(where: {
            $0.isEnabled && $0.modifiers == style.modifiers
                && ($0.keyCode == UInt32(kVK_ANSI_K) || $0.keyCode == UInt32(kVK_ANSI_V))
        }) else {
            settings.registrationError = error
            return
        }
        guard registrar.register(id: 1, keyCode: UInt32(kVK_ANSI_K), modifiers: style.modifiers),
              registrar.register(id: 2, keyCode: UInt32(kVK_ANSI_V), modifiers: style.modifiers) else {
            registrar.removeAll()
            settings.registrationError = error
            return
        }
        isRegistered = true
    }
    private func handle(_ identifier: UInt32) {
        guard isStarted, isRegistered, settings.isEnabled else { return }
        switch identifier {
        case 1: search()
        case 2: capture()
        default: break
        }
    }
    func stop() {
        subscription?.cancel(); subscription = nil
        isStarted = false
        isRegistered = false
        registrar.uninstall()
    }
}
