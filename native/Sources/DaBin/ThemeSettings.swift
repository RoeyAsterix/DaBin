import AppKit
import SwiftUI

private struct DaBinAccentKey: EnvironmentKey {
    static let defaultValue = ThemeSettings.accentColor(for: ThemeSettings.defaultHex)
}

extension EnvironmentValues {
    var daBinAccent: Color {
        get { self[DaBinAccentKey.self] }
        set { self[DaBinAccentKey.self] = newValue }
    }
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case purple, blue, teal, green, rose, amber

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var hex: String {
        switch self {
        case .purple: return ThemeSettings.defaultHex
        case .blue: return "386A9A"
        case .teal: return "287875"
        case .green: return "47763E"
        case .rose: return "A34D73"
        case .amber: return "956515"
        }
    }
    var swatch: Color { ThemeSettings.color(for: hex) }
}

/// An appearance preference only; changing it never rewrites captured content.
@MainActor
final class ThemeSettings: ObservableObject {
    nonisolated static let defaultHex = "6D5387"
    nonisolated static let defaultsKey = "DaBin.themeColor.v1"
    nonisolated static let defaultBoardOpacity = 0.75
    nonisolated static let minimumBoardOpacity = 0.35
    nonisolated static let maximumBoardOpacity = 1.0
    nonisolated static let boardOpacityKey = "DaBin.boardOpacity.v1"
    nonisolated static let darkModeKey = "DaBin.darkMode.v1"

    @Published private(set) var selectedHex: String
    @Published private(set) var boardOpacity: Double
    @Published private(set) var darkModeEnabled: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, systemDarkMode: Bool? = nil) {
        self.defaults = defaults
        selectedHex = Self.normalizedHex(defaults.string(forKey: Self.defaultsKey) ?? "") ?? Self.defaultHex
        if let saved = defaults.object(forKey: Self.boardOpacityKey) as? NSNumber,
           saved.doubleValue.isFinite,
           (Self.minimumBoardOpacity...Self.maximumBoardOpacity).contains(saved.doubleValue) {
            boardOpacity = saved.doubleValue
        } else {
            boardOpacity = Self.defaultBoardOpacity
        }
        if let saved = defaults.object(forKey: Self.darkModeKey) as? Bool {
            darkModeEnabled = saved
        } else {
            darkModeEnabled = systemDarkMode ?? Self.currentSystemDarkMode
        }
    }

    var selection: Color { Self.color(for: selectedHex) }
    var accent: Color { Self.accentColor(for: selectedHex) }

    func select(_ preset: ThemePreset) { setHex(preset.hex) }

    func setBoardOpacity(_ value: Double) {
        guard value.isFinite else { return }
        let clamped = min(Self.maximumBoardOpacity, max(Self.minimumBoardOpacity, value))
        if boardOpacity != clamped { boardOpacity = clamped }
        defaults.set(clamped, forKey: Self.boardOpacityKey)
    }

    /// The user's preference remains stored while macOS temporarily requests
    /// solid surfaces for readability.
    nonisolated static func effectiveBoardOpacity(preferred: Double,
                                                  reduceTransparency: Bool) -> Double {
        reduceTransparency ? maximumBoardOpacity
            : min(maximumBoardOpacity, max(minimumBoardOpacity, preferred))
    }

    func setDarkMode(_ enabled: Bool) {
        if darkModeEnabled != enabled { darkModeEnabled = enabled }
        defaults.set(enabled, forKey: Self.darkModeKey)
    }

    /// Stores an opaque sRGB choice even when the color picker supplies a different color space.
    func setColor(_ color: Color) { setColor(NSColor(color)) }

    func setColor(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return }
        let values = components.map { Int((max(0, min(1, $0)) * 255).rounded()) }
        setHex(String(format: "%02X%02X%02X", values[0], values[1], values[2]))
    }

    @discardableResult
    func setHex(_ value: String) -> Bool {
        guard let normalized = Self.normalizedHex(value) else { return false }
        if selectedHex != normalized { selectedHex = normalized }
        defaults.set(normalized, forKey: Self.defaultsKey)
        return true
    }

    nonisolated static func normalizedHex(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("#") { candidate.removeFirst() }
        guard candidate.utf8.count == 6,
              candidate.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return candidate.uppercased()
    }

    nonisolated static func color(for hex: String) -> Color {
        Color(nsColor: RGB(hex: normalizedHex(hex) ?? defaultHex).color)
    }

    private static var currentSystemDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    nonisolated static func accentColor(for hex: String) -> Color {
        Color(nsColor: accentNSColor(for: hex))
    }

    nonisolated static func accentNSColor(for hex: String) -> NSColor {
        let normalized = normalizedHex(hex) ?? defaultHex
        let light = resolvedAccentColor(for: normalized, dark: false)
        let dark = resolvedAccentColor(for: normalized, dark: true)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Accents also appear on slightly tinted cards, so use the least favorable solid surface.
    nonisolated static func resolvedAccentColor(for hex: String, dark: Bool) -> NSColor {
        let normalized = normalizedHex(hex) ?? defaultHex
        if normalized == defaultHex { return RGB(hex: dark ? "AB92C6" : defaultHex).color }
        let source = RGB(hex: normalized)
        let background = RGB(hex: dark ? "2D2A30" : "F3F1F5")
        guard source.contrast(with: background) < 4.5 else { return source.color }
        let destination = RGB(hex: dark ? "FFFFFF" : "000000")
        var lower = 0.0
        var upper = 1.0
        // Mix only as much white or black as needed; this retains the chosen hue.
        for _ in 0..<24 {
            let midpoint = (lower + upper) / 2
            if source.mixed(with: destination, amount: midpoint).contrast(with: background) >= 4.5 {
                upper = midpoint
            } else {
                lower = midpoint
            }
        }
        return source.mixed(with: destination, amount: upper).color
    }
}

private struct RGB {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        red = Double((value >> 16) & 255) / 255
        green = Double((value >> 8) & 255) / 255
        blue = Double(value & 255) / 255
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    private var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: RGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    func mixed(with other: RGB, amount: Double) -> RGB {
        RGB(red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount)
    }
}
