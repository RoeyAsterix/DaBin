import AppKit

extension AutoCaptureSignReceipt {
    /// Receipt construction deliberately never reads titles, text, filenames,
    /// projects, source applications or previews from the successful action.
    init?(savedAction action: AutoCaptureSavedAction) {
        guard !action.captures.isEmpty else { return nil }
        switch action.origin {
        case .automaticScreenshot: self.init(kind: .screenshot, count: 1)
        case .automaticClipboard: self.init(kind: .clipboard, count: 1)
        case .manual: return nil
        }
    }
}

/// The system screenshot UI is a best-effort suspension signal, not a global
/// screen-capture detector. A completed file/clipboard receipt remains the only
/// success trigger; macOS has no public veto over another app's screenshots.
enum AutoCaptureScreenshotActivity {
    static func isSystemCaptureTool(_ bundleIdentifier: String?) -> Bool {
        switch bundleIdentifier?.lowercased() {
        case "com.apple.screencaptureui", "com.apple.screenshot.launcher": return true
        default: return false
        }
    }
}
