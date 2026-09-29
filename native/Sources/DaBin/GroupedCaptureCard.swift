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
                Button(group.isMinimized ? "Show items" : "Collapse") { state.toggleMinimized(group.captures) }
                Spacer(minLength: 0)
                Menu {
                    Button(primary.comment.isEmpty ? "Add note" : "Edit note") { state.openCapture(primary.id, focus: "comment") }
                    Button(primary.reminderAt == nil ? "Add reminder" : "Edit reminder") { state.openCapture(primary.id, focus: "reminder") }
                    Divider()
                    Button("Move batch to Recently Deleted", role: .destructive) { confirmsRemoval = true }
                } label: { Text("More") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More batch actions")
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)

            if let reminder = primary.reminderAt {
                Text("Remind \(reminder.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(compact ? 9 : 11)
        .background(Palette.soft.opacity(compact ? 0.58 : 0.46),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(accent.opacity(0.24), lineWidth: 0.75))
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
                    Text(title).font(.system(size: 15, weight: .semibold))
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
        .help(label).accessibilityLabel(label)
        .disabled(state.removingCaptureID != nil)
    }
}

@MainActor
private struct GroupedCaptureItem: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { state.openCapture(capture.id) } label: {
                HStack(spacing: compact ? 7 : 10) {
                    CaptureThumbnail(store: state.store, capture: capture)
                        .frame(width: compact ? 36 : 44, height: compact ? 38 : 46)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "Task" : captureTypeLabel(capture.kind))")
            if capture.isTask {
                TaskStatusButton(state: state, capture: capture)
                    .padding(.leading, compact ? 43 : 54)
            }
        }
        .padding(.horizontal, compact ? 7 : 9).padding(.vertical, compact ? 6 : 7)
        .contextMenu {
            CaptureTaskConversionMenu(state: state, capture: capture)
        }
    }
}
