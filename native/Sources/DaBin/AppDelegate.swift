import AppKit

/// AppKit lifecycle boundary. Construction and service ownership live in the
/// coordinator; this delegate handles macOS events and user quit decisions.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var application: ApplicationCoordinator?
    private let reopenDailyOverride: (() -> Void)?

    init(reopenDaily: (() -> Void)? = nil) {
        reopenDailyOverride = reopenDaily
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        do {
            let application = try ApplicationCoordinator()
            self.application = application
            // Launching the app in Finder must always show its window. As an
            // accessory app, a hidden cold launch otherwise looks like failure.
            // Background capture continues only after the user hides the board.
            application.start(showDaily: true)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "DaBin couldn’t open its archive"
            alert.informativeText = "Your saved files have been left in place.\n\n\(error.localizedDescription)\n\nQuit and try again, or use the storage path in the README to diagnose the archive."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let message = application?.terminationBlock {
            let alert = NSAlert()
            alert.messageText = "DaBin is finishing a removal"
            alert.informativeText = message
            alert.addButton(withTitle: "Keep open")
            alert.runModal()
            return .terminateCancel
        }
        if application?.input.isBusy == true {
            let alert = NSAlert()
            alert.messageText = "DaBin is still receiving content"
            alert.informativeText = "Keep DaBin open to finish saving. Quitting now can interrupt files that the source application has not finished providing."
            alert.addButton(withTitle: "Keep receiving")
            alert.addButton(withTitle: "Quit anyway")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        application?.state.persistDrafts()
        guard application?.state.draftPersistenceError != nil || application?.state.workspace.hasUnsavedChanges == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Some drafts could not be saved locally"
        alert.informativeText = "Keep DaBin open to retry saving. Quitting now can lose the drafts still held in memory. Your previously saved captures are safe."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Quit without edits")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        application?.state.persistDrafts()
        application?.shutdown()
        application = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A floating panel can remain "visible" to AppKit while it is occluded,
        // transparent, or on another display. An explicit reopen must always
        // restore Daily and bring it forward.
        if let reopenDailyOverride { reopenDailyOverride() }
        else { application?.corners.openDaily() }
        return false
    }
}
