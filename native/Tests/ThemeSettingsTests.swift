import AppKit
import SwiftUI

@main
struct ThemeSettingsTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinThemeSettingsTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return linear(rgb.redComponent) * 0.2126 + linear(rgb.greenComponent) * 0.7152 + linear(rgb.blueComponent) * 0.0722
    }

    private static func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        let values = [luminance(first), luminance(second)]
        return (values.max()! + 0.05) / (values.min()! + 0.05)
    }

    private static func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB)!
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    private static func resolved(_ color: NSColor, dark: Bool) -> NSColor {
        var result: NSColor!
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)!
        }
        return result
    }

    @MainActor static func main() throws {
        let suiteName = "DaBin.ThemeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ThemeSettings(defaults: defaults, systemDarkMode: false)
        try expect(settings.boardOpacity == ThemeSettings.defaultBoardOpacity,
                   "A new profile starts with the 75 percent board opacity")
        try expect(!settings.darkModeEnabled, "A new profile follows the supplied light system appearance")
        try expect(settings.selectedHex == "6D5387", "A new profile starts with the original purple")
        try expect(defaults.persistentDomain(forName: suiteName) == nil,
                   "Reading an unset preference does not create any persisted settings")

        settings.setBoardOpacity(0.55)
        try expect(settings.boardOpacity == 0.55 && defaults.double(forKey: ThemeSettings.boardOpacityKey) == 0.55,
                   "Transparency control updates the live board and stored opacity")
        try expect(ThemeSettings(defaults: defaults, systemDarkMode: true).boardOpacity == 0.55,
                   "Background opacity survives settings reinitialization")
        settings.setBoardOpacity(0.1)
        try expect(settings.boardOpacity == ThemeSettings.minimumBoardOpacity,
                   "Background opacity stays above the readable minimum")
        settings.setBoardOpacity(2)
        try expect(settings.boardOpacity == ThemeSettings.maximumBoardOpacity,
                   "Background opacity stays at or below fully opaque")
        settings.setBoardOpacity(.nan)
        try expect(settings.boardOpacity == ThemeSettings.maximumBoardOpacity,
                   "A non-finite opacity cannot corrupt the appearance preference")
        defaults.set("invalid opacity", forKey: ThemeSettings.boardOpacityKey)
        try expect(ThemeSettings(defaults: defaults, systemDarkMode: false).boardOpacity == ThemeSettings.defaultBoardOpacity,
                   "Malformed stored opacity falls back without affecting the archive")
        settings.setBoardOpacity(ThemeSettings.defaultBoardOpacity)
        try expect(ThemeSettings.effectiveBoardOpacity(preferred: 0.35, reduceTransparency: true) == 1,
                   "Reduce Transparency forces a solid board surface")
        try expect(ThemeSettings.effectiveBoardOpacity(preferred: 0.55, reduceTransparency: false) == 0.55,
                   "The stored opacity remains effective when Reduce Transparency is off")

        settings.setDarkMode(true)
        try expect(settings.darkModeEnabled && defaults.bool(forKey: ThemeSettings.darkModeKey),
                   "Dark mode toggle updates the live and stored appearance")
        try expect(ThemeSettings(defaults: defaults, systemDarkMode: false).darkModeEnabled,
                   "Dark mode survives settings reinitialization")
        settings.setDarkMode(false)
        try expect(!settings.darkModeEnabled && !ThemeSettings(defaults: defaults, systemDarkMode: true).darkModeEnabled,
                   "Turning dark mode off explicitly selects light mode")
        defaults.set("unrelated-value", forKey: "unrelated")
        for preset in ThemePreset.allCases {
            settings.select(preset)
            try expect(settings.selectedHex == preset.hex && defaults.string(forKey: ThemeSettings.defaultsKey) == preset.hex,
                       "\(preset.name) updates both live and stored choice")
            try expect(ThemeSettings(defaults: defaults).selectedHex == preset.hex,
                       "\(preset.name) survives settings reinitialization")
        }
        try expect(defaults.string(forKey: "unrelated") == "unrelated-value", "Choosing a theme preserves unrelated settings")
        try expect(settings.setHex(" #a1b2c3\n") && settings.selectedHex == "A1B2C3", "Custom hex normalizes surrounding whitespace, hash, and case")
        for invalid in ["", "#", "abc", "1234567", "11223344", "#GGHHII", "#12 456", "#１２３４５６"] {
            try expect(!settings.setHex(invalid) && settings.selectedHex == "A1B2C3",
                       "Malformed custom color does not replace the existing selection: \(invalid)")
        }
        try expect(defaults.string(forKey: ThemeSettings.defaultsKey) == "A1B2C3", "Rejected custom colors leave persisted selection unchanged")

        for invalid: Any in ["not a color", 42, ["hex": "123456"], true] {
            defaults.set(invalid, forKey: ThemeSettings.defaultsKey)
            let before = defaults.persistentDomain(forName: suiteName)! as NSDictionary
            try expect(ThemeSettings(defaults: defaults).selectedHex == ThemeSettings.defaultHex, "Malformed saved color falls back to purple")
            try expect(before.isEqual(to: defaults.persistentDomain(forName: suiteName)!), "Reading malformed saved color never rewrites preferences")
        }
        defaults.set("#abcdef", forKey: ThemeSettings.defaultsKey)
        try expect(ThemeSettings(defaults: defaults).selectedHex == "ABCDEF", "A valid previously saved custom color is normalized on load")
        settings.setColor(Color(red: 0.2, green: 0.4, blue: 0.6))
        try expect(settings.selectedHex == "336699", "SwiftUI color picker value is stored as sRGB")
        settings.setColor(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.3))
        try expect(settings.selectedHex == "336699" && NSColor(settings.selection).alphaComponent == 1,
                   "Custom selection stays opaque even if a source supplies alpha")
        settings.setColor(NSColor(deviceWhite: 0.5, alpha: 1))
        try expect(ThemeSettings.normalizedHex(settings.selectedHex) != nil, "Grayscale color spaces can be stored")
        try expect(Set(defaults.persistentDomain(forName: suiteName)!.keys)
                   == [ThemeSettings.defaultsKey, ThemeSettings.boardOpacityKey, ThemeSettings.darkModeKey, "unrelated"],
                   "Appearance changes store only their three dedicated preferences")

        try expect(hex(ThemeSettings.resolvedAccentColor(for: ThemeSettings.defaultHex, dark: false)) == "6D5387", "Light default accent matches the original app")
        try expect(hex(ThemeSettings.resolvedAccentColor(for: ThemeSettings.defaultHex, dark: true)) == "AB92C6", "Dark default accent matches the original app")
        let choices = ThemePreset.allCases.map(\.hex) + ["000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "888888", "F0F0FA"]
        for choice in choices {
            let adaptive = ThemeSettings.accentNSColor(for: choice)
            for dark in [false, true] {
                let color = ThemeSettings.resolvedAccentColor(for: choice, dark: dark)
                let surfaces = dark ? ["1D1C21", "252328", "2D2A30"] : ["FDFCFE", "FFFFFF", "F3F1F5"]
                for surface in surfaces {
                    let background = NSColor(ThemeSettings.color(for: surface))
                    try expect(contrast(color, background) >= 4.5 - 0.000001,
                               "\(choice) remains readable against \(surface)")
                }
                try expect(hex(resolved(adaptive, dark: dark)) == hex(color),
                           "\(choice) dynamic accent resolves correctly in \(dark ? "dark" : "light") appearance")
            }
        }
        try expect(hex(resolved(ThemeSettings.accentNSColor(for: "invalid"), dark: true)) == "AB92C6",
                   "Invalid helper input also resolves to the safe default")

        let robotSuiteName = "DaBin.RobotPlacementSettingsTests.\(UUID().uuidString)"
        let robotDefaults = UserDefaults(suiteName: robotSuiteName)!
        defer { robotDefaults.removePersistentDomain(forName: robotSuiteName) }
        let robotSettings = RobotPlacementSettings(defaults: robotDefaults)
        try expect(robotSettings.home == .corners && robotDefaults.persistentDomain(forName: robotSuiteName) == nil,
                   "A new profile uses corners without writing a preference")
        robotSettings.setHome(.cameraIsland)
        try expect(robotSettings.home == .cameraIsland
                   && robotDefaults.string(forKey: RobotPlacementSettings.defaultsKey) == RobotHome.cameraIsland.rawValue,
                   "Camera-island home updates the live and stored preference")
        try expect(RobotPlacementSettings(defaults: robotDefaults).home == .cameraIsland,
                   "Robot home survives settings reinitialization")
        robotDefaults.set("future-invalid-value", forKey: RobotPlacementSettings.defaultsKey)
        let malformedSnapshot = robotDefaults.persistentDomain(forName: robotSuiteName)! as NSDictionary
        try expect(RobotPlacementSettings(defaults: robotDefaults).home == .corners,
                   "An unknown robot home falls back safely to corners")
        try expect(malformedSnapshot.isEqual(to: robotDefaults.persistentDomain(forName: robotSuiteName)!),
                   "Reading an unknown robot home never rewrites preferences")
        let isolatedRobotSettings = RobotPlacementSettings(defaults: nil)
        isolatedRobotSettings.setHome(.cameraIsland)
        try expect(isolatedRobotSettings.home == .cameraIsland,
                   "An isolated robot preference supports previews without persistent defaults")
        print("PASS: \(checks) theme settings checks")
    }
}
