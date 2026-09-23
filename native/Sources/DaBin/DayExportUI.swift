import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TimelinePrimaryAction: String, CaseIterable, Identifiable {
    case add, search, exportDay, notifications, settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .add: return "plus"
        case .search: return "magnifyingglass"
        case .exportDay: return "square.and.arrow.up"
        case .notifications: return "bell"
        case .settings: return "gearshape"
        }
    }

    var label: String {
        switch self {
        case .add: return "Add task"
        case .search: return "Search captures, Command K"
        case .exportDay: return "Export Day"
        case .notifications: return "Notifications"
        case .settings: return "Settings and options"
        }
    }
}

enum DayExportDestinationSelection: Equatable {
    case selected(URL)
    case cancelled
}

enum DayExportSaveOutcome: Equatable {
    case saved(URL)
    case cancelled
    case failed(String)
    case nothingToExport
}

enum DayExportActionFeedback: Equatable {
    case copied
    case saved
    case failed(String)

    var symbol: String {
        switch self {
        case .copied, .saved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var message: String {
        switch self {
        case .copied: return "Day copied."
        case .saved: return "Text file exported."
        case .failed(let message): return message
        }
    }
}

/// Owns transient export UI state and isolates pasteboard, panel and file IO so
/// the same outcomes can be exercised without touching a user's clipboard.
@MainActor
final class DayExportActionController: ObservableObject {
    typealias PasteboardWriter = (String) -> Bool
    typealias DestinationChooser = (String) -> DayExportDestinationSelection
    typealias FileWriter = (Data, URL) throws -> Void

    @Published var isPresented = false
    @Published private(set) var feedback: DayExportActionFeedback?

    private let pasteboardWriter: PasteboardWriter
    private let destinationChooser: DestinationChooser
    private let fileWriter: FileWriter
    private var dismissalTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?

    init(pasteboardWriter: @escaping PasteboardWriter,
         destinationChooser: @escaping DestinationChooser,
         fileWriter: @escaping FileWriter) {
        self.pasteboardWriter = pasteboardWriter
        self.destinationChooser = destinationChooser
        self.fileWriter = fileWriter
    }

    deinit {
        dismissalTask?.cancel()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    static func live() -> DayExportActionController {
        DayExportActionController(pasteboardWriter: { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }, destinationChooser: { filename in
            let panel = NSSavePanel()
            panel.title = "Export Day"
            panel.prompt = "Export"
            panel.nameFieldStringValue = filename
            panel.allowedContentTypes = [.plainText]
            panel.allowsOtherFileTypes = false
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
            return .selected(url)
        }, fileWriter: { data, url in
            try data.write(to: url, options: .atomic)
        })
    }

    func togglePresentation() {
        if isPresented { dismiss() } else { present() }
    }

    func present() {
        dismissalTask?.cancel()
        feedback = nil
        isPresented = true
        let presentingWindow = NSApplication.shared.currentEvent?.windowNumber
            ?? NSApplication.shared.keyWindow?.windowNumber
        installOutsideClickMonitor(for: presentingWindow)
    }

    func updatePresentation(_ presented: Bool) {
        if presented { present() } else { dismiss() }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        isPresented = false
        feedback = nil
    }

    @discardableResult
    func copy(_ document: DayExportDocument) -> Bool {
        guard !document.isEmpty else { return false }
        if pasteboardWriter(document.text) {
            feedback = .copied
            dismissAfterFeedback()
            return true
        }
        feedback = .failed("Couldn’t copy this day.")
        return false
    }

    @discardableResult
    func save(_ document: DayExportDocument) -> DayExportSaveOutcome {
        guard !document.isEmpty else { return .nothingToExport }
        feedback = nil
        switch destinationChooser(document.filename) {
        case .cancelled:
            return .cancelled
        case .selected(let url):
            do {
                try fileWriter(document.utf8Data, url)
                feedback = .saved
                dismissAfterFeedback()
                return .saved(url)
            } catch {
                let message = "Couldn’t export this day: \(error.localizedDescription)"
                feedback = .failed(message)
                return .failed(message)
            }
        }
    }

    private func dismissAfterFeedback() {
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.15))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func installOutsideClickMonitor(for presentingWindowNumber: Int?) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        guard let presentingWindowNumber else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            if event.windowNumber == presentingWindowNumber {
                // Dispatch after the click so its intended board control still
                // receives the event. Clicking the trigger again therefore
                // closes the popover instead of immediately reopening it.
                DispatchQueue.main.async { self?.dismiss() }
            }
            return event
        }
    }
}

@MainActor
struct DayExportButton: View {
    @ObservedObject var state: AppState
    let selectedDate: Date
    @ObservedObject var controller: DayExportActionController

    init(state: AppState, selectedDate: Date,
         controller: DayExportActionController) {
        self.state = state
        self.selectedDate = selectedDate
        self.controller = controller
    }

    private var document: DayExportDocument {
        DayExportDocument.make(captures: state.store.captures, selectedDate: selectedDate)
    }

    private var presentation: Binding<Bool> {
        Binding(get: { controller.isPresented }, set: { controller.updatePresentation($0) })
    }

    var body: some View {
        AccentIconButton(symbol: TimelinePrimaryAction.exportDay.symbol,
                         label: TimelinePrimaryAction.exportDay.label,
                         accessibilityIdentifier: "timeline-action-export-day") {
            controller.togglePresentation()
        }
        .popover(isPresented: presentation, arrowEdge: .bottom) {
            DayExportPopover(document: document, controller: controller) { message in
                state.reportFailure(message)
            }
        }
        .onChange(of: selectedDate) { _, _ in controller.dismiss() }
        .onDisappear { controller.dismiss() }
    }
}

@MainActor
private struct DayExportPopover: View {
    enum Choice: Hashable { case copy, file }

    @Environment(\.daBinAccent) private var accent
    let document: DayExportDocument
    @ObservedObject var controller: DayExportActionController
    let reportFailure: (String) -> Void
    @FocusState private var focusedChoice: Choice?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export \(document.day)")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            exportChoice(title: "Copy Day", symbol: "doc.on.doc", choice: .copy,
                         shortcut: "c", shortcutLabel: "⌘C") {
                controller.copy(document)
            }
            exportChoice(title: "Export Text File", symbol: "doc.text", choice: .file,
                         shortcut: "s", shortcutLabel: "⌘S") {
                let outcome = controller.save(document)
                if case .failed(let message) = outcome { reportFailure(message) }
            }

            if document.isEmpty {
                Text("Nothing to export.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel("Nothing to export")
            } else if let feedback = controller.feedback {
                HStack(spacing: 6) {
                    Image(systemName: feedback.symbol)
                        .foregroundStyle(feedbackColor(feedback))
                        .accessibilityHidden(true)
                    Text(feedback.message)
                }
                .font(.system(size: 11, weight: .medium))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(width: 226)
        .onAppear {
            guard !document.isEmpty else { return }
            DispatchQueue.main.async { focusedChoice = .copy }
        }
        .onExitCommand { controller.dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Export day actions")
    }

    private func exportChoice(title: String, symbol: String, choice: Choice,
                              shortcut: KeyEquivalent, shortcutLabel: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(shortcutLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(focusedChoice == choice ? accent.opacity(0.16) : Palette.soft,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(focusedChoice == choice ? accent : .clear, lineWidth: 1.25)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .focused($focusedChoice, equals: choice)
        .disabled(document.isEmpty)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint(document.isEmpty ? "Nothing to export" :
            (choice == .copy ? "Copies this day as plain text" : "Saves this day as a UTF-8 text file"))
    }

    private func feedbackColor(_ feedback: DayExportActionFeedback) -> Color {
        if case .failed = feedback { return Palette.task }
        return .green
    }
}
