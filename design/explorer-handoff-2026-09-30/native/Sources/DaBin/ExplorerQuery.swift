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
            let haystack = CaptureSearch.normalized([capture.title, capture.originalText ?? "", capture.originalURL ?? "",
                capture.originalFilename ?? "", capture.comment, projectName ?? "", capture.captureDay,
                WorkspaceQuery.sourceName(capture) ?? "", workspace.snippetName(for: capture.id) ?? ""].joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) || capture.normalizedIndexedTextForSearch.contains($0) }
        }.sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
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
