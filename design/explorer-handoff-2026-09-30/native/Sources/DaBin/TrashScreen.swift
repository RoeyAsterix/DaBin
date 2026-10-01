import SwiftUI

@MainActor
struct TrashScreen: View {
    @ObservedObject var state: AppState
    @State private var pendingPermanentRemoval: Capture?

    var body: some View {
        Group {
            if state.store.trashedCaptures.isEmpty {
                EmptyMessage(symbol: "trash", title: "Nothing in Recently Deleted", message: "Removed captures appear here until you restore or permanently delete them.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Restore a capture with its saved content and notes.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 10)
                        ForEach(state.store.trashedCaptures) { capture in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                                    .font(.system(size: 14, weight: .medium)).lineLimit(3)
                                if let deletedAt = capture.deletedAt {
                                    Text("Deleted \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                HStack(spacing: 12) {
                                    Button("Restore") { Task { await state.restoreCapture(capture) } }
                                    Spacer(minLength: 0)
                                    Button("Delete permanently…", role: .destructive) { pendingPermanentRemoval = capture }
                                }.font(.system(size: 12)).disabled(state.removingCaptureID != nil)
                            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
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
    }
}
