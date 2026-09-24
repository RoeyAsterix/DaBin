import AppKit
import SwiftUI

@MainActor
struct DetailScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject var draft: CaptureDraft
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(capture.title).font(.system(size: 20, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button { state.showCaptureDay(capture) } label: {
                                Text("\(prettyDay(capture.captureDay)) · \(captureClock(capture))")
                            }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent).help("Show original capture day")
                        }
                        if capture.isTask {
                            TaskStatusButton(state: state, capture: capture)
                        } else {
                            CaptureTaskConversionButton(state: state, capture: capture)
                        }
                        DetailPreview(store: state.store, capture: capture)
                        if let error = capture.previewError, !error.isEmpty {
                            Label(error, systemImage: "info.circle")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let text = capture.originalText, !text.isEmpty, capture.kind == .text || capture.kind == .task {
                            if capture.kind == .text || text != capture.title {
                                Text(text).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                            Button { state.copyCapturesToClipboard([capture]) } label: { Label("Copy text", systemImage: "doc.on.doc") }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                        } else if !capture.previewDescription.isEmpty {
                            Text(capture.previewDescription).font(.system(size: 13)).foregroundStyle(Palette.muted).textSelection(.enabled)
                        }
                        if capture.kind != .task {
                            original
                            CaptureSourceView(capture: capture)
                        }
                        Button { state.showArchiveFolder(for: capture) } label: {
                            Label("Show saved folder", systemImage: "folder")
                        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                        commentField.id("comment")
                        reminderField.id("reminder")
                        if let serviceStatus = state.reminders.status {
                            Text(serviceStatus).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if let reminder = capture.reminderAt, !(capture.isTask && capture.isCompleted) {
                            if reminder <= Date() {
                                Text("This reminder time has passed. Choose a future time and save to receive another reminder.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !["scheduled", "delivered"].contains(capture.notificationState) {
                                Button("Retry notification") {
                                    if reminder > Date() { state.retryReminder(capture) }
                                    else {
                                        draft.message = "Choose a future time and save to receive another reminder."
                                        draft.hasError = false
                                    }
                                }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                            }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 18)
                }.onAppear {
                    if let target = state.detailFocus {
                        proxy.scrollTo(target, anchor: .top)
                        focusedField = target
                    }
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let message = draft.message {
                        Text(message).foregroundStyle(draft.hasError ? Color.red : Palette.muted)
                    } else {
                        Text(draft.hasChanges ? "Draft kept until you save" : "Captured day stays the same").foregroundStyle(Palette.muted)
                    }
                }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Save changes") { state.saveDetail() }.buttonStyle(.borderedProminent)
                    .controlSize(.regular).disabled(!draft.hasChanges).keyboardShortcut("s", modifiers: .command)
            }.padding(13).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
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
            Text("Comment").font(.system(size: 13, weight: .medium))
            TextEditor(text: $draft.comment).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(7).frame(minHeight: 76, maxHeight: 108).background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
                .focused($focusedField, equals: "comment").accessibilityLabel("Comment")
                .onChange(of: draft.comment) { _, _ in draft.message = nil }
        }
    }

    private var reminderField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Reminder", isOn: $draft.reminderEnabled).toggleStyle(.switch).controlSize(.small)
                .font(.system(size: 13, weight: .medium)).focused($focusedField, equals: "reminder")
                .onChange(of: draft.reminderEnabled) { _, _ in draft.message = nil }
            if draft.reminderEnabled {
                DatePicker("Remind me", selection: $draft.reminderDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).accessibilityLabel("Reminder date and time")
                    .onChange(of: draft.reminderDate) { _, _ in draft.message = nil }
                Text("\(TimeZone.current.identifier) · \(draft.reminderDate.formatted(.dateTime.timeZone(.iso8601(.long))))")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if capture.isTask && capture.isCompleted {
                    Text("Reminder is paused while this task is completed.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Button("Clear reminder") { draft.reminderEnabled = false; draft.message = "Reminder will be cleared when you save." }
                    .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent)
            }
        }
    }
}
