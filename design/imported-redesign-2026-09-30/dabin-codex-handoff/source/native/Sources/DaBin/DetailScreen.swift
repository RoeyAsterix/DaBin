import AppKit
import SwiftUI

@MainActor
struct DetailScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject var draft: CaptureDraft
    @FocusState private var focusedField: String?
    @State private var copiedSearchableText = false
    @State private var projectDraft = ""
    @State private var showingProjectEditor = false
    @State private var taskExpanded = true
    @State private var infoExpanded = false
    @State private var noteExpanded = false
    @State private var reminderExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(capture.title).font(.system(size: 21, weight: .semibold))
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Button { state.showCaptureDay(capture) } label: {
                                    Label("\(prettyDay(capture.captureDay)) · \(captureClock(capture))", systemImage: "calendar")
                                }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.muted).buddyHelp("Show original capture day")
                            }
                            Spacer(minLength: 0)
                            if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                        }
                        actionRail
                        DetailPreview(store: state.store, capture: capture)
                        if let text = capture.originalText, !text.isEmpty, capture.kind == .text || capture.kind == .task {
                            if text != capture.title {
                                Text(text).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            }
                        } else if !capture.previewDescription.isEmpty {
                            Text(capture.previewDescription).font(.system(size: 13)).foregroundStyle(Palette.muted).textSelection(.enabled)
                        }
                        CaptureSourceView(capture: capture)
                        if let parent = capture.parentTaskID {
                            Button { state.openCapture(parent, focus: "task") } label: { Label("Back to task", systemImage: "arrow.turn.up.left") }
                                .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12))
                        }
                        if capture.isTask {
                            DisclosureGroup(isExpanded: $taskExpanded) {
                                TaskPlanningEditor(planning: $draft.planning).padding(.top, 8)
                                if let previous = capture.taskPlanning?.previousOccurrenceID {
                                    Button("Previous occurrence", systemImage: "arrow.counterclockwise") { state.openCapture(previous) }
                                        .buttonStyle(.plain).font(.system(size: 12))
                                }
                                TaskAttachmentsView(state: state, task: capture).padding(.top, 8)
                            } label: {
                                Label(capture.isCompleted ? "Nicely done" : "Task workspace", systemImage: capture.isCompleted ? "checkmark.seal.fill" : "checklist")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(capture.isCompleted ? Palette.completed : accent)
                            }.id("task").accessibilityIdentifier("task-workspace")
                        }
                        if showingProjectEditor || capture.projectName != nil { organization.id("project") }
                        DisclosureGroup(isExpanded: $noteExpanded) { commentField.padding(.top, 8) } label: {
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
                        if let serviceStatus = state.reminders.status {
                            Text(serviceStatus).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if let reminder = capture.reminderAt, !(capture.isTask && capture.isCompleted), reminder > Date(), !["scheduled", "delivered"].contains(capture.notificationState) {
                            Button("Retry notification", systemImage: "bell.badge") { state.retryReminder(capture) }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                        }
                    }.padding(16).frame(maxWidth: 860).frame(maxWidth: .infinity)
                }.onAppear {
                    projectDraft = capture.projectName ?? ""
                    noteExpanded = !capture.comment.isEmpty || draft.hasChanges
                    reminderExpanded = draft.reminderEnabled
                    if let target = state.detailFocus {
                        noteExpanded = noteExpanded || target == "comment"
                        reminderExpanded = reminderExpanded || target == "reminder"
                        if target == "project" { showingProjectEditor = true }
                        proxy.scrollTo(target, anchor: .top)
                        focusedField = target
                    }
                }.onChange(of: state.detailFocus) { _, target in
                    guard let target else { return }
                    if target == "comment" { noteExpanded = true }
                    if target == "reminder" { reminderExpanded = true }
                    if target == "task" { taskExpanded = true }
                    if target == "project" { showingProjectEditor = true }
                    proxy.scrollTo(target, anchor: .top)
                    focusedField = target
                }.onChange(of: capture.isTask) { _, isTask in
                    if isTask { taskExpanded = true }
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let message = draft.message {
                        Text(message).foregroundStyle(draft.hasError ? Color.red : Palette.muted)
                    } else {
                        Text(draft.hasChanges ? "Draft kept locally · Save to apply" : "Captured day stays the same").foregroundStyle(Palette.muted)
                    }
                }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Save changes") { state.saveDetail() }.buttonStyle(.borderedProminent)
                    .controlSize(.regular).disabled(!draft.hasChanges).keyboardShortcut("s", modifiers: .command)
            }.padding(13).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }

    private var actionRail: some View {
        HStack(spacing: 4) {
            BuddyIconButton(symbol: "doc.on.doc", title: "Copy capture") { state.copyCapturesToClipboard([capture]) }
            BuddyIconButton(symbol: capture.isPinned ? "pin.fill" : "pin", title: capture.isPinned ? "Unpin" : "Pin", isActive: capture.isPinned) { state.togglePinned(capture) }
            BuddyIconButton(symbol: "folder.badge.plus", title: "Set project") { showingProjectEditor.toggle() }
            if !capture.isTask { CaptureTaskConversionButton(state: state, capture: capture) }
            if capture.kind != .text && capture.kind != .task {
                BuddyIconButton(symbol: "arrow.up.forward.square", title: "Open original") { state.openOriginal(capture) }
            }
            BuddyIconButton(symbol: "folder", title: "Show saved folder") { state.showArchiveFolder(for: capture) }
            Spacer(minLength: 0)
            BuddyIconButton(symbol: "trash", title: "Move to Recently Deleted") { state.requestRemoval(capture) }
        }.accessibilityElement(children: .contain).accessibilityLabel("Capture actions")
    }

    private var organization: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Button { state.togglePinned(capture) } label: {
                    Label(capture.isPinned ? "Pinned" : "Pin", systemImage: capture.isPinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).foregroundStyle(accent)
                Menu {
                    Button("No project", systemImage: "folder.badge.minus") { state.assignProject(capture, name: nil); projectDraft = "" }
                    ForEach(state.projectNames, id: \.self) { project in
                        Button(project, systemImage: "folder") { state.assignProject(capture, name: project); projectDraft = project }
                    }
                    Divider()
                    Button("Create project…", systemImage: "folder.badge.plus") { showingProjectEditor = true; projectDraft = ""; focusedField = "project" }
                } label: { Label(capture.projectName ?? "Add to project", systemImage: "folder").lineLimit(1) }
                    .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.font(.system(size: 12))
            if showingProjectEditor {
                HStack(spacing: 8) {
                    TextField("Project name", text: $projectDraft).textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: "project").accessibilityLabel("Project name")
                        .onSubmit { saveProject() }
                    Button("Add") { saveProject() }.disabled(projectDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { showingProjectEditor = false }.buttonStyle(.plain)
                }.font(.system(size: 12))
            }
        }
    }

    private func saveProject() {
        let name = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.assignProject(capture, name: name)
        showingProjectEditor = false
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
            if capture.kind != .text {
                Button("Open original") { state.openOriginal(capture) }.controlSize(.small).fixedSize()
            }
        }.padding(.vertical, 11)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 7) {
            EmptyView()
            TextEditor(text: $draft.comment).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(7).frame(minHeight: 76, maxHeight: 108).background(Palette.surface)
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
