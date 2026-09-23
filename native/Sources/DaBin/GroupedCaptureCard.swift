import SwiftUI

@MainActor
struct GroupedCaptureCard: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    let group: CaptureCardGroup
    var compact = false
    @State private var confirmsRemoval = false

    private var primary: Capture { group.primary }
    private var title: String { "\(group.captures.count) items" }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: compact ? 13 : 15, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: compact ? 18 : 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: compact ? 13 : 15, weight: .semibold))
                    if group.isMinimized {
                        Text(group.captures.map(\.title).joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    } else {
                        Text("Saved together in one drop or paste")
                            .font(.system(size: compact ? 9 : 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 5)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(captureClock(primary)).font(.system(size: 12.65)).monospacedDigit()
                        .foregroundStyle(Palette.muted)
                    Text("Batch").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.fixedSize()
            }

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

            if !group.isMinimized && !primary.comment.isEmpty {
                Text(primary.comment).font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(Palette.muted).lineLimit(2)
            }

            HStack(spacing: compact ? 2 : 18) {
                if compact {
                    batchIcon(symbol: primary.comment.isEmpty ? "text.bubble" : "text.bubble.fill",
                              label: "Comment on this batch") {
                        state.openCapture(primary.id, focus: "comment")
                    }
                    batchIcon(symbol: primary.reminderAt == nil ? "bell" : "bell.fill",
                              label: "Reminder for this batch") {
                        state.openCapture(primary.id, focus: "reminder")
                    }
                } else {
                    Button { state.openCapture(primary.id, focus: "comment") } label: {
                        Label("Comment", systemImage: primary.comment.isEmpty ? "text.bubble" : "text.bubble.fill")
                    }.accessibilityLabel("Comment on this batch")
                    Button { state.openCapture(primary.id, focus: "reminder") } label: {
                        Label("Reminder", systemImage: primary.reminderAt == nil ? "bell" : "bell.fill")
                    }.accessibilityLabel("Reminder for this batch")
                }
                Spacer(minLength: 0)
                batchIcon(symbol: group.isMinimized ? "chevron.down" : "chevron.up",
                          label: group.isMinimized ? "Expand batch" : "Minimize batch") {
                    state.toggleMinimized(group.captures)
                }
                batchIcon(symbol: "trash", label: "Remove batch") { confirmsRemoval = true }
            }
            .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent)

            if !group.isMinimized, let reminder = primary.reminderAt {
                Text("Remind \(reminder.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: compact ? 9 : 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(compact ? 9 : 11)
        .background(Palette.soft.opacity(compact ? 0.58 : 0.46),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(accent.opacity(0.24), lineWidth: 0.75))
        .padding(.vertical, compact ? 0 : 6)
        .alert("Remove this batch?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove \(group.captures.count) items", role: .destructive) {
                Task { await state.removeCaptures(group.captures) }
            }
        } message: {
            Text("This removes all items in this caption card, their saved copies, comment and reminder. Files at their original locations are kept. This cannot be undone.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch of \(group.captures.count) captured items")
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
        Button { state.openCapture(capture.id) } label: {
            HStack(spacing: compact ? 7 : 10) {
                CaptureThumbnail(store: state.store, capture: capture)
                    .frame(width: compact ? 36 : 44, height: compact ? 38 : 46)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(capture.title.isEmpty ? "Untitled item" : capture.title)
                        .font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(compact ? 2 : 1)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Text(captureTypeLabel(capture.kind))
                        .font(.system(size: compact ? 9 : 10)).foregroundStyle(Palette.muted)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted).accessibilityHidden(true)
            }
            .padding(.horizontal, compact ? 7 : 9).padding(.vertical, compact ? 6 : 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(capture.title), \(captureTypeLabel(capture.kind))")
    }
}
