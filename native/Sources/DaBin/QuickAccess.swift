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

enum ConfigurableShortcutAction: UInt32, CaseIterable, Identifiable {
    case fullScreen = 3, recording = 4
    var id: UInt32 { rawValue }
    var title: String { self == .fullScreen ? "Full screen" : "Recording on/off" }
}

struct GlobalShortcutBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    static let fullScreenDefault = Self(keyCode: UInt32(kVK_ANSI_F),
        modifiers: UInt32(controlKey | optionKey), keyLabel: "F")
    static let recordingDefault = Self(keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey), keyLabel: "R")
    var label: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "")
        + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "")
        + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "")
        + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + keyLabel
    }
    private static let specialLabels: [UInt32: String] = [
        49: "Space", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20"
    ]
    private static func supports(_ code: UInt32) -> Bool {
        // Printable ANSI/ISO keys, keypad symbols/digits, arrows and F1–F20.
        (code <= 47 && code != 36) || code == 50 || specialLabels[code] != nil
            || [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92].contains(code)
    }
    var validationError: String? {
        let allowed = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        guard Self.supports(keyCode), modifiers & ~allowed == 0,
              !keyLabel.isEmpty, keyLabel.count <= 12,
              !keyLabel.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return "Choose a letter, number, symbol, function key, arrow or Space."
        }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else {
            return "Include Control, Option or Command in the shortcut."
        }
        if (keyCode == UInt32(kVK_ANSI_H)
            && (modifiers == UInt32(cmdKey) || modifiers == UInt32(cmdKey | optionKey)))
            || (keyCode == UInt32(kVK_ANSI_Comma) && modifiers == UInt32(cmdKey)) {
            return "That combination is reserved for Hide DaBin, Hide Others or Settings."
        }
        let commandOnly = modifiers & UInt32(cmdKey) != 0
            && modifiers & UInt32(controlKey | optionKey) == 0
        let editingKeys = [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z,
                           kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_S, kVK_ANSI_O, kVK_ANSI_N,
                           kVK_ANSI_K, kVK_ANSI_F, kVK_ANSI_P, kVK_ANSI_LeftBracket,
                           kVK_ANSI_RightBracket, kVK_ANSI_Equal, kVK_ANSI_Minus, kVK_ANSI_0]
        if commandOnly && (editingKeys.contains(Int(keyCode))
            || (keyCode == UInt32(kVK_ANSI_D) && modifiers & UInt32(shiftKey) != 0)
            || [123, 124, 125, 126].contains(keyCode)) {
            return "That combination is reserved for standard editing or DaBin commands."
        }
        if modifiers == UInt32(optionKey) && [123, 124].contains(keyCode) {
            return "That combination is reserved for moving through text."
        }
        if modifiers == UInt32(controlKey)
            && [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
                kVK_ANSI_H, kVK_ANSI_K, kVK_ANSI_N, kVK_ANSI_P, kVK_ANSI_T,
                kVK_ANSI_V].contains(Int(keyCode)) {
            return "That combination is reserved for standard text editing."
        }
        return nil
    }
    static func from(event: NSEvent) -> Self? {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let code = UInt32(event.keyCode)
        guard supports(code) else { return nil }
        let label: String
        if let special = specialLabels[code] { label = special }
        else {
            guard let characters = event.characters(byApplyingModifiers: []), !characters.isEmpty,
                  characters.count <= 4,
                  !characters.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value)
                  }) else { return nil }
            label = characters.uppercased()
        }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return Self(keyCode: code, modifiers: modifiers, keyLabel: label)
    }
    func conflicts(with other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
}

struct GlobalActionShortcutBindings: Codable, Equatable {
    var fullScreen: GlobalShortcutBinding?
    var recording: GlobalShortcutBinding?
    init(fullScreen: GlobalShortcutBinding? = .fullScreenDefault,
         recording: GlobalShortcutBinding? = .recordingDefault) {
        self.fullScreen = fullScreen; self.recording = recording
    }
}

/// A release does not dispatch. It only permits the next deliberate press.
struct ShortcutPressLatch {
    private var pressed = Set<UInt32>()
    mutating func accept(id: UInt32, isPressed: Bool) -> Bool {
        if isPressed { return pressed.insert(id).inserted }
        pressed.remove(id); return false
    }
    mutating func reset() { pressed.removeAll() }
}

@MainActor
final class QuickAccessSettings: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var shortcutStyle: GlobalShortcutStyle
    @Published private(set) var quietMode: Bool
    @Published private(set) var actionShortcuts: GlobalActionShortcutBindings
    @Published var isEditingShortcut = false
    @Published var shortcutEditError: String?
    @Published var registrationError: String?
    private let defaults: UserDefaults?
    private let systemShortcuts: @MainActor () -> [SystemGlobalShortcut]?
    static let enabledKey = "DaBin.quickAccess.enabled.v1"
    static let styleKey = "DaBin.quickAccess.style.v1"
    static let quietKey = "DaBin.quickAccess.quiet.v1"
    static let actionShortcutsKey = "DaBin.quickAccess.actionShortcuts.v1"

    init(defaults: UserDefaults? = .standard,
         systemShortcuts: @escaping @MainActor () -> [SystemGlobalShortcut]? = { SystemGlobalShortcut.current() }) {
        self.defaults = defaults
        self.systemShortcuts = systemShortcuts
        isEnabled = defaults?.object(forKey: Self.enabledKey) as? Bool ?? true
        shortcutStyle = defaults?.string(forKey: Self.styleKey).flatMap(GlobalShortcutStyle.init(rawValue:)) ?? .controlOption
        quietMode = defaults?.bool(forKey: Self.quietKey) ?? false
        actionShortcuts = GlobalActionShortcutBindings()
        if let saved = defaults?.data(forKey: Self.actionShortcutsKey) {
            if let decoded = try? JSONDecoder().decode(GlobalActionShortcutBindings.self, from: saved) {
                actionShortcuts = decoded
            } else {
                actionShortcuts = .init(fullScreen: nil, recording: nil)
                shortcutEditError = "Saved action shortcuts could not be read. Set them again or reset shortcuts."
            }
        }
        if let error = validationError(actionShortcuts, style: shortcutStyle) {
            actionShortcuts = .init(fullScreen: nil, recording: nil)
            shortcutEditError = error
        }
    }
    func setEnabled(_ enabled: Bool) { isEnabled = enabled; defaults?.set(enabled, forKey: Self.enabledKey) }
    func setShortcutStyle(_ style: GlobalShortcutStyle) {
        if let error = validationError(actionShortcuts, style: style) { shortcutEditError = error; return }
        shortcutStyle = style; defaults?.set(style.rawValue, forKey: Self.styleKey); shortcutEditError = nil
    }
    func setQuietMode(_ quiet: Bool) { quietMode = quiet; defaults?.set(quiet, forKey: Self.quietKey) }
    func binding(for action: ConfigurableShortcutAction) -> GlobalShortcutBinding? {
        action == .fullScreen ? actionShortcuts.fullScreen : actionShortcuts.recording
    }
    @discardableResult func setShortcut(_ binding: GlobalShortcutBinding?, for action: ConfigurableShortcutAction) -> Bool {
        var proposed = actionShortcuts
        if action == .fullScreen { proposed.fullScreen = binding } else { proposed.recording = binding }
        if let error = validationError(proposed, style: shortcutStyle) {
            shortcutEditError = error; return false
        }
        if let binding, let error = reservationError([(action, binding)]) {
            shortcutEditError = error; return false
        }
        actionShortcuts = proposed; persistActionShortcuts(); shortcutEditError = nil; return true
    }
    func resetActionShortcuts() {
        let proposed = GlobalActionShortcutBindings()
        let bindings: [(ConfigurableShortcutAction, GlobalShortcutBinding)] = [
            (.fullScreen, .fullScreenDefault), (.recording, .recordingDefault)
        ]
        if let error = reservationError(bindings) { shortcutEditError = error; return }
        actionShortcuts = proposed; persistActionShortcuts(); shortcutEditError = nil
    }
    private func reservationError(_ bindings: [(ConfigurableShortcutAction, GlobalShortcutBinding)]) -> String? {
        guard let reserved = systemShortcuts() else {
            return "macOS shortcuts could not be checked. Try setting the shortcut again."
        }
        for (action, binding) in bindings where reserved.contains(where: {
            $0.isEnabled && $0.keyCode == binding.keyCode && $0.modifiers == binding.modifiers
        }) {
            return "\(action.title) shortcut \(binding.label) is used by macOS. Choose a different shortcut."
        }
        return nil
    }
    private func persistActionShortcuts() {
        if let data = try? JSONEncoder().encode(actionShortcuts) { defaults?.set(data, forKey: Self.actionShortcutsKey) }
    }
    private func validationError(_ bindings: GlobalActionShortcutBindings, style: GlobalShortcutStyle) -> String? {
        let active = [bindings.fullScreen, bindings.recording].compactMap { $0 }
        if let error = active.compactMap({ $0.validationError }).first { return error }
        if active.count == 2 && active[0].conflicts(with: active[1]) {
            return "Full screen and recording need different shortcuts."
        }
        if active.contains(where: { $0.modifiers == style.modifiers
            && ($0.keyCode == UInt32(kVK_ANSI_K) || $0.keyCode == UInt32(kVK_ANSI_V)) }) {
            return "That combination is already used by Search or Save clipboard."
        }
        return nil
    }
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
    private var registeredIDs = Set<UInt32>()
    private var pressLatch = ShortcutPressLatch()
    private var epoch: UInt = 0
    private var onPress: ((UInt32) -> Void)?
    private static let signature: OSType = 0x4441424E // DABN

    func install(_ onPress: @escaping (UInt32) -> Void) -> Bool {
        self.onPress = onPress
        guard handler == nil else { return true }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identity)
            guard status == noErr, identity.signature == 0x4441424E else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<CarbonShortcutRegistrar>.fromOpaque(context).takeUnretainedValue()
            let identifier = identity.id
            let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated {
                guard registrar.registeredIDs.contains(identifier),
                      registrar.pressLatch.accept(id: identifier, isPressed: isPressed) else { return }
                let epoch = registrar.epoch
                Task { @MainActor [weak registrar] in
                    guard let registrar, registrar.epoch == epoch,
                          registrar.registeredIDs.contains(identifier) else { return }
                    registrar.onPress?(identifier)
                }
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        return status == noErr
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        keys.append(reference); registeredIDs.insert(id)
        return true
    }
    func removeAll() {
        epoch &+= 1; pressLatch.reset(); registeredIDs.removeAll()
        keys.forEach { UnregisterEventHotKey($0) }; keys.removeAll()
    }
    func uninstall() {
        removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil; onPress = nil
    }
}

@MainActor
final class GlobalShortcutService {
    private let settings: QuickAccessSettings
    private let registrar: ShortcutRegistering
    private let systemShortcuts: @MainActor () -> [SystemGlobalShortcut]?
    private let search: () -> Void
    private let capture: () -> Void
    private let fullScreen: () -> Void
    private let recording: () -> Void
    private var subscription: AnyCancellable?
    private var registeredIDs = Set<UInt32>()
    private(set) var isStarted = false
    private(set) var isRegistered = false

    init(settings: QuickAccessSettings, registrar: ShortcutRegistering? = nil,
         systemShortcuts: @escaping @MainActor () -> [SystemGlobalShortcut]? = { SystemGlobalShortcut.current() },
         search: @escaping () -> Void, capture: @escaping () -> Void,
         fullScreen: @escaping () -> Void = {}, recording: @escaping () -> Void = {}) {
        self.settings = settings
        self.registrar = registrar ?? CarbonShortcutRegistrar()
        self.systemShortcuts = systemShortcuts
        self.search = search; self.capture = capture
        self.fullScreen = fullScreen; self.recording = recording
    }
    func start() {
        guard !isStarted else { return }
        isStarted = true
        guard registrar.install({ [weak self] identifier in self?.handle(identifier) }) else {
            settings.registrationError = "macOS could not register DaBin’s shortcuts. Menu bar access still works."
            isStarted = false; registrar.uninstall(); return
        }
        subscription = Publishers.CombineLatest4(settings.$isEnabled, settings.$shortcutStyle,
            settings.$actionShortcuts, settings.$isEditingShortcut)
            .sink { [weak self] enabled, style, actions, editing in
                self?.configure(enabled: enabled, style: style, actions: actions, editing: editing)
            }
    }
    private func configure(enabled: Bool, style: GlobalShortcutStyle,
                           actions: GlobalActionShortcutBindings, editing: Bool) {
        registrar.removeAll(); registeredIDs.removeAll()
        isRegistered = false; settings.registrationError = nil
        guard isStarted, enabled, !editing else { return }
        var chords: [(id: UInt32, title: String, binding: GlobalShortcutBinding)] = [
            (1, "Search", .init(keyCode: UInt32(kVK_ANSI_K), modifiers: style.modifiers, keyLabel: "K")),
            (2, "Save clipboard", .init(keyCode: UInt32(kVK_ANSI_V), modifiers: style.modifiers, keyLabel: "V"))
        ]
        if let binding = actions.fullScreen { chords.append((3, ConfigurableShortcutAction.fullScreen.title, binding)) }
        if let binding = actions.recording { chords.append((4, ConfigurableShortcutAction.recording.title, binding)) }
        func failureMessage(for chord: (id: UInt32, title: String, binding: GlobalShortcutBinding)) -> String {
            let recovery = ConfigurableShortcutAction(rawValue: chord.id) == nil
                ? "Choose the other Search/Save clipboard combination in Settings."
                : "Change or disable it in Settings."
            return "\(chord.title) shortcut \(chord.binding.label) is unavailable or used by macOS or another app. \(recovery)"
        }
        var signatures = Set<String>()
        for chord in chords {
            guard chord.binding.validationError == nil,
                  signatures.insert("\(chord.binding.keyCode):\(chord.binding.modifiers)").inserted else {
                settings.registrationError = failureMessage(for: chord); return
            }
        }
        guard let reserved = systemShortcuts() else {
            settings.registrationError = "macOS shortcuts could not be checked. Try again in Settings; menu bar access still works."
            return
        }
        for chord in chords where reserved.contains(where: {
            $0.isEnabled && $0.keyCode == chord.binding.keyCode && $0.modifiers == chord.binding.modifiers
        }) {
            settings.registrationError = failureMessage(for: chord); return
        }
        for chord in chords {
            guard registrar.register(id: chord.id, keyCode: chord.binding.keyCode, modifiers: chord.binding.modifiers) else {
                registrar.removeAll(); settings.registrationError = failureMessage(for: chord); return
            }
        }
        registeredIDs = Set(chords.map { $0.id }); isRegistered = true
    }
    private func handle(_ identifier: UInt32) {
        guard isStarted, isRegistered, settings.isEnabled, !settings.isEditingShortcut,
              registeredIDs.contains(identifier) else { return }
        switch identifier {
        case 1: search()
        case 2: capture()
        case 3: fullScreen()
        case 4: recording()
        default: break
        }
    }
    func stop() {
        subscription?.cancel(); subscription = nil
        isStarted = false; isRegistered = false; registeredIDs.removeAll()
        registrar.uninstall()
    }
}
