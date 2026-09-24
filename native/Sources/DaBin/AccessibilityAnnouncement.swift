import AppKit

/// Centralizes brief VoiceOver announcements for transient UI that otherwise
/// disappears without moving keyboard focus.
@MainActor
enum AccessibilityAnnouncement {
    static func post(_ message: String,
                     priority: NSAccessibilityPriorityLevel = .medium) {
        guard !message.isEmpty else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue,
            ]
        )
    }
}
