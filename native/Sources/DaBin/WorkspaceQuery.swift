import Foundation

@MainActor
enum WorkspaceQuery {
    static func sourceName(_ capture: Capture) -> String? {
        CaptureSourcePresentation.applicationName(name: capture.sourceApplicationName,
            identifier: capture.sourceApplicationBundleIdentifier)
    }

    /// The shelf and its complete ZIP export share membership and project
    /// ownership. Explicitly shelved attachments follow their parent task.
    static func shelfItems(_ captures: [Capture], workspace: WorkspaceStore, project: String?) -> [Capture] {
        let shelf = workspace.shelfCaptureIDs
        let parents = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        return captures.filter { capture in
            let parent = capture.parentTaskID.flatMap { parents[$0] }
            let projectName = parent == nil ? capture.projectName : parent?.projectName
            return capture.deletedAt == nil && shelf.contains(capture.id)
                && (project == nil || projectName == project)
                && (!workspace.explorerUnfiledOnly || project != nil || projectName == nil)
        }.sorted {
            $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt < $1.capturedAt
        }
    }

    static func items(_ captures: [Capture], workspace: WorkspaceStore, project: String?,
                      filter: CaptureFilter, query: String, pinnedOnly: Bool = false,
                      now: Date = Date()) -> [Capture] {
        let words = CaptureSearch.normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let isShelf = workspace.mode == .shelf
        let candidates = isShelf ? shelfItems(captures, workspace: workspace, project: project) : captures.filter {
            $0.deletedAt == nil && $0.parentTaskID == nil
                && (project == nil || $0.projectName == project)
                && (!workspace.explorerUnfiledOnly || project != nil || $0.projectName == nil)
        }
        let parents = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        return candidates.filter { capture in
            guard filter.includes(capture), !pinnedOnly || capture.isPinned,
                  workspace.sourceApplication == nil || sourceName(capture) == workspace.sourceApplication,
                  workspace.dateFilter.includes(capture.captureDay, now: now),
                  workspace.originFilter.includes(capture.captureOrigin) else { return false }
            switch workspace.mode {
            case .clipboard:
                if workspace.snippetsOnly {
                    guard workspace.snippetName(for: capture.id) != nil else { return false }
                } else {
                    guard capture.captureOrigin == .automaticClipboard
                            || ([CaptureKind.text, .link].contains(capture.kind) && !capture.isTask) else { return false }
                }
            case .shelf, .collection: break
            case .scratchpad: return false
            }
            guard !words.isEmpty else { return true }
            let parent = isShelf ? capture.parentTaskID.flatMap { parents[$0] } : nil
            let projectName = parent == nil ? capture.projectName : parent?.projectName
            let metadata = CaptureSearch.normalized([capture.title,
                capture.originalFilename ?? "", capture.originalURL ?? "", capture.comment,
                projectName ?? "", sourceName(capture) ?? "", capture.captureDay,
                workspace.snippetName(for: capture.id) ?? ""].joined(separator: " "))
            return words.allSatisfy { metadata.contains($0) || capture.normalizedOriginalTextForSearch.contains($0)
                || capture.normalizedIndexedTextForSearch.contains($0) }
        }.sorted {
            // New copies stay within reach even when there are many pinned items.
            $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt
        }
    }

    static func plainText(_ capture: Capture) -> String? {
        [capture.originalText, capture.originalURL, capture.indexedText.isEmpty ? nil : capture.indexedText]
            .compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
