import SwiftUI
import UniformTypeIdentifiers

enum TaskAttachmentTypes {
    static let identifiers = [UTType.fileURL.identifier, UTType.url.identifier, UTType.image.identifier,
        UTType.pdf.identifier, UTType.movie.identifier, UTType.text.identifier, UTType.data.identifier]
}

@MainActor
struct TaskAttachmentsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var task: Capture
    var minimumCardWidth: CGFloat = 125
    var thumbnailHeight: CGFloat = 100
    @Environment(\.daBinAccent) private var accent
    @State private var targeted = false
    private var attachments: [Capture] { state.store.attachments(for: task) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Label("Attachments", systemImage: "paperclip").font(.system(size: 13, weight: .semibold))
                if !attachments.isEmpty { Text("\(attachments.count)").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
                BuddyIconButton(symbol: "doc.on.clipboard", title: "Paste into task") { state.pasteAttachments(to: task) }
                    .disabled(state.isImporting).accessibilityIdentifier("task-paste-attachments")
                BuddyIconButton(symbol: "plus", title: "Add files to task") { state.importTaskAttachments(to: task) }
                    .disabled(state.isImporting).accessibilityIdentifier("task-add-attachments")
            }
            if attachments.isEmpty {
                Text("Drop files here or paste anything into this task.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 12)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCardWidth), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(attachments) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Button { state.openCapture(item.id) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    CaptureThumbnail(store: state.store, capture: item).frame(height: thumbnailHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Open attachment \(item.title)")
                            HStack {
                                CaptureSourceIcon(capture: item, size: 14)
                                Text(captureClock(item)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Spacer(minLength: 0)
                                CaptureControls(state: state, capture: item)
                            }
                        }
                    }
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(targeted ? 0.1 : 0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(targeted ? 0.7 : 0.2), style: StrokeStyle(lineWidth: 1, dash: attachments.isEmpty ? [4, 4] : [])))
            .onDrop(of: TaskAttachmentTypes.identifiers, isTargeted: $targeted) { state.receiveTaskAttachments($0, to: task) }
            .accessibilityElement(children: .contain).accessibilityLabel("Task attachments")
    }
}
