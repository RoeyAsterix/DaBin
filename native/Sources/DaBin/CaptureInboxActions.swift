import SwiftUI

@MainActor
extension AppState {
    /// Returning a kept capture must make it eligible for the actual Inbox,
    /// without changing its project, task schedule or original receipt.
    func canReturnCaptureToInbox(_ capture: Capture) -> Bool {
        store.captures.contains { $0 === capture }
            && capture.projectName == nil && capture.parentTaskID == nil
            && !capture.isCompleted && (!capture.isTask || capture.taskPlanning?.plannedDay == nil)
            && workspace.processedInboxIDs.contains(capture.id)
    }

    @discardableResult
    func returnCaptureToInbox(_ capture: Capture) -> Bool {
        guard canReturnCaptureToInbox(capture), !isNavigationBlocked,
              removingCaptureID == nil else { return false }
        do {
            try workspace.markInboxProcessed([capture.id], processed: false)
            beginNavigation(); defer { endNavigation() }
            filter = .all
            openInbox()
            status = AppStatusMessage(text: "Returned to Captions. Your original capture is unchanged.", severity: .success)
            return true
        } catch {
            reportFailure("Could not return this capture to Captions: \(error.localizedDescription)")
            return false
        }
    }
}

@MainActor
struct CaptureReturnToInboxMenuItem: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var store: CaptureStore

    init(state: AppState, capture: Capture) {
        self.state = state; self.capture = capture
        self.workspace = state.workspace; self.store = state.store
    }

    var body: some View {
        if state.canReturnCaptureToInbox(capture) {
            Button("Return to Captions", systemImage: "tray.and.arrow.down") {
                state.returnCaptureToInbox(capture)
            }
            .accessibilityIdentifier("capture-return-to-inbox-\(capture.id.uuidString)")
            .disabled(state.isNavigationBlocked || state.removingCaptureID != nil)
        }
    }
}
