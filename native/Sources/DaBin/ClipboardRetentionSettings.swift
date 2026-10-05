import SwiftUI

@MainActor
struct ClipboardRetentionSettings: View {
    @ObservedObject var service: ClipboardRetentionService
    @ObservedObject var store: CaptureStore
    @Environment(\.daBinAccent) private var accent
    @State private var confirmedIDs: [UUID] = []
    @State private var showClearConfirmation = false

    var body: some View {
        let candidates = service.clearCandidates
        VStack(alignment: .leading, spacing: 9) {
            Label("Clipboard history", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .medium)).accessibilityAddTraits(.isHeader)
            Picker("Automatic cleanup", selection: Binding(get: { service.period }, set: { value in
                do {
                    try service.setPeriod(value)
                    Task { _ = await service.cleanup() }
                } catch { /* The service keeps the old preference and exposes the failure. */ }
            })) {
                ForEach(ClipboardRetentionPeriod.allCases) { period in Text(period.title).tag(period) }
            }.pickerStyle(.menu).controlSize(.small).font(.system(size: 12))
                .disabled(service.isRunning).accessibilityIdentifier("settings-clipboard-retention")
            Text("Automatic copies that have been inactive for this long move to Recently Deleted. Tasks, reminders, pinned items, snippets, projects, the shelf and items kept from Captions are protected.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Button {
                confirmedIDs = candidates.map(\.id)
                showClearConfirmation = !confirmedIDs.isEmpty
            } label: {
                Label("Clear unfiled copies… (\(candidates.count))", systemImage: "trash")
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                .disabled(service.isRunning || candidates.isEmpty)
                .accessibilityIdentifier("settings-clear-clipboard-history")
            Text("Nothing is permanently deleted. Restore a copy from Recently Deleted to restart its retention period.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if service.isRunning {
                HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Tidying unused copies…").font(.system(size: 11)) }
            } else if let error = service.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.task).fixedSize(horizontal: false, vertical: true)
            } else if let message = service.visibleResultMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel(message)
            }
        }
        .alert("Move \(confirmedIDs.count) copies to Recently Deleted?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { confirmedIDs = [] }
            Button("Move \(confirmedIDs.count) copies", role: .destructive) {
                let ids = confirmedIDs
                Task { _ = await service.clearUnfiledHistory(confirmedIDs: ids) }
            }
        } message: {
            Text("Only unfiled automatic clipboard copies are included. Tasks, project materials, snippets, pinned items, shelf materials and items kept from Captions stay saved. You can restore moved copies from Recently Deleted.")
        }
    }
}
