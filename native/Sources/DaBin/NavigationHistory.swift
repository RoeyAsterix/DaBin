import Foundation

/// Presentation-only anchors. Neighbors let a deleted row fall back to an
/// adjacent surviving identity, never to whichever item occupies an old index.
struct NavigationViewportAnchor: Equatable {
    var itemID: String
    var offset: Double = 0
    var neighbors: [String] = []

    func resolving(against available: Set<String>) -> Self? {
        guard let id = ([itemID] + neighbors).first(where: available.contains) else { return nil }
        return Self(itemID: id, offset: offset.isFinite ? offset : 0,
                    neighbors: Array(neighbors.filter(available.contains).prefix(8)))
    }
}

/// Session presentation belongs to AppState, not a view's lifetime. It contains
/// no notes, comments, file bodies, clipboard contents, or draft copies.
struct ProjectNavigationPresentation: Equatable {
    var filterRawValue = "All"
    var dateFilter: WorkspaceDateFilter = .anytime
    var newestFirst = false
    var compact = false
    var selectedIDs: Set<String> = []
    var selectionAnchor: String?
    var focusedID: String?
    var viewport: NavigationViewportAnchor?
}

struct NavigationWorkspacePresentation: Equatable {
    var mode: WorkspaceMode = .collection
    var selectedID: UUID?
    var source: String?
    var dateFilter: WorkspaceDateFilter = .anytime
    var originFilter: WorkspaceOriginFilter = .all
    var snippetsOnly = false
    var unfiledOnly = false
    var grouping: ExplorerGrouping = .type
    var query = ""
    var dailyFiles = false
}

struct NavigationReturnContext: Equatable {
    var origin: BoardRoute = .daily
    var attachmentTaskID: UUID?
    var creation: BoardRoute = .inbox
    var auxiliary: BoardRoute = .inbox
    var search: BoardRoute = .daily
    var searchFilter: CaptureFilter = .all
    var searchCreation: BoardRoute = .inbox
    var searchAuxiliary: BoardRoute = .inbox
    var searchCaptureID: UUID?
    var searchDetailID: UUID?
    var searchDetailOrigin: BoardRoute = .daily
    var searchDetailAttachmentID: UUID?
    var searchDetailFocus: String?
}

struct NavigationSnapshot: Equatable {
    var route: BoardRoute = .inbox
    var project: String?
    var selectedCaptureID: UUID?
    var selectedNoteProjectKey: String?
    var day = Date()
    var weekEndingDay = Date()
    var weeklyDays: [Date]?
    var filter: CaptureFilter = .all
    var pinnedOnly = false
    var query = ""
    var searchProject: String?
    var searchUnfiledOnly = false
    var searchSource: String?
    var searchScope: CaptureSearchScope = .all
    var searchDay = Date()
    var searchWeekEndingDay = Date()
    var searchRangeStartDay = Date()
    var searchRangeEndDay = Date()
    var searchContext = false
    var dailyScrollID: CaptureFeedCardID?
    var searchScrollID: UUID?
    var searchDateAnchor: String?
    var searchSelectedResultID: String?
    var searchColumnScrollIDs: [String: String] = [:]
    var searchColumnViewports: [String: NavigationViewportAnchor] = [:]
    var weeklyColumnViewports: [String: NavigationViewportAnchor] = [:]
    var expandedHours: Set<AutomaticHourKey> = []
    var focus: String?
    var focusTarget: String?
    var workspace = NavigationWorkspacePresentation()
    var todayPlanningScope = "today"
    var workspaceViewport: NavigationViewportAnchor?
    var projectPresentation: ProjectNavigationPresentation?
    var returnContext = NavigationReturnContext()

    /// Only a Search destination owns the search session's query/refinements.
    /// Returning to an unrelated workspace keeps the user's latest search words.
    var belongsToSearchSession: Bool {
        var visited: [BoardRoute] = []
        var current = route
        while !visited.contains(current) {
            visited.append(current)
            switch current {
            case .search, .searchNote: return true
            case .detail: current = returnContext.origin
            case .newTask, .newNote: current = returnContext.creation
            case .settings, .trash: current = returnContext.auxiliary
            default: return false
            }
        }
        return false
    }

    /// Refinements update the current entry; only deliberate destinations can
    /// create a new branch. Dates compare by civil day, not incidental seconds.
    func hasSameDestination(as other: Self) -> Bool {
        guard route == other.route else { return false }
        switch route {
        case .detail: return selectedCaptureID == other.selectedCaptureID
        case .searchNote: return selectedNoteProjectKey == other.selectedNoteProjectKey
        case .library: return project == other.project && workspace.mode == other.workspace.mode
            && workspace.unfiledOnly == other.workspace.unfiledOnly
        case .daily: return CaptureCalendar.dayString(day) == CaptureCalendar.dayString(other.day)
        case .weekly:
            let days = weeklyDays ?? WeeklyDateSelection.trailingWeek(ending: weekEndingDay)
            let otherDays = other.weeklyDays ?? WeeklyDateSelection.trailingWeek(ending: other.weekEndingDay)
            return days.map { CaptureCalendar.dayString($0) } == otherDays.map { CaptureCalendar.dayString($0) }
        default: return true
        }
    }
}

/// Bounded, session-only browser history. Callers refresh the current entry
/// before leaving; live arrivals never call visit and cannot cut a Forward branch.
struct NavigationHistory {
    static let maximumEntries = 100
    private(set) var entries: [NavigationSnapshot] = []
    private(set) var index = 0
    var current: NavigationSnapshot? { entries.indices.contains(index) ? entries[index] : nil }
    var canGoBack: Bool { index > 0 && !entries.isEmpty }
    var canGoForward: Bool { index + 1 < entries.count }

    mutating func updateCurrent(_ snapshot: NavigationSnapshot) {
        if entries.isEmpty { entries = [snapshot]; index = 0 }
        else { entries[index] = snapshot }
    }

    mutating func visit(_ snapshot: NavigationSnapshot) {
        guard let current else { updateCurrent(snapshot); return }
        guard !current.hasSameDestination(as: snapshot) else { updateCurrent(snapshot); return }
        if canGoForward { entries.removeSubrange((index + 1)..<entries.count) }
        entries.append(snapshot)
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
        index = entries.count - 1
    }

    mutating func back() -> NavigationSnapshot? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    mutating func forward() -> NavigationSnapshot? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    /// Reopening the live Search session from a result/auxiliary page returns
    /// to its existing entry, preserving Forward instead of making a loop.
    mutating func returnToPreviousSearch() {
        guard index > 0, let previous = entries[..<index].lastIndex(where: { $0.route == .search }) else { return }
        index = previous
    }

    /// Resolve edits/deletions against current data. Nil removes an entry;
    /// adjacent destinations collapsing to one are coalesced without a loop.
    mutating func reconcile(_ resolve: (NavigationSnapshot) -> NavigationSnapshot?) {
        var next: [NavigationSnapshot] = []
        var nextIndex = 0
        for (oldIndex, old) in entries.enumerated() {
            guard let resolved = resolve(old) else { continue }
            if let previous = next.last, previous.hasSameDestination(as: resolved) {
                if oldIndex <= index { next[next.count - 1] = resolved; nextIndex = next.count - 1 }
            } else {
                next.append(resolved)
                if oldIndex <= index { nextIndex = next.count - 1 }
            }
        }
        entries = next
        index = min(nextIndex, max(0, entries.count - 1))
    }
}
