import Foundation
import Combine

/// The project header and grid share the same unfiltered, metadata-only scope.
/// Attachments follow their parent task's current project, including Unfiled.
@MainActor enum ProjectWorkspaceContents {
    static func captures(in project: String, from captures: [Capture]) -> [Capture] {
        let parents = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        return captures.filter { capture in
            guard capture.deletedAt == nil else { return false }
            let parent = capture.parentTaskID.flatMap { parents[$0] }
            return (parent?.projectName ?? (parent == nil ? capture.projectName : nil)) == project
        }
    }

    static func itemCount(in project: String, captures: [Capture], scratchpad: String) -> Int {
        self.captures(in: project, from: captures).count
            + (scratchpad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }
}

/// The compact project picker redraws during every workspace magnification
/// update. Its count and appearance depend on data changes, not window size.
/// Retain only the current project's small summary, never a second archive.
@MainActor final class ProjectWorkspaceSummaryCache {
    struct Summary: Equatable {
        let itemCount: Int
        let colorHex: String
    }
    private let store: CaptureStore
    private let workspace: WorkspaceStore
    private var subscriptions: [AnyCancellable] = []
    private var project: String?
    private var value: Summary?
    private(set) var buildCount = 0

    init(store: CaptureStore, workspace: WorkspaceStore) {
        self.store = store; self.workspace = workspace
        subscriptions = [store.objectWillChange.sink { [weak self] _ in self?.invalidate() },
                         workspace.objectWillChange.sink { [weak self] _ in self?.invalidate() }]
    }

    private func invalidate() { project = nil; value = nil }

    func summary(for project: String) -> Summary {
        if self.project == project, let value { return value }
        let summary = Summary(
            itemCount: ProjectWorkspaceContents.itemCount(in: project, captures: store.captures,
                                                         scratchpad: workspace.scratchpad(project: project)),
            colorHex: workspace.projectColorHex(for: project) ?? WorkspaceStore.defaultProjectColorHex)
        self.project = project; value = summary; buildCount += 1
        return summary
    }
}

/// Stable identities include the capture's original type-independent UUID and
/// the project's existing scratchpad, without copying either into a new store.
enum ProjectWorkspaceIdentity {
    static func capture(_ id: UUID) -> String { "capture:" + id.uuidString }
    static func note(project: String?) -> String { "note:" + WorkspaceSnapshot.projectKey(project) }

    static func isValid(_ id: String, scope: String) -> Bool {
        if id.hasPrefix("capture:") { return UUID(uuidString: String(id.dropFirst(8))) != nil }
        return id == "note:" + scope
    }
}

enum ProjectWorkspaceOrdering {
    enum Direction { case earlier, later }

    /// Native List virtualizes grid rows rather than individual cards. For a
    /// newest-first feed, keep complete rows anchored from the oldest end so a
    /// new capture changes only the leading partial row instead of every row
    /// identity. A saved manual order receives new captures at the end instead.
    static func rows(ids: [String], columns: Int, newestFirst: Bool) -> [[String]] {
        guard !ids.isEmpty else { return [] }
        let width = max(1, columns)
        var result: [[String]] = []
        result.reserveCapacity((ids.count - 1) / width + 1)
        var index = 0
        let leadingCount = newestFirst ? ids.count % width : 0
        if leadingCount > 0 {
            result.append(Array(ids[..<leadingCount]))
            index = leadingCount
        }
        while index < ids.count {
            let end = index + min(width, ids.count - index)
            result.append(Array(ids[index..<end]))
            index = end
        }
        return result
    }

    /// Missing/deleted items never render. Newly added items follow the saved
    /// sequence in the caller's default order; stored positions stay stable.
    static func ordered(_ available: [String], saved: [String]) -> [String] {
        var remaining = Set(available)
        let known = saved.filter { remaining.remove($0) != nil }
        return known + available.filter { remaining.remove($0) != nil }
    }

    /// Each selected block moves by one adjacent unselected item, retaining the
    /// relative order of both selected and unselected items.
    static func move(_ ids: [String], selected: Set<String>, direction: Direction) -> [String] {
        guard ids.count > 1, !selected.isEmpty else { return ids }
        var result = ids
        switch direction {
        case .earlier:
            for index in 1..<result.count where selected.contains(result[index]) && !selected.contains(result[index - 1]) {
                result.swapAt(index, index - 1)
            }
        case .later:
            for index in (0..<(result.count - 1)).reversed()
                where selected.contains(result[index]) && !selected.contains(result[index + 1]) {
                result.swapAt(index, index + 1)
            }
        }
        return result
    }

    /// Reposition the selected block before a visible target. A nil target means
    /// the end; dropping on a selected item is intentionally a no-op.
    static func moving(_ ids: [String], selected: Set<String>, before target: String?) -> [String] {
        guard !selected.isEmpty, target.map({ !selected.contains($0) && ids.contains($0) }) ?? true else { return ids }
        let moved = ids.filter { selected.contains($0) }
        var result = ids.filter { !selected.contains($0) }
        let insertion = target.flatMap { result.firstIndex(of: $0) } ?? result.endIndex
        result.insert(contentsOf: moved, at: insertion)
        return result
    }

    static func isValid(_ orders: [String: [String]]?) -> Bool {
        guard let orders else { return true }
        guard orders.count <= 5_001, orders.values.reduce(0, { $0 + $1.count }) <= 500_000 else { return false }
        return orders.allSatisfy { scope, ids in
            let validScope = scope == "inbox:" || (scope.hasPrefix("project:")
                && WorkspaceStore.isValidProjectName(String(scope.dropFirst(8))))
            return validScope && ids.count <= 100_000 && Set(ids).count == ids.count
                && ids.allSatisfy { ProjectWorkspaceIdentity.isValid($0, scope: scope) }
        }
    }
}

/// Selection is ephemeral and always scoped to visible identities. Filtering
/// cannot leave hidden items participating in destructive or bulk actions.
struct ProjectWorkspaceSelection: Equatable {
    private(set) var ids: Set<String> = []
    private(set) var anchorID: String?

    mutating func toggle(_ id: String, visible: [String], extending: Bool = false) {
        reconcile(visible: visible)
        guard let clicked = visible.firstIndex(of: id) else { return }
        if extending, let anchorID, let anchor = visible.firstIndex(of: anchorID) {
            ids.formUnion(visible[min(anchor, clicked)...max(anchor, clicked)])
        } else {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchorID = id
        }
    }

    mutating func selectAll(visible: [String]) { ids = Set(visible); anchorID = visible.first }
    mutating func clear() { ids.removeAll(); anchorID = nil }
    mutating func reconcile(visible: [String]) {
        let available = Set(visible)
        ids.formIntersection(available)
        if let anchorID, !available.contains(anchorID) { self.anchorID = nil }
    }
}

@MainActor extension WorkspaceStore {
    func orderedProjectItemIDs(_ available: [String], project: String?) -> [String] {
        ProjectWorkspaceOrdering.ordered(available,
            saved: snapshot.projectItemOrders?[WorkspaceSnapshot.projectKey(project)] ?? [])
    }

    /// Save the complete project sequence, never only the filtered selection.
    /// The workspace's normal atomic writer, error reporting and backups apply.
    func saveProjectItemOrder(_ ids: [String], project: String?) throws {
        var next = snapshot
        var orders = next.projectItemOrders ?? [:]
        orders[WorkspaceSnapshot.projectKey(project)] = ids
        guard orders != (next.projectItemOrders ?? [:]) else { return }
        next.projectItemOrders = orders
        try save(next)
    }
}
