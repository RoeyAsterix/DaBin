import SwiftUI

@MainActor
struct GroupedCaptureCard: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    let group: CaptureCardGroup
    var compact = false
    var showsCopyButton = true
    @State private var confirmsRemoval = false

    private var primary: Capture { group.primary }
    private var title: String { "\(group.captures.count) items" }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            cardHeader

            if !group.isMinimized {
                VStack(spacing: 0) {
                    ForEach(Array(group.captures.enumerated()), id: \.element.id) { index, capture in
                        GroupedCaptureItem(state: state, capture: capture, compact: compact)
                        if index < group.captures.count - 1 {
                            Rectangle().fill(Palette.line).frame(height: 0.5)
                                .padding(.leading, compact ? 44 : 54)
                        }
                    }
                }
                .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.line.opacity(0.75), lineWidth: 0.5))
            }

            if !primary.comment.isEmpty {
                Text(primary.comment).font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(Palette.muted).lineLimit(2)
            }

            HStack {
                Button { state.toggleMinimized(group.captures) } label: {
                    Label(group.isMinimized ? "Show items" : "Collapse", systemImage: group.isMinimized ? "chevron.down" : "minus")
                        .frame(minHeight: 32)
                }.accessibilityLabel(group.isMinimized ? "Expand batch items" : "Collapse batch items")
                Spacer(minLength: 0)
                BuddyIconButton(symbol: "trash", title: "Move batch to Recently Deleted") { confirmsRemoval = true }
                    .accessibilityIdentifier("capture-trash-batch-\(primary.id.uuidString)")
                    .disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning)
                Menu {
                    Button(primary.comment.isEmpty ? "Add note" : "Edit note", systemImage: "text.bubble") { state.openCapture(primary.id, focus: "comment") }
                    Button(primary.reminderAt == nil ? "Add reminder" : "Edit reminder", systemImage: "clock") { state.openCapture(primary.id, focus: "reminder") }
                    Divider()
                    Button("Move batch to Recently Deleted", systemImage: "trash", role: .destructive) { confirmsRemoval = true }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More batch actions").buddyHelp("More batch actions")
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)

            if let reminder = primary.reminderAt {
                Text("Remind \(reminder.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(compact ? 6 : 16)
        .background(Palette.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Palette.line, lineWidth: 0.7))
        .padding(.vertical, compact ? 0 : 6)
        .alert("Move this batch to Recently Deleted?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Move \(group.captures.count) items", role: .destructive) {
                Task { await state.removeCaptures(group.captures) }
            }
        } message: {
            Text("You can restore these captures from Recently Deleted. Files at their original locations are kept.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch of \(group.captures.count) captured items")
    }

    @ViewBuilder
    private var cardHeader: some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    batchSymbol(size: 13, width: 18)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    if showsCopyButton {
                        CaptureCopyButton(state: state, captures: group.captures, compact: true)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(group.isMinimized
                         ? group.captures.map(\.title).joined(separator: " · ")
                         : "Saved together")
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text("\(captureClock(primary)) · Batch").monospacedDigit().fixedSize()
                }
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
            }
        } else {
            HStack(alignment: .top, spacing: 9) {
                batchSymbol(size: 15, width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    if group.isMinimized {
                        Text(group.captures.map(\.title).joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    } else {
                        Text("Saved together in one drop or paste")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 5)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(captureClock(primary)).font(.system(size: 12.65)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                        if showsCopyButton {
                            CaptureCopyButton(state: state, captures: group.captures)
                        }
                    }
                    Text("Batch").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.fixedSize()
            }
        }
    }

    private func batchSymbol(size: CGFloat, width: CGFloat) -> some View {
        Image(systemName: "square.stack.3d.up.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: width, height: 22)
            .accessibilityHidden(true)
    }

    private func batchIcon(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 26)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buddyHelp(label).accessibilityLabel(label)
        .disabled(state.removingCaptureID != nil)
    }
}

@MainActor
private struct GroupedCaptureItem: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let compact: Bool

    var body: some View {
        if compact { compactContent }
        else { CaptureRow(state: state, capture: capture, featured: false, embeddedInCard: true).padding(8) }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { state.openCapture(capture.id) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if !compact {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                HStack(spacing: compact ? 7 : 10) {
                    if compact {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(width: 44, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capture.title.isEmpty ? "Untitled item" : capture.title)
                            .font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(compact ? 2 : 1)
                            .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        if !capture.isTask {
                            Text(captureTypeLabel(capture.kind))
                                .font(.system(size: compact ? 9 : 10)).foregroundStyle(Palette.muted)
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.muted).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "Task" : captureTypeLabel(capture.kind))")
            if capture.isTask {
                HStack {
                    TaskStatusButton(state: state, capture: capture)
                    Spacer(minLength: 0)
                    CaptureTrashButton(state: state, capture: capture)
                }
                TaskFocusControls(state: state, capture: capture)
            } else {
                HStack(spacing: 2) {
                    CaptureTaskConversionButton(state: state, capture: capture)
                    Spacer(minLength: 0)
                    CaptureCopyButton(state: state, captures: [capture], compact: true)
                    CaptureTrashButton(state: state, capture: capture)
                }
            }
        }
        .padding(.horizontal, compact ? 1 : 9).padding(.vertical, compact ? 6 : 7)
        .contextMenu {
            CaptureTaskConversionMenu(state: state, capture: capture)
        }
    }
}
