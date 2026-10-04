import AppKit
import SwiftUI

/// Size from the visible viewport, never from the unbounded scroll content.
/// Resizing changes metrics without replacing editors, playback, or PDF state.
struct DetailLayout {
    let viewport: CGSize
    var horizontalInset: CGFloat { min(24, max(16, 16 + (viewport.width - 380) * 0.025)) }
    var contentWidth: CGFloat { max(0, viewport.width - horizontalInset * 2) }
    // Reserve the title/action area in short windows; enlarging the viewport
    // then gives that space back to the fitted media instead of a fixed box.
    var previewHeight: CGFloat { max(100, min(viewport.height - 170, contentWidth * 0.85)) }
    var commentHeight: CGFloat { min(260, max(108, viewport.height * 0.25)) }
    var titleSize: CGFloat { min(28, max(21, 21 + (viewport.width - 380) / 110)) }
    var bodySize: CGFloat { min(17, max(15, 15 + (viewport.width - 380) / 360)) }
    var usesTaskColumns: Bool { contentWidth >= 860 }
    var sectionSpacing: CGFloat { usesTaskColumns ? 20 : 14 }
    private var taskColumnWidth: CGFloat { usesTaskColumns ? (contentWidth - sectionSpacing) / 2 : contentWidth }
    var attachmentMinimumWidth: CGFloat { min(220, max(125, taskColumnWidth * 0.3)) }
    var attachmentHeight: CGFloat { min(200, max(100, taskColumnWidth * 0.28)) }
}

@MainActor
struct DetailScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject var draft: CaptureDraft
    @FocusState private var focusedField: String?
    @State private var copiedSearchableText = false
    @State private var taskExpanded = true
    @State private var infoExpanded = false
    @State private var noteExpanded = false
    @State private var reminderExpanded = false
    @State private var originalExpanded = false
    @State private var sourceExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let layout = DetailLayout(viewport: geometry.size)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                            CaptureProjectPickerButton(state: state, capture: capture)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(alignment: .top, spacing: 8) {
                                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                                VStack(alignment: .leading, spacing: 8) {
                                    if capture.isTask {
                                        Text(capture.isCompleted ? "COMPLETED" : "TASK")
                                            .font(.system(size: 10, weight: .medium)).tracking(0.8).foregroundStyle(Palette.muted)
                                            .accessibilityIdentifier("detail-task-caption")
                                            .captureDragSource(state: state, capture: capture)
                                    }
                                    if capture.isTask {
                                        TextField("Task title", text: $draft.title, axis: .vertical)
                                            .textFieldStyle(.plain).font(.system(size: layout.titleSize, weight: .semibold, design: .rounded))
                                            .lineLimit(1...6).fixedSize(horizontal: false, vertical: true)
                                            .accessibilityLabel("Task title").accessibilityIdentifier("detail-title")
                                            .focused($focusedField, equals: "title")
                                            .onChange(of: draft.title) { _, _ in draft.message = nil }
                                        if draft.planning.priority != .none {
                                            TaskPriorityTag(priority: draft.planning.priority)
                                        }
                                    } else {
                                        Text(capture.title).font(.system(size: layout.titleSize, weight: .semibold, design: .rounded))
                                            .accessibilityIdentifier("detail-title")
                                            .fixedSize(horizontal: false, vertical: true)
                                            .captureDragSource(state: state, capture: capture)
                                    }
                                    Button { state.showCaptureDay(capture) } label: {
                                        Label(captureReceiptText(capture, includeWeekday: true), systemImage: "calendar")
                                            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                                    }.font(.system(size: 16, weight: .medium)).buttonStyle(.plain)
                                        .foregroundStyle(Palette.foreground)
                                        .accessibilityLabel("Captured \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
                                        .accessibilityIdentifier("detail-captured-at")
                                        .buddyHelp("Show original capture day")
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            CaptureTrailView(state: state, capture: capture, compact: false)
                            actionRail
                            CaptureConversionUndo(state: state, capture: capture)
                            if capture.isTask {
                                TaskFocusControls(state: state, capture: capture, compact: false)
                                DisclosureGroup(isExpanded: $taskExpanded) {
                                    taskWorkspace(layout: layout).padding(.top, 12)
                                } label: {
                                    Label(capture.isCompleted ? "Nicely done" : "Task workspace", systemImage: capture.isCompleted ? "checkmark.seal.fill" : "checklist")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.foreground)
                                }.id("task").accessibilityIdentifier("task-workspace")
                                DisclosureGroup(isExpanded: $originalExpanded) {
                                    originalContent(layout: layout).padding(.top, 12)
                                } label: {
                                    Label("Original capture · \(captureTypeLabel(capture.kind))", systemImage: "doc.text")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            } else {
                                originalContent(layout: layout)
                            }
                            DisclosureGroup(isExpanded: $sourceExpanded) {
                                CaptureSourceView(capture: capture).padding(.top, 8)
                            } label: {
                                Label("Source details", systemImage: "arrow.triangle.branch")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            if let parent = capture.parentTaskID {
                                Button { state.openCapture(parent, focus: "task") } label: { Label("Back to task", systemImage: "arrow.turn.up.left") }
                                    .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12))
                            }
                            DisclosureGroup(isExpanded: $noteExpanded) { commentField(height: layout.commentHeight).padding(.top, 8) } label: {
                                Label(capture.comment.isEmpty ? "Comment" : "Comment · saved", systemImage: "text.bubble")
                                    .font(.system(size: 12, weight: .medium))
                            }.id("comment")
                            DisclosureGroup(isExpanded: $reminderExpanded) { reminderField.padding(.top, 8) } label: {
                                Label(capture.reminderAt?.formatted(date: .abbreviated, time: .shortened) ?? "Reminder", systemImage: "clock")
                                    .font(.system(size: 12, weight: .medium))
                            }.id("reminder")
                            DisclosureGroup(isExpanded: $infoExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let error = capture.previewError, !error.isEmpty {
                                        Label(error, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    }
                                    if ContentIndexService.isEligible(capture.kind) { searchableText }
                                    if capture.kind != .task { original }
                                }.padding(.top, 8)
                            } label: {
                                Label("File & recognized text", systemImage: "doc.text.magnifyingglass").font(.system(size: 12))
                            }
                            if let serviceStatus = state.reminders.visibleStatus {
                                Text(serviceStatus).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("detail-reminder-feedback")
                            }
                            if let reminder = capture.reminderAt, !(capture.isTask && capture.isCompleted), reminder > Date(), !["scheduled", "delivered"].contains(capture.notificationState) {
                                Button("Retry notification", systemImage: "bell.badge") { state.retryReminder(capture) }
                                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                            }
                        }.padding(.horizontal, layout.horizontalInset).padding(.vertical, 16)
                            .frame(width: max(0, geometry.size.width), alignment: .leading)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("detail-content")
                    }.onAppear {
                        noteExpanded = !capture.comment.isEmpty || draft.hasChanges
                        reminderExpanded = draft.reminderEnabled
                        if let target = state.detailFocus {
                            noteExpanded = noteExpanded || target == "comment"
                            reminderExpanded = reminderExpanded || target == "reminder"
                            proxy.scrollTo(target, anchor: .top)
                            focusedField = target
                        }
                    }.onChange(of: state.detailFocus) { _, target in
                        guard let target else { return }
                        if target == "comment" { noteExpanded = true }
                        if target == "reminder" { reminderExpanded = true }
                        if target == "task" { taskExpanded = true }
                        proxy.scrollTo(target, anchor: .top)
                        focusedField = target
                    }.onChange(of: capture.isTask) { _, isTask in
                        if isTask { taskExpanded = true }
                    }
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let message = draft.visibleMessage {
                        Text(message).foregroundStyle(draft.hasError ? Color.red : Palette.muted)
                            .accessibilityIdentifier("detail-save-feedback")
                    } else {
                        Text(draft.hasChanges ? "Draft kept locally · Save to apply" : "Captured day stays the same").foregroundStyle(Palette.muted)
                    }
                }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Save changes") { state.saveDetail() }.buttonStyle(.borderedProminent)
                    .controlSize(.regular).disabled(!draft.hasChanges).keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("detail-save")
            }.padding(13).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }

    private func originalContent(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailPreview(store: state.store, capture: capture, height: layout.previewHeight,
                          onOpenOriginal: { state.openOriginal(capture) })
                .captureDragSource(state: state, capture: capture)
            if let text = capture.originalText, !text.isEmpty, capture.kind == .text || capture.kind == .task {
                if capture.isTask || text != capture.title {
                    Text(text).font(.system(size: layout.bodySize)).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            } else if !capture.previewDescription.isEmpty {
                Text(capture.previewDescription).font(.system(size: 14)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
        }
    }

    private func taskWorkspace(layout: DetailLayout) -> some View {
        let arrangement = layout.usesTaskColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.sectionSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return arrangement {
            VStack(alignment: .leading, spacing: 8) {
                TaskPlanningEditor(planning: $draft.planning, showsSchedule: false)
                if let previous = capture.taskPlanning?.previousOccurrenceID {
                    Button("Previous occurrence", systemImage: "arrow.counterclockwise") { state.openCapture(previous) }
                        .buttonStyle(.plain).font(.system(size: 12))
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            TaskAttachmentsView(state: state, task: capture,
                minimumCardWidth: layout.attachmentMinimumWidth, thumbnailHeight: layout.attachmentHeight)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var actionRail: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            BuddyIconButton(symbol: "doc.on.doc", title: "Copy capture") { state.copyCapturesToClipboard([capture]) }
            if !capture.isTask { CaptureTaskConversionButton(state: state, capture: capture) }
            BuddyIconButton(symbol: capture.isPinned ? "pin.fill" : "pin", title: capture.isPinned ? "Unpin" : "Pin", isActive: capture.isPinned) { state.togglePinned(capture) }
            if capture.kind != .text && capture.kind != .task {
                BuddyIconButton(symbol: "arrow.up.forward.square", title: "Open original") { state.openOriginal(capture) }
            }
            BuddyIconButton(symbol: "folder", title: "Show saved folder") { state.showArchiveFolder(for: capture) }
            CaptureTrashButton(state: state, capture: capture)
        }.accessibilityElement(children: .contain).accessibilityLabel("Capture actions")
    }

    @ViewBuilder
    private var searchableText: some View {
        switch capture.contentIndexState {
        case "indexing":
            Label("Making this capture searchable…", systemImage: "text.viewfinder")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .accessibilityLabel("Recognizing text on this Mac")
        case "ready" where !capture.indexedText.isEmpty:
            VStack(alignment: .leading, spacing: 6) {
                Label("Searchable text", systemImage: "text.viewfinder")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                if capture.indexedText.count > 2_000 {
                    Text("Preview · first 2,000 of \(capture.indexedText.count.formatted()) characters")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                }
                Text(indexedTextPreview)
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .lineLimit(8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button { copySearchableText() } label: {
                    Label(copiedSearchableText ? "Searchable text copied" : "Copy all searchable text",
                          systemImage: copiedSearchableText ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                .buddyHelp("Copy all recognized text to the clipboard")
                if let message = capture.contentIndexError {
                    Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            .padding(10).background(Palette.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityElement(children: .contain)
        case "ready":
            Label("No readable text found", systemImage: "text.viewfinder")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        case "unavailable":
            VStack(alignment: .leading, spacing: 5) {
                Label(capture.contentIndexError ?? "Text search is unavailable for this capture.",
                      systemImage: "text.viewfinder")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if state.contentIndex != nil, capture.contentIndexCanRetry {
                    Button("Try text recognition again") { state.retryContentIndex(capture) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                        .buddyHelp("Retry local text recognition")
                }
            }
        default:
            if state.contentIndex?.isBusy == true {
                Label("Waiting for local text recognition…", systemImage: "text.viewfinder")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var indexedTextPreview: String {
        capture.indexedText.count > 2_000
            ? String(capture.indexedText.prefix(2_000)) + "…"
            : capture.indexedText
    }

    private func copySearchableText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(capture.indexedText, forType: .string) else {
            state.reportFailure("Searchable text could not be copied.")
            return
        }
        copiedSearchableText = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            copiedSearchableText = false
        }
    }

    private var original: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capture.originalURL ?? capture.originalFilename ?? "Text capture")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(3).textSelection(.enabled)
                if let bytes = capture.byteCount { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 11)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            .captureDragSource(state: state, capture: capture)
            .buddyHelp("Drag the saved content into another app")
    }

    private func commentField(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            EmptyView()
            TextEditor(text: $draft.comment).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(7).frame(height: height).background(Palette.surface)
                .accessibilityIdentifier("detail-comment-editor")
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
                .focused($focusedField, equals: "comment").accessibilityLabel("Capture note")
                .onChange(of: draft.comment) { _, _ in draft.message = nil }
        }
    }

    private var reminderField: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReminderClockEditor(enabled: $draft.reminderEnabled, mode: $draft.reminderMode,
                date: $draft.reminderDate, hours: $draft.countdownHours, minutes: $draft.countdownMinutes)
                        .onChange(of: draft.reminderEnabled) { _, _ in draft.message = nil }
                        .onChange(of: draft.reminderMode) { _, _ in draft.message = nil }
                        .onChange(of: draft.reminderDate) { _, _ in draft.message = nil }
                        .onChange(of: draft.countdownHours) { _, _ in draft.message = nil }
                        .onChange(of: draft.countdownMinutes) { _, _ in draft.message = nil }
            if capture.isTask && capture.isCompleted && draft.reminderEnabled {
                Label("Reminder is paused while completed", systemImage: "bell.slash")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if let due = capture.reminderAt, due <= Date(), !capture.isCompleted {
                Text("This reminder has passed. Choose a new time to be reminded again.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }
}
