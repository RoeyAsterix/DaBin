import AppKit

/// AppKit lifecycle boundary. Construction and service ownership live in the
/// coordinator; this delegate handles macOS events and user quit decisions.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var application: ApplicationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        do {
            let application = try ApplicationCoordinator()
            self.application = application
            let firstLaunch = application.claimFirstLaunchDailyPresentation()
            application.start(showDaily: firstLaunch || CommandLine.arguments.contains("--show-daily"))
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
        guard application?.state.hasUnsavedDrafts == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Keep editing your unsaved changes?"
        alert.informativeText = "Your saved captures are safe. Any unfinished new task, comment or reminder edits will be lost if you quit."
        alert.addButton(withTitle: "Keep editing")
        alert.addButton(withTitle: "Quit without edits")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        application?.shutdown()
        application = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, application?.corners.board.isVisible != true { application?.corners.openDaily() }
        return false
    }
}
