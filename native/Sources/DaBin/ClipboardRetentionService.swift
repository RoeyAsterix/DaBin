import Foundation
import Combine

enum ClipboardRetentionPeriod: Int, Codable, CaseIterable, Identifiable {
    case never = 0, days7 = 7, days30 = 30, days90 = 90
    var id: Int { rawValue }
    var title: String { self == .never ? "Never" : "After \(rawValue) days" }
}

struct ClipboardCleanupResult {
    let movedCount: Int
    let remainingCount: Int
    let error: String?
    var message: String {
        if let error { return "\(movedCount) copies moved to Recently Deleted. \(error)" }
        if movedCount == 0 { return "No unfiled copies needed cleanup." }
        return "\(movedCount) \(movedCount == 1 ? "copy" : "copies") moved to Recently Deleted. You can restore them there."
    }
}

/// Opt-in cleanup moves inactive automatic copies to recoverable trash. It never
/// deletes an original, imports the current clipboard, or uses shared preferences.
@MainActor
final class ClipboardRetentionService: ObservableObject {
    static let filename = "ClipboardRetention.json"
    private struct Settings: Codable { let version: Int; let period: ClipboardRetentionPeriod }
    private let store: CaptureStore
    private let workspace: WorkspaceStore
    private var unreadable = false
    private var settingsReadError: String?
    @Published private(set) var period: ClipboardRetentionPeriod = .never
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?
    @Published private(set) var lastResult: ClipboardCleanupResult? {
        didSet { feedback.present(lastResult?.error == nil ? lastResult?.message : nil) }
    }
    let feedback = TransientMessagePresentation<String>()
    var visibleResultMessage: String? { feedback.visibleMessage }
    private var feedbackSubscription: AnyCancellable?
    var onWillTrash: ((Capture) async -> Void)?
    var settingsFailureInjector: (() throws -> Void)?

    init(store: CaptureStore, workspace: WorkspaceStore) {
        self.store = store
        self.workspace = workspace
        feedbackSubscription = feedback.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        do {
            let url = try DailyArchive(root: store.root).safeURL(Self.filename)
            if FileManager.default.fileExists(atPath: url.path) {
                try OriginalFileStorage.validateRegularFile(url)
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= 65_536 else { throw WorkspaceError.invalidArchive }
                let saved = try JSONDecoder().decode(Settings.self, from: bytes)
                guard saved.version == 1 else { throw WorkspaceError.invalidArchive }
                period = saved.period
            }
        } catch {
            settingsReadError = "Clipboard retention is off because its settings could not be read. The original settings file was preserved."
            self.error = settingsReadError
            unreadable = true
        }
    }

    func setPeriod(_ value: ClipboardRetentionPeriod) throws {
        guard !unreadable else { throw WorkspaceError.invalidArchive }
        do {
            let url = try DailyArchive(root: store.root).safeURL(Self.filename)
            if FileManager.default.fileExists(atPath: url.path) { try OriginalFileStorage.validateRegularFile(url) }
            let bytes = try JSONEncoder().encode(Settings(version: 1, period: value))
            try settingsFailureInjector?()
            try bytes.write(to: url, options: .atomic)
            period = value
            error = nil
        } catch { self.error = error.localizedDescription; throw error }
    }

    var clearCandidates: [Capture] {
        guard workspace.error == nil else { return [] }
        let protected = protectedIDs
        return store.captures.filter { isUnfiledCopy($0, protected: protected) }.sorted { $0.capturedAt < $1.capturedAt }
    }

    func retentionCandidates(at now: Date = Date(), calendar: Calendar = .current) -> [Capture] {
        guard period != .never, !unreadable,
              let cutoff = calendar.date(byAdding: .day, value: -period.rawValue, to: now) else { return [] }
        // Restoring or editing a capture restarts its retention interval.
        return clearCandidates.filter { max($0.capturedAt, $0.updatedAt) < cutoff }
    }

    func cleanup(at now: Date = Date()) async -> ClipboardCleanupResult {
        guard !isRunning else { return ClipboardCleanupResult(movedCount: 0, remainingCount: 0, error: nil) }
        guard !unreadable else { return ClipboardCleanupResult(movedCount: 0, remainingCount: 0, error: settingsReadError) }
        guard period != .never else { return ClipboardCleanupResult(movedCount: 0, remainingCount: 0, error: nil) }
        let candidates = retentionCandidates(at: now)
        return await move(Array(candidates.prefix(200)).map(\.id), remainingBeyondBatch: max(0, candidates.count - 200), retentionNow: now)
    }

    /// Caller presents the exact count for these IDs before starting. New copies
    /// arriving while the confirmation is open are never included implicitly.
    func clearUnfiledHistory(confirmedIDs: [UUID]) async -> ClipboardCleanupResult {
        guard !isRunning else { return ClipboardCleanupResult(movedCount: 0, remainingCount: confirmedIDs.count, error: "Cleanup is already running.") }
        return await move(Array(Set(confirmedIDs)), remainingBeyondBatch: 0)
    }

    private var protectedIDs: Set<UUID> {
        workspace.shelfCaptureIDs.union(workspace.snapshot.snippetNames.keys.compactMap(UUID.init(uuidString:)))
            .union(workspace.processedInboxIDs)
    }

    private func isUnfiledCopy(_ capture: Capture, protected: Set<UUID>) -> Bool {
        capture.captureOrigin == .automaticClipboard && capture.deletedAt == nil
        && !capture.isTask && capture.parentTaskID == nil && !capture.isPinned
        && capture.projectName == nil && capture.reminderAt == nil
        && !protected.contains(capture.id)
    }

    private func remainsInactive(_ capture: Capture, at now: Date?) -> Bool {
        guard let now else { return true }
        guard period != .never, let cutoff = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: now) else { return false }
        return max(capture.capturedAt, capture.updatedAt) < cutoff
    }

    private func move(_ ids: [UUID], remainingBeyondBatch: Int, retentionNow: Date? = nil) async -> ClipboardCleanupResult {
        isRunning = true
        defer { isRunning = false }
        var moved = 0
        var failure: String?
        var protected = protectedIDs
        for (index, id) in ids.enumerated() {
            if Task.isCancelled { failure = "Cleanup paused. Remaining copies were kept."; break }
            guard workspace.error == nil else { failure = "Workspace references could not be verified. Copies were kept."; break }
            guard let capture = store.captures.first(where: { $0.id == id }), isUnfiledCopy(capture, protected: protected) else { continue }
            do {
                await onWillTrash?(capture)
                if Task.isCancelled { failure = "Cleanup paused. Remaining copies were kept."; break }
                protected = protectedIDs
                guard store.captures.contains(where: { $0 === capture }), workspace.error == nil,
                      isUnfiledCopy(capture, protected: protected), remainsInactive(capture, at: retentionNow) else { continue }
                try store.moveToTrash(capture)
                moved += 1
            } catch { failure = "Remaining copies were kept: \(error.localizedDescription)"; break }
            if index.isMultiple(of: 20) { await Task.yield(); protected = protectedIDs }
        }
        let confirmed = Set(ids)
        protected = protectedIDs
        let remaining = store.captures.filter { confirmed.contains($0.id) && isUnfiledCopy($0, protected: protected)
            && remainsInactive($0, at: retentionNow) }.count + remainingBeyondBatch
        let result = ClipboardCleanupResult(movedCount: moved, remainingCount: remaining, error: failure)
        lastResult = result
        error = failure ?? settingsReadError
        return result
    }
}
