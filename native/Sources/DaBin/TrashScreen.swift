import SwiftUI

@MainActor
struct TrashScreen: View {
    @ObservedObject var state: AppState
    @ObservedObject private var workspace: WorkspaceStore
    @State private var pendingPermanentRemoval: Capture?
    @State private var pendingNoteRemoval: WorkspaceDeletedScratchpad?

    init(state: AppState) {
        self.state = state
        workspace = state.workspace
    }

    var body: some View {
        Group {
            if state.store.trashedCaptures.isEmpty && workspace.deletedScratchpads.isEmpty {
                EmptyMessage(symbol: "trash", title: "Nothing in Recently Deleted", message: "Removed captures and live notes appear here until you restore or permanently delete them.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Restore saved content and notes. Restoring live notes keeps any new notes you have written.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 10)
                        ForEach(state.store.trashedCaptures) { capture in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                                    .font(.system(size: 14, weight: .medium)).lineLimit(3)
                                if let deletedAt = capture.deletedAt { deletionDate(deletedAt) }
                                HStack(spacing: 12) {
                                    Button("Restore") { Task { await state.restoreCapture(capture) } }
                                        .accessibilityIdentifier("trash-restore-\(capture.id.uuidString)")
                                    Spacer(minLength: 0)
                                    Button("Delete permanently…", role: .destructive) { pendingPermanentRemoval = capture }
                                        .accessibilityIdentifier("trash-delete-\(capture.id.uuidString)")
                                }.font(.system(size: 12)).disabled(state.removingCaptureID != nil)
                            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
                        }
                        ForEach(workspace.deletedScratchpads) { receipt in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(receipt.note.projectName.map { "\($0) notes" } ?? "Scratchpad", systemImage: "note.text")
                                    .font(.system(size: 14, weight: .medium)).lineLimit(2)
                                Text(receipt.note.text).font(.system(size: 12)).lineLimit(3)
                                deletionDate(receipt.deletedAt)
                                HStack(spacing: 12) {
                                    Button("Restore") { state.restoreScratchpad(receipt) }
                                        .accessibilityIdentifier("trash-note-restore-\(receipt.id.uuidString)")
                                    Spacer(minLength: 0)
                                    Button("Delete permanently…", role: .destructive) { pendingNoteRemoval = receipt }
                                        .accessibilityIdentifier("trash-note-delete-\(receipt.id.uuidString)")
                                }.font(.system(size: 12)).disabled(state.removingCaptureID != nil)
                            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("trash-note-\(receipt.id.uuidString)")
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
        .alert("Permanently delete this capture?", isPresented: Binding(
            get: { pendingPermanentRemoval != nil }, set: { if !$0 { pendingPermanentRemoval = nil } }
        ), presenting: pendingPermanentRemoval) { capture in
            Button("Cancel", role: .cancel) { pendingPermanentRemoval = nil }
            Button("Delete permanently", role: .destructive) {
                pendingPermanentRemoval = nil
                Task { await state.permanentlyRemoveCapture(capture) }
            }
        } message: { _ in
            Text("This deletes the capture and its saved copies from DaBin. It cannot be undone. Files at their original locations are kept.")
        }
        .alert("Permanently delete these notes?", isPresented: Binding(
            get: { pendingNoteRemoval != nil }, set: { if !$0 { pendingNoteRemoval = nil } }
        ), presenting: pendingNoteRemoval) { receipt in
            Button("Cancel", role: .cancel) { pendingNoteRemoval = nil }
            Button("Delete permanently", role: .destructive) {
                pendingNoteRemoval = nil
                state.permanentlyDeleteScratchpad(receipt)
            }
        } message: { _ in
            Text("This deletes only this removed copy of the notes. It cannot be undone. Current notes and saved project items are kept.")
        }
    }

    private func deletionDate(_ date: Date) -> some View {
        Text("Deleted \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
    }
}
