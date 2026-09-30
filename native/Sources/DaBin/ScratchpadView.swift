import SwiftUI

@MainActor
struct ScratchpadView: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @Environment(\.daBinAccent) private var accent
    @State private var message: String?
    @State private var savedCaptureID: UUID?
    @State private var savedText: String?

    private var project: String? { state.libraryProject }
    private var text: String { workspace.scratchpad(project: project) }
    private var pending: Bool { workspace.pendingScratchpads[WorkspaceSnapshot.projectKey(project)] != nil }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(project.map { "\($0) notes" } ?? "Scratchpad", systemImage: "note.text")
                    .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Label(pending ? "Not saved" : "Autosaved", systemImage: pending ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(pending ? Palette.task : Palette.muted)
                    .accessibilityLabel(pending ? "Scratchpad has unsaved changes" : "Scratchpad saved locally")
            }
            HStack(spacing: 10) {
                if pending {
                    Button("Retry save", systemImage: "arrow.clockwise") {
                        do { try workspace.setScratchpad(text: text, project: project); message = nil }
                        catch { message = error.localizedDescription }
                    }
                } else {
                    Button("Save note", systemImage: "square.and.arrow.down") { saveNote(asTask: false) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Make task", systemImage: "checkmark.circle") { saveNote(asTask: true) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer(minLength: 0)
            }.font(.system(size: 12)).tint(accent)
            Text("A place to think. Your notes stay on this Mac after you close DaBin.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: Binding(get: { text }, set: { value in
                do { try workspace.setScratchpad(text: value, project: project); message = nil }
                catch { message = error.localizedDescription }
            }))
            .font(.system(size: 14)).scrollContentBackground(.hidden)
            .padding(10).frame(height: 220)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
            .accessibilityLabel("Autosaving scratchpad")
            .accessibilityIdentifier("workspace-scratchpad")
            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(pending ? Palette.task : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Save note adds a copy to your library. Make task keeps the original text and opens its next actions.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 16).padding(.bottom, 16)
            .onChange(of: project) { _, _ in message = nil; savedCaptureID = nil; savedText = nil }
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
                if capture.isTask { state.openCapture(capture.id, focus: "task") }
                else { state.convertToTask(capture) }
            } else {
                message = "Saved in \(project ?? "your library"). Your scratchpad is still here."
                workspace.selectedCaptureID = capture.id
            }
        } catch { message = "Couldn’t save this note. " + error.localizedDescription }
    }
}
