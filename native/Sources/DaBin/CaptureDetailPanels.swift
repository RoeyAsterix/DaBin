import SwiftUI

/// Both detail presentations edit the same recoverable draft and saved thread.
enum CaptureDetailSection: String, CaseIterable { case comments, reminder }

@MainActor
struct CaptureDetailPanels: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject var draft: CaptureDraft
    @Binding var selection: CaptureDetailSection
    var showsTabs = true
    var isActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTabs {
                HStack(spacing: 6) {
                    tab(.comments, title: "Comments · \(capture.commentCount)", subtitle: nil, icon: "text.bubble")
                    tab(.reminder, title: "Reminder", subtitle: reminderLabel, icon: "alarm")
                }.accessibilityElement(children: .contain).accessibilityLabel("Capture sections")
            }
            if selection == .comments { comments } else { reminder }
        }
        .onChange(of: state.detailFocus) { _, focus in
            guard showsTabs else { return }
            if focus == "comment" { selection = .comments }
            if focus == "reminder" { selection = .reminder }
        }
    }

    private var reminderLabel: String {
        guard let date = capture.reminderAt else { return "Not scheduled" }
        if capture.isReminderAcknowledged { return "Acknowledged" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func tab(_ section: CaptureDetailSection, title: String, subtitle: String?, icon: String) -> some View {
        Button { selection = section } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 10)).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .background(selection == section ? accent.opacity(0.14) : Palette.soft,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(
                selection == section ? accent.opacity(0.7) : Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain).foregroundStyle(selection == section ? accent : Palette.foreground)
        .accessibilityLabel(title + (subtitle.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityIdentifier("capture-tab-\(section.rawValue)")
        .buddyHelp(section == .comments ? "Read and add comments" : "Schedule, snooze or remove this reminder")
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.comment != capture.comment {
                Text("Recovered comment edit").font(.system(size: 12, weight: .semibold))
                TextEditor(text: $draft.comment).frame(minHeight: 80)
                    .background(NavigationEditorRegion(target: .recoveredComment, isActive: isActive))
                    .accessibilityLabel("Recovered capture comment")
                Text("Save changes to apply this earlier edit.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Text(draft.editingCommentID == nil ? "Add a comment" : "Edit comment")
                .font(.system(size: 12, weight: .semibold))
            TextEditor(text: $draft.commentComposer)
                .background(NavigationEditorRegion(target: .commentComposer, isActive: isActive))
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(7).frame(minHeight: 100, maxHeight: 150)
                .background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityLabel(draft.editingCommentID == nil ? "New comment" : "Edit comment text")
                .accessibilityIdentifier("capture-comment-composer")
            HStack {
                if draft.editingCommentID != nil {
                    Button("Cancel edit") { draft.commentComposer = ""; draft.editingCommentID = nil }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button(draft.editingCommentID == nil ? "Post comment" : "Save comment", systemImage: "arrow.up.circle.fill") {
                    state.postDetailComment(capture, draft: draft)
                }.buttonStyle(.borderedProminent).controlSize(.regular)
                    .disabled(draft.commentComposer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("capture-post-comment")
            }
            if !capture.commentThread.isEmpty {
                Divider()
                Text("Comments · \(capture.commentCount)").font(.system(size: 12, weight: .semibold))
            }
            if capture.commentThread.isEmpty {
                Label("Keep a thought or the next step here.", systemImage: "text.bubble")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            ForEach(capture.commentThread) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Saved comment")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Spacer()
                        Button {
                            draft.editingCommentID = entry.id
                            draft.commentComposer = entry.text
                        } label: { Image(systemName: "pencil").frame(width: 28, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(accent)
                        .disabled(!draft.commentComposer.isEmpty && draft.editingCommentID != entry.id)
                        .accessibilityLabel("Edit comment")
                        .accessibilityIdentifier("edit-comment-\(entry.id.uuidString)")
                        .buddyHelp("Edit this comment")
                    }
                    Text(entry.text).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(10).background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("capture-comment-thread")
    }

    private var reminder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReminderClockEditor(enabled: $draft.reminderEnabled, mode: $draft.reminderMode,
                date: $draft.reminderDate, hours: $draft.countdownHours, minutes: $draft.countdownMinutes)
            if capture.reminderAt != nil {
                Text("Saved · \(reminderLabel)")
                    .font(.system(size: reminderControlFont)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture-reminder-saved-summary")
            }
            if draft.reminderEnabled || draft.reminderChanged || capture.reminderAt != nil {
            BuddyActionFlow {
                Button {
                    do {
                        let date = draft.reminderChanged ? try draft.resolvedReminder() : draft.reminder
                        if state.setDetailReminder(capture, date: date) {
                            draft.adoptSavedReminder(from: capture)
                            draft.message = date == nil ? "Reminder removed." : "Reminder saved."
                        }
                    } catch { draft.message = error.localizedDescription; draft.hasError = true }
                } label: {
                    Label("Apply reminder", systemImage: "checkmark")
                        .font(.system(size: reminderControlFont, weight: .medium))
                        .padding(.horizontal, 10).frame(minHeight: 32).contentShape(Rectangle())
                        .foregroundStyle(Palette.background)
                }.buttonStyle(.borderedProminent).controlSize(.small).tint(accent)
                    .disabled(!draft.reminderChanged).accessibilityIdentifier("capture-save-reminder")
                    .accessibilityLabel("Apply reminder")
                    .accessibilityHint("Save only the reminder; other draft changes stay pending")
                if capture.reminderAt != nil {
                    Menu {
                        Button("In 10 minutes") { snooze(minutes: 10) }
                        Button("In 1 hour") { snooze(minutes: 60) }
                        Button("Tomorrow morning") { state.snoozeFollowUp(capture) }
                    } label: {
                        Label("Snooze", systemImage: "zzz")
                            .font(.system(size: reminderControlFont))
                            .padding(.horizontal, 8).frame(minHeight: 32).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).fixedSize()
                        .accessibilityIdentifier("capture-snooze-reminder")
                    Button { state.setDetailReminder(capture, date: nil) } label: {
                        Label("Remove", systemImage: "bell.slash")
                            .font(.system(size: reminderControlFont))
                            .padding(.horizontal, 8).frame(minHeight: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Remove reminder")
                        .accessibilityIdentifier("capture-remove-reminder")
                }
            }.foregroundStyle(accent)
            }
            if capture.isTask && capture.isCompleted {
                Label("Reminders pause while this task is completed.", systemImage: "bell.slash")
                    .font(.system(size: reminderControlFont)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = state.reminders.visibleStatus {
                Text(message).font(.system(size: reminderControlFont)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if (!capture.isTask || !capture.isCompleted), let date = capture.reminderAt, date > Date(),
               !["scheduled", "delivered"].contains(capture.notificationState) {
                Button { state.retryReminder(capture) } label: {
                    Label("Retry notification", systemImage: "bell.badge")
                        .font(.system(size: reminderControlFont))
                        .padding(.horizontal, 8).frame(minHeight: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(accent)
                    .accessibilityIdentifier("capture-retry-reminder")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("capture-reminder-panel")
    }

    private var reminderControlFont: CGFloat { min(15, max(12, zoom.fontSize(13))) }
    private func snooze(minutes: Int) { state.setDetailReminder(capture, date: Date().addingTimeInterval(Double(minutes) * 60)) }
}
