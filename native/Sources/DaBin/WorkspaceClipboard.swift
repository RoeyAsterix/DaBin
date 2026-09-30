import AppKit

@MainActor
enum WorkspaceClipboard {
    /// Plain text is an explicit clipboard write. It never requests Accessibility
    /// permission or synthesizes a keystroke into an unrelated working app.
    static func copyPlainText(_ capture: Capture, to pasteboard: NSPasteboard = .general) throws {
        guard let text = WorkspaceQuery.plainText(capture) else { throw WorkspaceError.missingContent }
        try write(text, to: pasteboard)
    }

    static func copyManagedPath(_ capture: Capture, store: CaptureStore, to pasteboard: NSPasteboard = .general) throws {
        guard let url = store.managedURL(for: capture) else {
            throw CaptureClipboardError.missingSavedOriginal(capture.originalFilename ?? capture.title)
        }
        try write(url.path, to: pasteboard)
    }

    static func write(_ text: String, to pasteboard: NSPasteboard = .general) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw CaptureClipboardError.writeFailed }
    }
}
