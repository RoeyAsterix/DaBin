import SwiftUI

@MainActor
struct ScratchpadView: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    var noteContext: WorkspaceScratchpad? = nil
    @Environment(\.daBinAccent) private var accent
    @State private var message: String?
    @StateObject private var successPresentation = TransientMessagePresentation<String>()
    @State private var savedCaptureID: UUID?
    @State private var savedText: String?

    private var project: String? {
        if let noteContext { return noteContext.projectName }
        return state.libraryProject
    }
    private var text: String { workspace.scratchpad(project: project) }
    private var pending: Bool { workspace.pendingScratchpads[WorkspaceSnapshot.projectKey(project)] != nil }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(project.map { "\($0) notes" } ?? "Scratchpad", systemImage: "note.text")
                    .font(.system(size: zoom.fontSize(18), weight: .semibold, design: .rounded)).lineLimit(2)
                    .buddyHelp(project.map { "\($0) notes" } ?? "Scratchpad")
                    .nativeContentDrag(label: project.map { "\($0) notes" } ?? "Scratchpad", items: {
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [text as NSString]
                    }, onError: { state.reportFailure($0.localizedDescription) })
                Spacer(minLength: 0)
                Label(pending ? "Not saved" : "Autosaved", systemImage: pending ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: zoom.fontSize(12))).foregroundStyle(pending ? Palette.task : Palette.muted).fixedSize()
                    .accessibilityLabel(pending ? "Scratchpad has unsaved changes" : "Scratchpad saved locally")
                    .accessibilityIdentifier("workspace-scratchpad-save-status")
            }
            HStack(spacing: 10) {
                if pending {
                    Button("Retry save", systemImage: "arrow.clockwise") {
                        do { try workspace.setScratchpad(text: text, project: project); clearFeedback() }
                        catch { successPresentation.dismiss(); message = error.localizedDescription }
                    }
                } else {
                    Button("Save note", systemImage: "square.and.arrow.down") { saveNote(asTask: false) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Make task", systemImage: "checkmark.circle") { saveNote(asTask: true) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer(minLength: 0)
            }.font(.system(size: zoom.fontSize(13))).tint(accent)
            Text("A place to think. Your notes stay on this Mac after you close DaBin.")
                .font(.system(size: zoom.fontSize(14))).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: Binding(get: { text }, set: { value in
                do { try workspace.setScratchpad(text: value, project: project); clearFeedback() }
                catch { successPresentation.dismiss(); message = error.localizedDescription }
            }))
            .font(.system(size: zoom.fontSize(14))).lineSpacing(zoom.lineSpacing(4)).scrollContentBackground(.hidden)
            .padding(12).frame(height: max(220, geometry.size.height - 220))
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.75))
            .accessibilityLabel("Autosaving scratchpad")
            .accessibilityIdentifier("workspace-scratchpad")
            if let message = message ?? successPresentation.visibleMessage {
                Text(message).font(.system(size: zoom.fontSize(13))).foregroundStyle(pending ? Palette.task : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Save note adds a copy to your library. Make task keeps the original text and opens its next actions.")
                .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.workspaceZoomItem("note:" + WorkspaceSnapshot.projectKey(project)).frame(maxWidth: zoom.value(740)).padding(.horizontal, 16).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .top)
            .onChange(of: project) { _, _ in clearFeedback(); savedCaptureID = nil; savedText = nil }
            .onDisappear { successPresentation.dismiss() }
        }.background {
            WorkspaceScrollHistory(anchor: state.workspaceViewport, contextID: "note-" + WorkspaceSnapshot.projectKey(project),
                onAnchor: { state.workspaceViewport = $0 }).allowsHitTesting(false).accessibilityHidden(true)
        }
        }
    }

    private func saveNote(asTask: Bool) {
        do {
            let capture: Capture
            // Repeated clicks on an unchanged scratchpad reuse the just-created
            // receipt, including a promotion from saved note to task.
            if savedText == text, let id = savedCaptureID, let existing = state.store.captures.first(where: { $0.id == id }) {
                capture = existing
            } else {
                capture = try state.store.createNote(text: text, projectName: project)
                savedCaptureID = capture.id; savedText = text
                state.didCapture([capture])
            }
            if asTask {
                clearFeedback()
                if capture.isTask { state.openCapture(capture.id, focus: "task") }
                else { state.convertToTask(capture, openDetails: true) }
            } else {
                message = nil
                successPresentation.present("Saved in \(project ?? "your library"). Your scratchpad is still here.")
                workspace.selectedCaptureID = capture.id
            }
        } catch {
            successPresentation.dismiss()
            message = "Couldn’t save this note. " + error.localizedDescription
        }
    }

    private func clearFeedback() {
        message = nil
        successPresentation.dismiss()
    }
}
