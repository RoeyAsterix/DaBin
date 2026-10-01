import Combine
import Foundation

enum RobotHome: String, CaseIterable, Identifiable {
    case corners
    case cameraIsland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .corners: return "Screen corners"
        case .cameraIsland: return "Below camera island"
        }
    }
}

/// Controls only where the small robot waits. Capture data and the movable
/// Daily window position are deliberately outside this preference.
@MainActor
final class RobotPlacementSettings: ObservableObject {
    nonisolated static let defaultsKey = "DaBin.robotHome.v1"

    @Published private(set) var home: RobotHome
    private let defaults: UserDefaults?

    /// Passing nil creates an isolated, non-persisting default for tests and
    /// previews. The production composition root supplies its shared defaults.
    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        home = defaults?.string(forKey: Self.defaultsKey).flatMap(RobotHome.init(rawValue:)) ?? .corners
    }

    func setHome(_ value: RobotHome) {
        if home != value { home = value }
        defaults?.set(value.rawValue, forKey: Self.defaultsKey)
    }
}
