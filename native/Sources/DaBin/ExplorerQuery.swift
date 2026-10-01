import Foundation

enum ExplorerGrouping: String, Codable, CaseIterable, Identifiable {
    case type, date
    var id: String { rawValue }
    var title: String { self == .type ? "Type" : "Date" }
    var symbol: String { self == .type ? "square.grid.2x2" : "calendar" }
}

struct ExplorerSection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let captures: [Capture]
}

struct ExplorerProjectDay: Hashable, Sendable {
    let projectName: String?
    let day: String
}

@MainActor enum ExplorerQuery {
    static func project(of capture: Capture, in captures: [Capture]) -> String? {
        if let parent = capture.parentTaskID, let task = captures.first(where: { $0.id == parent }) {
            return task.projectName
        }
        return capture.projectName
    }

    static func items(_ captures: [Capture], workspace: WorkspaceStore, project: String?,
                      filter: CaptureFilter, pinnedOnly: Bool, now: Date = Date()) -> [Capture] {
        let words = CaptureSearch.normalized(workspace.explorerQuery).split(whereSeparator: \.isWhitespace).map(String.init)
        let parents = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        return captures.filter { capture in
            let parent = capture.parentTaskID.flatMap { parents[$0] }
            let projectName = parent == nil ? capture.projectName : parent?.projectName
            guard capture.deletedAt == nil, project == nil || projectName == project,
                  !(workspace.explorerUnfiledOnly && project == nil) || projectName == nil,
                  filter.includes(capture), !pinnedOnly || capture.isPinned,
                  workspace.sourceApplication == nil || WorkspaceQuery.sourceName(capture) == workspace.sourceApplication,
                  workspace.dateFilter.includes(capture.captureDay, now: now),
                  workspace.originFilter.includes(capture.captureOrigin) else { return false }
            // Browsing does not need to fold the full immutable content of every
            // capture. Large pasted documents must stay out of the empty-search path.
            guard !words.isEmpty else { return true }
            let haystack = CaptureSearch.normalized([capture.title, capture.originalURL ?? "",
                capture.originalFilename ?? "", capture.comment, projectName ?? "", capture.captureDay,
                WorkspaceQuery.sourceName(capture) ?? "", workspace.snippetName(for: capture.id) ?? ""].joined(separator: " "))
            return words.allSatisfy {
                haystack.contains($0) || capture.normalizedOriginalTextForSearch.contains($0)
                    || capture.normalizedIndexedTextForSearch.contains($0)
            }
        }.sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
    }

    /// Snapshot only the facts needed to list dated files. Parent ownership is
    /// resolved once on the main actor before filesystem validation runs away
    /// from the view, without passing mutable Capture objects to a worker.
    static func projectDays(_ captures: [Capture], in records: [Capture]) -> [ExplorerProjectDay] {
        let parents = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return captures.filter { $0.deletedAt == nil }.map { capture in
            let parent = capture.parentTaskID.flatMap { parents[$0] }
            return ExplorerProjectDay(projectName: parent == nil ? capture.projectName : parent?.projectName,
                                      day: capture.captureDay)
        }
    }

    nonisolated static func dailyDocuments(_ days: [ExplorerProjectDay], archive: DailyArchive,
                                           project: String?, unfiledOnly: Bool) throws -> [ProjectArchiveDay] {
        try Dictionary(grouping: days, by: { $0 }).compactMap { day, captures in
            guard (!unfiledOnly || day.projectName == nil), project == nil || day.projectName == project else { return nil }
            let relative = try ProjectFileArchive.dayRelativePath(project: day.projectName, day: day.day)
                + "/\(day.day) - Captures and Links.md"
            return ProjectArchiveDay(projectName: day.projectName, captureDay: day.day,
                                     url: try archive.safeURL(relative), captureCount: captures.count)
        }.sorted { $0.captureDay == $1.captureDay ? ($0.projectName ?? "") < ($1.projectName ?? "") : $0.captureDay > $1.captureDay }
    }

    static func sections(_ captures: [Capture], grouping: ExplorerGrouping) -> [ExplorerSection] {
        if grouping == .date {
            return Dictionary(grouping: captures, by: \.captureDay).sorted { $0.key > $1.key }.map {
                ExplorerSection(id: $0.key, title: prettyDay($0.key), symbol: "calendar", captures: $0.value)
            }
        }
        let groups = Dictionary(grouping: captures, by: category)
        return [("files", "Files", "doc"), ("media", "Media", "photo.on.rectangle"),
                ("links", "Links", "link"), ("text", "Text and notes", "text.alignleft"),
                ("tasks", "Tasks", "checkmark.circle")].compactMap { key, title, symbol in
            guard let values = groups[key], !values.isEmpty else { return nil }
            return ExplorerSection(id: key, title: title, symbol: symbol, captures: values)
        }
    }

    static func category(_ capture: Capture) -> String {
        // An image converted to a task stays beside its image, with a task badge.
        switch capture.kind {
        case .image, .video: return "media"
        case .link: return "links"
        case .text: return "text"
        case .task: return "tasks"
        default: return "files"
        }
    }
}
