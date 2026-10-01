import AppKit
import Combine

@MainActor
final class ShelfCaptureController: ObservableObject {
    @Published private(set) var isBusy = false
    private let state: AppState
    private let input: InputService

    init(state: AppState) {
        self.state = state
        input = InputService(store: state.store)
        input.onBusy = { [weak self] in self?.isBusy = $0 }
    }

    func paste(from pasteboard: NSPasteboard = .general) {
        guard !isBusy, !state.isArchiveOperationRunning else { return }
        let project = state.libraryProject
        input.receive(pasteboard, completion: { [self] captures, failures in finish(captures, failures: failures, project: project) })
    }

    func receive(_ providers: [NSItemProvider]) -> Bool {
        guard !isBusy, !state.isArchiveOperationRunning, !providers.isEmpty else { return false }
        let project = state.libraryProject
        input.receiveProviders(providers, completion: { [self] captures, failures in finish(captures, failures: failures, project: project) })
        return true
    }

    func chooseFiles() {
        guard !isBusy, !state.isArchiveOperationRunning else { return }
        let picker = NSOpenPanel()
        picker.title = "Add files to the shelf"
        picker.message = "DaBin keeps a local copy. Your original files stay where they are."
        picker.prompt = "Add to shelf"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        let urls = picker.urls
        let project = state.libraryProject
        let timestamp = Date()
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            var captured: [Capture] = []
            var failures: [String] = []
            for url in urls {
                do { captured.append(try await state.store.importFile(url, at: timestamp)) }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            finish(captured, failures: failures, project: project)
        }
    }

    private func finish(_ captures: [Capture], failures: [String], project: String?) {
        var errors = failures
        do {
            if let project {
                for capture in captures { try state.store.setOrganization(capture, pinned: false, projectName: project) }
            }
            try state.workspace.setOnShelf(captures.map(\.id), included: true)
        } catch { errors.append("Items were captured, but couldn’t be added to this shelf: " + error.localizedDescription) }
        state.reportCaptureResult(captures, errors: errors)
        if errors.isEmpty, !captures.isEmpty {
            state.status = AppStatusMessage(text: "\(captures.count) \(captures.count == 1 ? "item" : "items") saved to your shelf.", severity: .success)
        }
    }
}
