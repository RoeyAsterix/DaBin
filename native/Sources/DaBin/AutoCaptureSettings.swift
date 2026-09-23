import Combine
import Foundation

/// The durable and user-visible state of the opt-in automatic monitor.
///
/// `ready` means the preference and folder grant are present but the runtime
/// monitor has not started yet. It prevents a persisted `monitoring` value from
/// claiming that a newly launched process is already observing anything.
enum AutoCaptureStatus: Equatable, Sendable {
    case disabled
    case paused
    case ready
    case monitoring
    case permissionRequired
    case permissionRevoked
    case sourceApplicationExcluded(String)
    case failed(String)

    fileprivate var persistedValue: (kind: String, detail: String?) {
        switch self {
        case .disabled: return ("disabled", nil)
        case .paused: return ("paused", nil)
        case .ready: return ("ready", nil)
        case .monitoring: return ("monitoring", nil)
        case .permissionRequired: return ("permissionRequired", nil)
        case .permissionRevoked: return ("permissionRevoked", nil)
        case .sourceApplicationExcluded(let name): return ("sourceApplicationExcluded", name)
        case .failed(let message): return ("failed", message)
        }
    }

    fileprivate static func restore(kind: String?, detail: String?) -> AutoCaptureStatus? {
        switch kind {
        case "disabled": return .disabled
        case "paused": return .paused
        case "ready": return .ready
        case "monitoring": return .monitoring
        case "permissionRequired": return .permissionRequired
        case "permissionRevoked": return .permissionRevoked
        case "sourceApplicationExcluded": return .sourceApplicationExcluded(detail ?? "Excluded application")
        case "failed": return .failed(detail ?? "Auto Capture could not start.")
        default: return nil
        }
    }
}

/// Preferences for Auto Capture. Constructing this object never requests a
/// permission, opens a panel, or reads the clipboard.
@MainActor
final class AutoCaptureSettings: ObservableObject {
    nonisolated static let enabledKey = "DaBin.autoCapture.enabled.v1"
    nonisolated static let pausedKey = "DaBin.autoCapture.paused.v1"
    nonisolated static let statusKey = "DaBin.autoCapture.status.v1"
    nonisolated static let statusDetailKey = "DaBin.autoCapture.statusDetail.v1"
    nonisolated static let exclusionsKey = "DaBin.autoCapture.excludedBundleIdentifiers.v1"
    nonisolated static let screenshotFolderBookmarkKey = "DaBin.autoCapture.screenshotFolderBookmark.v1"
    nonisolated static let screenshotFolderDisplayNameKey = "DaBin.autoCapture.screenshotFolderDisplayName.v1"
    nonisolated static let privacyExplanationAcknowledgedKey = "DaBin.autoCapture.privacyExplanationAcknowledged.v1"

    /// Password managers are excluded on first use. Users can extend this set;
    /// the DaBin bundle identifier is always added by the initializer.
    nonisolated static let defaultExcludedBundleIdentifiers: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.enpass.Enpass",
        "com.lastpass.LastPass",
        "com.nordsec.NordPass",
        "com.roboform.roboform-mac",
        "org.keepassxc.keepassxc"
    ]

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isPaused: Bool
    @Published private(set) var status: AutoCaptureStatus
    @Published private(set) var excludedBundleIdentifiers: Set<String>
    @Published private(set) var hasAcknowledgedPrivacyExplanation: Bool
    @Published private(set) var screenshotFolderDisplayName: String?

    private let defaults: UserDefaults?
    private let ownBundleIdentifier: String

    init(defaults: UserDefaults? = .standard,
         ownBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.dabin.mac") {
        self.defaults = defaults
        self.ownBundleIdentifier = ownBundleIdentifier
        let savedEnabled = defaults?.object(forKey: Self.enabledKey) as? Bool ?? false
        let savedPaused = defaults?.object(forKey: Self.pausedKey) as? Bool ?? false
        isEnabled = savedEnabled
        isPaused = savedPaused
        hasAcknowledgedPrivacyExplanation = defaults?.object(forKey: Self.privacyExplanationAcknowledgedKey) as? Bool ?? false
        screenshotFolderDisplayName = defaults?.string(forKey: Self.screenshotFolderDisplayNameKey)

        let savedExclusions = defaults?.array(forKey: Self.exclusionsKey) as? [String]
        var exclusions = Set(savedExclusions ?? Array(Self.defaultExcludedBundleIdentifiers))
        exclusions.insert(ownBundleIdentifier)
        excludedBundleIdentifiers = exclusions

        if !savedEnabled {
            status = .disabled
        } else if savedPaused {
            status = .paused
        } else {
            let restored = AutoCaptureStatus.restore(
                kind: defaults?.string(forKey: Self.statusKey),
                detail: defaults?.string(forKey: Self.statusDetailKey)
            )
            switch restored {
            case .monitoring, .sourceApplicationExcluded:
                // A previous process cannot still be monitoring after relaunch.
                status = .ready
            case .some(let saved):
                status = saved
            case nil:
                status = defaults?.data(forKey: Self.screenshotFolderBookmarkKey) == nil
                    ? .permissionRequired : .ready
            }
        }
    }

    var screenshotFolderBookmark: Data? {
        defaults?.data(forKey: Self.screenshotFolderBookmarkKey)
    }

    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(bundleIdentifier)
    }

    func setEnabled(_ enabled: Bool) {
        if isEnabled != enabled { isEnabled = enabled }
        defaults?.set(enabled, forKey: Self.enabledKey)
    }

    func setPaused(_ paused: Bool) {
        if isPaused != paused { isPaused = paused }
        defaults?.set(paused, forKey: Self.pausedKey)
    }

    func setStatus(_ value: AutoCaptureStatus) {
        if status != value { status = value }
        let persisted = value.persistedValue
        defaults?.set(persisted.kind, forKey: Self.statusKey)
        if let detail = persisted.detail {
            defaults?.set(detail, forKey: Self.statusDetailKey)
        } else {
            defaults?.removeObject(forKey: Self.statusDetailKey)
        }
    }

    func setScreenshotFolderBookmark(_ data: Data?, displayName: String? = nil) {
        if let data {
            defaults?.set(data, forKey: Self.screenshotFolderBookmarkKey)
            if let displayName, !displayName.isEmpty {
                screenshotFolderDisplayName = displayName
                defaults?.set(displayName, forKey: Self.screenshotFolderDisplayNameKey)
            }
        } else {
            defaults?.removeObject(forKey: Self.screenshotFolderBookmarkKey)
            defaults?.removeObject(forKey: Self.screenshotFolderDisplayNameKey)
            screenshotFolderDisplayName = nil
        }
    }

    func setPrivacyExplanationAcknowledged(_ acknowledged: Bool) {
        if hasAcknowledgedPrivacyExplanation != acknowledged {
            hasAcknowledgedPrivacyExplanation = acknowledged
        }
        defaults?.set(acknowledged, forKey: Self.privacyExplanationAcknowledgedKey)
    }

    func acknowledgePrivacyExplanation() {
        setPrivacyExplanationAcknowledged(true)
    }

    func setApplication(bundleIdentifier: String, excluded: Bool) {
        guard !bundleIdentifier.isEmpty else { return }
        if excluded || bundleIdentifier == ownBundleIdentifier {
            excludedBundleIdentifiers.insert(bundleIdentifier)
        } else {
            excludedBundleIdentifiers.remove(bundleIdentifier)
        }
        persistExclusions()
    }

    func replaceExcludedBundleIdentifiers(with bundleIdentifiers: Set<String>) {
        excludedBundleIdentifiers = bundleIdentifiers.filter { !$0.isEmpty }
        excludedBundleIdentifiers.insert(ownBundleIdentifier)
        persistExclusions()
    }

    private func persistExclusions() {
        defaults?.set(excludedBundleIdentifiers.sorted(), forKey: Self.exclusionsKey)
    }
}
