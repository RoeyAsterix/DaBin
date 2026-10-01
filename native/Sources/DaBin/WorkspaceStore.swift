import Foundation
import Combine

enum WorkspaceMode: String, CaseIterable, Codable, Identifiable {
    case collection, clipboard, shelf, scratchpad
    var id: String { rawValue }
    var title: String {
        switch self {
        case .collection: return "Explorer"
        case .clipboard: return "Clipboard"
        case .shelf: return "Shelf"
        case .scratchpad: return "Notes"
        }
    }
    var symbol: String {
        switch self {
        case .collection: return "folder"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.full"
        case .scratchpad: return "note.text"
        }
    }
}

enum WorkspaceDateFilter: String, CaseIterable, Codable, Identifiable {
    case anytime, today, lastSevenDays, lastThirtyDays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anytime: return "Any date"
        case .today: return "Today"
        case .lastSevenDays: return "Last 7 days"
        case .lastThirtyDays: return "Last 30 days"
        }
    }
    func includes(_ day: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self != .anytime else { return true }
        let upper = CaptureCalendar.dayString(now, timeZone: calendar.timeZone)
        let distance = self == .today ? 0 : self == .lastSevenDays ? 6 : 29
        let start = calendar.date(byAdding: .day, value: -distance, to: now) ?? now
        return day >= CaptureCalendar.dayString(start, timeZone: calendar.timeZone) && day <= upper
    }
}

enum WorkspaceOriginFilter: String, CaseIterable, Codable, Identifiable {
    case all, clipboard, manual, screenshots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Every source"
        case .clipboard: return "Automatic copies"
        case .manual: return "Manual captures"
        case .screenshots: return "Screenshots"
        }
    }
    func includes(_ origin: CaptureOrigin) -> Bool {
        switch self {
        case .all: return true
        case .clipboard: return origin == .automaticClipboard
        case .manual: return origin == .manual
        case .screenshots: return origin == .automaticScreenshot
        }
    }
}

struct WorkspaceScratchpad: Codable, Equatable {
    var text: String
    var projectName: String?
    var updatedAt: Date
}

/// Supplemental organization references existing immutable captures. Shelf and
/// snippet removal never removes a capture, its managed copy, or an external file.
struct WorkspaceSnapshot: Codable, Equatable {
    var schemaVersion = 1
    var scratchpads: [String: WorkspaceScratchpad] = [:]
    /// Optional so workspaces written before project colors remain readable.
    /// Keys are the exact persisted project names; values are six RGB hex digits.
    var projectColors: [String: String]?
    var shelfCaptureIDs: [UUID] = []
    var snippetNames: [String: String] = [:]
    var processedInboxIDs: [UUID] = []
    var mode: WorkspaceMode = .collection
    var selectedProject: String?
    var selectedCaptureID: UUID?
    /// Optional so the first workspace schema remains readable after upgrade.
    var projectSelections: [String: UUID]?
    var sourceApplication: String?
    var dateFilter: WorkspaceDateFilter = .anytime
    var originFilter: WorkspaceOriginFilter = .all
    var snippetsOnly = false
    // Optional fields keep older workspace archives readable.
    var explorerUnfiledOnly: Bool?
    var explorerGrouping: ExplorerGrouping?
    var explorerQuery: String?
    var explorerShowsDailyFiles: Bool?

    static func projectKey(_ name: String?) -> String { name.map { "project:" + $0 } ?? "inbox:" }

    func validated() throws -> WorkspaceSnapshot {
        guard schemaVersion == 1, scratchpads.count <= 5_000,
              (selectedProject?.count ?? 0) <= 180, (sourceApplication?.count ?? 0) <= 250,
              (explorerQuery?.count ?? 0) <= 2_000,
              (projectSelections?.count ?? 0) <= 5_001,
              projectSelections?.keys.allSatisfy({ $0 == "inbox:" || ($0.hasPrefix("project:") && $0.count <= 188) }) != false,
              (projectColors?.count ?? 0) <= 5_000,
              projectColors?.allSatisfy({ name, hex in
                  WorkspaceStore.isValidProjectName(name)
                    && WorkspaceStore.isValidProjectColorHex(hex)
                    && scratchpads[Self.projectKey(name)]?.projectName == name
              }) != false,
              shelfCaptureIDs.count <= 100_000, snippetNames.count <= 100_000,
              Set(snippetNames.keys.compactMap(UUID.init(uuidString:))).count == snippetNames.count,
              processedInboxIDs.count <= 500_000,
              Set(shelfCaptureIDs).count == shelfCaptureIDs.count,
              Set(processedInboxIDs).count == processedInboxIDs.count,
              scratchpads.allSatisfy({ key, value in
                  key == Self.projectKey(value.projectName) && value.text.utf8.count <= 1_000_000
                    && (value.projectName?.count ?? 0) <= 180
                    && value.updatedAt.timeIntervalSinceReferenceDate.isFinite
              }), snippetNames.allSatisfy({ UUID(uuidString: $0.key) != nil && !$0.value.isEmpty && $0.value.count <= 120 }) else {
            throw WorkspaceError.invalidArchive
        }
        return self
    }

    /// Restore is additive and refuses ambiguous replacements of authored text.
    static func merging(_ incoming: WorkspaceSnapshot, into current: WorkspaceSnapshot) throws -> WorkspaceSnapshot {
        _ = try incoming.validated(); _ = try current.validated()
        var result = current
        for (key, note) in incoming.scratchpads {
            if let existing = result.scratchpads[key], !existing.text.isEmpty,
               !note.text.isEmpty, existing.text != note.text {
                throw WorkspaceError.restoreConflict(note.projectName ?? "Inbox scratchpad")
            }
            if result.scratchpads[key]?.text.isEmpty != false { result.scratchpads[key] = note }
        }
        for (id, name) in incoming.snippetNames {
            if let existing = result.snippetNames[id], existing != name { throw WorkspaceError.restoreConflict("Snippet: " + existing) }
            result.snippetNames[id] = name
        }
        var shelf = Set(result.shelfCaptureIDs)
        result.shelfCaptureIDs += incoming.shelfCaptureIDs.filter { shelf.insert($0).inserted }
        var processed = Set(result.processedInboxIDs)
        result.processedInboxIDs += incoming.processedInboxIDs.filter { processed.insert($0).inserted }
        if let selections = incoming.projectSelections {
            var currentSelections = result.projectSelections ?? [:]
            for (key, value) in selections where currentSelections[key] == nil { currentSelections[key] = value }
            result.projectSelections = currentSelections
        }
        if let incomingColors = incoming.projectColors {
            var currentColors = result.projectColors ?? [:]
            for (name, color) in incomingColors where currentColors[name] == nil {
                currentColors[name] = color
            }
            result.projectColors = currentColors
        }
        return try result.validated()
    }
}

enum WorkspaceError: LocalizedError {
    case invalidArchive, unavailable(String), restoreConflict(String), missingContent, emptyCollection
    case invalidProjectName, invalidProjectColor
    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The saved workspace could not be read safely. Your existing file has been preserved."
        case .unavailable(let message): return "The workspace could not be saved. " + message
        case .restoreConflict(let name): return "The backup contains different workspace text for \(name). Your current notes were kept."
        case .missingContent: return "This item has no available text to copy."
        case .emptyCollection: return "Add items to the shelf before exporting."
        case .invalidProjectName: return "Enter a project name between 1 and 180 characters without line breaks."
        case .invalidProjectColor: return "Choose a valid six-digit RGB project color."
        }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    static let filename = "Workspace.json"
    nonisolated static let defaultProjectColorHex = "7568D8"
    let root: URL
    @Published private(set) var snapshot = WorkspaceSnapshot()
    @Published private(set) var error: String?
    @Published private(set) var pendingScratchpads: [String: String] = [:]
    private var unreadable = false
    var failureInjector: (() throws -> Void)?

    init(root: URL) {
        self.root = root
        do { snapshot = try Self.readSnapshot(at: root) ?? WorkspaceSnapshot() }
        catch { self.error = error.localizedDescription; unreadable = true }
    }

    var mode: WorkspaceMode {
        get { snapshot.mode }
        set { updatePreference { $0.mode = newValue } }
    }
    var selectedProject: String? {
        get { snapshot.selectedProject }
        set { updatePreference {
            if $0.projectSelections == nil, let current = $0.selectedCaptureID {
                $0.projectSelections = [WorkspaceSnapshot.projectKey($0.selectedProject): current]
            }
            $0.selectedProject = newValue
        } }
    }
    var selectedCaptureID: UUID? {
        get {
            if let selections = snapshot.projectSelections { return selections[WorkspaceSnapshot.projectKey(snapshot.selectedProject)] }
            return snapshot.selectedCaptureID
        }
        set { updatePreference {
            var selections = $0.projectSelections ?? [:]
            selections[WorkspaceSnapshot.projectKey($0.selectedProject)] = newValue
            $0.projectSelections = selections
            $0.selectedCaptureID = newValue
        } }
    }
    var sourceApplication: String? {
        get { snapshot.sourceApplication }
        set { updatePreference { $0.sourceApplication = newValue } }
    }
    var dateFilter: WorkspaceDateFilter {
        get { snapshot.dateFilter }
        set { updatePreference { $0.dateFilter = newValue } }
    }
    var originFilter: WorkspaceOriginFilter {
        get { snapshot.originFilter }
        set { updatePreference { $0.originFilter = newValue } }
    }
    var snippetsOnly: Bool {
        get { snapshot.snippetsOnly }
        set { updatePreference { $0.snippetsOnly = newValue } }
    }
    var explorerUnfiledOnly: Bool {
        get { snapshot.explorerUnfiledOnly ?? false }
        set { updatePreference { $0.explorerUnfiledOnly = newValue } }
    }
    var explorerGrouping: ExplorerGrouping {
        get { snapshot.explorerGrouping ?? .type }
        set { updatePreference { $0.explorerGrouping = newValue } }
    }
    var explorerQuery: String {
        get { snapshot.explorerQuery ?? "" }
        set { updatePreference { $0.explorerQuery = String(newValue.prefix(2_000)) } }
    }
    var explorerShowsDailyFiles: Bool {
        get { snapshot.explorerShowsDailyFiles ?? false }
        set { updatePreference { $0.explorerShowsDailyFiles = newValue } }
    }
    var shelfCaptureIDs: Set<UUID> { Set(snapshot.shelfCaptureIDs) }
    var processedInboxIDs: Set<UUID> { Set(snapshot.processedInboxIDs) }
    var projectNames: [String] { snapshot.scratchpads.values.compactMap(\.projectName).sorted() }
    var scratchpads: [WorkspaceScratchpad] { snapshot.scratchpads.values.filter { !$0.text.isEmpty }.sorted { $0.updatedAt > $1.updatedAt } }
    var hasUnsavedChanges: Bool { !pendingScratchpads.isEmpty }

    func projectColorHex(for name: String?) -> String? {
        guard let name, Self.isValidProjectName(name) else { return nil }
        return snapshot.projectColors?[name]?.uppercased() ?? Self.defaultProjectColorHex
    }

    /// Creates the project marker and its appearance in one atomic workspace write.
    func createProject(name: String, colorHex: String) throws {
        guard let normalizedName = Self.normalizedProjectName(name) else {
            throw WorkspaceError.invalidProjectName
        }
        guard let normalizedColor = Self.normalizedProjectColorHex(colorHex) else {
            throw WorkspaceError.invalidProjectColor
        }
        var next = snapshot
        let key = WorkspaceSnapshot.projectKey(normalizedName)
        if next.scratchpads[key] == nil {
            next.scratchpads[key] = WorkspaceScratchpad(text: "", projectName: normalizedName, updatedAt: Date())
        }
        var colors = next.projectColors ?? [:]
        colors[normalizedName] = normalizedColor
        next.projectColors = colors
        try save(next)
    }

    /// Assigning a color also persists an empty scratchpad marker so the project
    /// remains available even when its last capture is later moved elsewhere.
    func setProjectColor(hex: String, for name: String) throws {
        guard let normalizedName = Self.normalizedProjectName(name) else {
            throw WorkspaceError.invalidProjectName
        }
        guard let normalizedColor = Self.normalizedProjectColorHex(hex) else {
            throw WorkspaceError.invalidProjectColor
        }
        var next = snapshot
        let key = WorkspaceSnapshot.projectKey(normalizedName)
        if next.scratchpads[key] == nil {
            next.scratchpads[key] = WorkspaceScratchpad(text: "", projectName: normalizedName, updatedAt: Date())
        }
        var colors = next.projectColors ?? [:]
        colors[normalizedName] = normalizedColor
        next.projectColors = colors
        try save(next)
    }

    func scratchpad(project: String?) -> String {
        let key = WorkspaceSnapshot.projectKey(project)
        return pendingScratchpads[key] ?? snapshot.scratchpads[key]?.text ?? ""
    }
    func snippetName(for captureID: UUID) -> String? { snapshot.snippetNames[captureID.uuidString] }

    func setScratchpad(text: String, project: String?) throws {
        let name = project.map { String($0.prefix(180)) }
        var next = snapshot
        let key = WorkspaceSnapshot.projectKey(name)
        pendingScratchpads[key] = text
        next.scratchpads[key] = WorkspaceScratchpad(text: text, projectName: name, updatedAt: Date())
        try save(next)
        pendingScratchpads.removeValue(forKey: key)
    }

    func setOnShelf(_ ids: [UUID], included: Bool) throws {
        var next = snapshot
        let incoming = Set(ids)
        next.shelfCaptureIDs.removeAll { incoming.contains($0) }
        if included { next.shelfCaptureIDs.insert(contentsOf: Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }, at: 0) }
        try save(next)
    }

    func setSnippetName(_ name: String?, for captureID: UUID) throws {
        var next = snapshot
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        next.snippetNames[captureID.uuidString] = trimmed.isEmpty ? nil : String(trimmed.prefix(120))
        try save(next)
    }

    func markInboxProcessed(_ ids: [UUID], processed: Bool = true) throws {
        var next = snapshot
        var existing = Set(next.processedInboxIDs)
        if processed { ids.forEach { existing.insert($0) } }
        else { ids.forEach { existing.remove($0) } }
        next.processedInboxIDs = existing.sorted { $0.uuidString < $1.uuidString }
        try save(next)
    }

    func reload() throws { snapshot = try Self.readSnapshot(at: root) ?? WorkspaceSnapshot(); error = nil; unreadable = false }

    func save(_ value: WorkspaceSnapshot) throws {
        guard !unreadable else { throw WorkspaceError.invalidArchive }
        do {
            let checked = try value.validated()
            try failureInjector?()
            try Self.writeSnapshot(checked, at: root)
            snapshot = checked
            error = nil
        } catch { self.error = error.localizedDescription; throw error }
    }

    static func readSnapshot(at root: URL) throws -> WorkspaceSnapshot? {
        let url = root.appendingPathComponent(filename)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw WorkspaceError.invalidArchive }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? 0) <= 64_000_000 else { throw WorkspaceError.invalidArchive }
        return try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: url)).validated()
    }

    static func writeSnapshot(_ value: WorkspaceSnapshot, at root: URL) throws {
        let checked = try value.validated()
        let url = root.appendingPathComponent(filename)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw WorkspaceError.invalidArchive }
        if FileManager.default.fileExists(atPath: url.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw WorkspaceError.invalidArchive }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(checked)
        guard bytes.count <= 64_000_000 else { throw WorkspaceError.invalidArchive }
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func updatePreference(_ change: (inout WorkspaceSnapshot) -> Void) {
        var next = snapshot; change(&next)
        guard next != snapshot else { return }
        do { try save(next) } catch { self.error = error.localizedDescription }
    }

    nonisolated static func isValidProjectName(_ name: String) -> Bool {
        normalizedProjectName(name) == name
    }

    nonisolated static func isValidProjectColorHex(_ hex: String) -> Bool {
        normalizedProjectColorHex(hex) != nil
    }

    nonisolated private static func normalizedProjectName(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty, normalized.count <= 180,
              !normalized.unicodeScalars.contains(where: {
                  CharacterSet.newlines.union(.controlCharacters).contains($0)
              }) else { return nil }
        return normalized
    }

    nonisolated private static func normalizedProjectColorHex(_ value: String) -> String? {
        guard value.utf8.count == 6,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
              }) else { return nil }
        return value.uppercased()
    }
}
