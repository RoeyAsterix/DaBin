import Foundation

@MainActor
enum WorkspaceQuery {
    static func sourceName(_ capture: Capture) -> String? {
        CaptureSourcePresentation.applicationName(name: capture.sourceApplicationName,
            identifier: capture.sourceApplicationBundleIdentifier)
    }

    static func items(_ captures: [Capture], workspace: WorkspaceStore, project: String?,
                      filter: CaptureFilter, query: String, pinnedOnly: Bool = false,
                      now: Date = Date()) -> [Capture] {
        let words = CaptureSearch.normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let shelf = workspace.shelfCaptureIDs
        return captures.filter { capture in
            guard capture.deletedAt == nil, capture.parentTaskID == nil,
                  project == nil || capture.projectName == project,
                  !workspace.explorerUnfiledOnly || project != nil || capture.projectName == nil,
                  filter.includes(capture), !pinnedOnly || capture.isPinned,
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
            case .shelf: guard shelf.contains(capture.id) else { return false }
            case .collection: break
            case .scratchpad: return false
            }
            guard !words.isEmpty else { return true }
            let metadata = CaptureSearch.normalized([capture.title, capture.originalText ?? "",
                capture.originalFilename ?? "", capture.originalURL ?? "", capture.comment,
                capture.projectName ?? "", sourceName(capture) ?? "", capture.captureDay,
                workspace.snippetName(for: capture.id) ?? ""].joined(separator: " "))
            let indexed = capture.normalizedIndexedTextForSearch
            return words.allSatisfy { metadata.contains($0) || indexed.contains($0) }
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
