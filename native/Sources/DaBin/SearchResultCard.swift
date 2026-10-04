import SwiftUI

/// A bounded excerpt keeps large documents out of the card's rendered text.
struct SearchResultExcerpt {
    let text: String
    let label: String?

    @MainActor static func make(entry: SearchEntry, query: String) -> SearchResultExcerpt? {
        let capture = entry.capture
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if let indexed = entry.indexedTextMatch,
           let snippet = excerpt(indexed, words: words, requiresMatch: false) {
            return .init(text: snippet, label: "Extracted text")
        }
        let candidates: [(String, String?)] = [
            (capture.comment, "Comment"),
            (capture.taskPlanning?.checklist.map(\.text).joined(separator: "\n") ?? "", "Checklist"),
            (capture.originalText ?? "", nil), (capture.previewDescription, nil)
        ]
        if !words.isEmpty {
            for (text, label) in candidates {
                if let snippet = excerpt(text, words: words, requiresMatch: true) {
                    return .init(text: snippet, label: label)
                }
            }
        }
        let fallback = capture.originalText ?? (capture.previewDescription.isEmpty ? capture.comment : capture.previewDescription)
        guard let snippet = excerpt(fallback, words: [], requiresMatch: false), snippet != capture.title else { return nil }
        return .init(text: snippet, label: nil)
    }

    static func excerpt(_ text: String, words: [String], requiresMatch: Bool) -> String? {
        guard !text.isEmpty else { return nil }
        let match = words.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive],
                                                 locale: Locale(identifier: "en_US_POSIX")) }.min { $0.lowerBound < $1.lowerBound }
        if requiresMatch && match == nil { return nil }
        let start = match.map { text.index($0.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex } ?? text.startIndex
        let budget = 180 - (start > text.startIndex ? 1 : 0) - 1
        let end = text.index(start, offsetBy: budget, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return body.isEmpty ? nil : (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }
}

@MainActor
struct SearchResultCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    let item: SearchDateItem
    let expanded: Bool
    var focus: FocusState<String?>.Binding
    @Environment(\.daBinAccent) private var accent
    @State private var nearbyPresented = false
    @State private var copiedNote = false

    var body: some View {
        Group {
            switch item {
            case .capture(let entry): captureCard(entry)
            case .note(let note): noteCard(note)
            }
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("search-result-\(item.id)")
    }

    private func captureCard(_ entry: SearchEntry) -> some View {
        let capture = entry.capture
        let project = ExplorerQuery.project(of: capture, in: state.store.captures)
        let excerpt = SearchResultExcerpt.make(entry: entry, query: state.query)
        let selected = state.searchSelectedResultID == item.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                focus.wrappedValue = item.id
                state.searchSelectedResultID = item.id
                if !expanded { state.openCapture(capture.id) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if ExplorerCaptureCardPresentation.hasLargePreview(capture: capture, store: state.store) || capture.kind == .link {
                        CaptureThumbnail(store: state.store, capture: capture).frame(height: zoom.value(124))
                            .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: capture.isTask ? "checkmark.circle" : SearchFiltersControl.symbol(filter(for: capture)))
                            .foregroundStyle(capture.isCompleted ? Palette.completed : accent).accessibilityHidden(true)
                        Text(capture.isTask ? (capture.isCompleted ? "Completed task" : "Task") : captureTypeLabel(capture.kind))
                        Spacer(minLength: 0)
                        Text(captureClock(capture)).monospacedDigit()
                    }.font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
                    Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                        .font(.system(size: zoom.fontSize(15), weight: .semibold)).lineLimit(2)
                        .strikethrough(capture.isTask && capture.isCompleted)
                        .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                    if let alias = state.workspace.snippetName(for: capture.id) {
                        Label(alias, systemImage: "text.badge.star").font(.system(size: zoom.fontSize(11), weight: .medium)).foregroundStyle(accent).lineLimit(1)
                    }
                    if let excerpt {
                        VStack(alignment: .leading, spacing: 3) {
                            if let label = excerpt.label { Text(label).font(.system(size: zoom.fontSize(10), weight: .medium)).foregroundStyle(accent) }
                            Text(excerpt.text).font(.system(size: zoom.fontSize(12))).lineSpacing(zoom.lineSpacing(2)).lineLimit(3).foregroundStyle(Palette.muted)
                        }
                    }
                    if let source = WorkspaceQuery.sourceName(capture) {
                        HStack(spacing: 5) {
                            CaptureApplicationMark(application: CaptureSourcePresentation.origin(for: capture), size: 16)
                            Text(source).lineLimit(1)
                        }.font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted)
                    }
                    if capture.contentIndexState == "indexing" {
                        Label("Reading text locally…", systemImage: "text.viewfinder").font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted)
                    } else if capture.contentIndexState == "unavailable" {
                        Label("Metadata searchable · text unavailable", systemImage: "text.viewfinder")
                            .font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted).lineLimit(2)
                            .buddyHelp(capture.contentIndexError ?? "Text extraction is unavailable for this item. Saved metadata is searchable.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).multilineTextAlignment(.leading)
            }.buttonStyle(.plain).focusable().focused(focus, equals: item.id)
                .accessibilityIdentifier("search-select-\(capture.id.uuidString)")
                .accessibilityLabel("\(expanded ? "Preview" : "Open") \(capture.title), \(project ?? "Unfiled"), saved \(captureReceiptText(capture))")
                .accessibilityValue([excerpt?.label, excerpt?.text, WorkspaceQuery.sourceName(capture)].compactMap { $0 }.joined(separator: ". "))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .captureDragSource(state: state, capture: capture)
            CaptureTaskPriorityTag(capture: capture)
            HStack(spacing: 4) {
                ProjectChipLabel(name: project, colorHex: project.flatMap { state.workspace.projectColorHex(for: $0) }, inherited: capture.parentTaskID != nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SmallIcon(symbol: "arrow.up.forward.square", label: "Open details", size: 28) { state.openCapture(capture.id) }
                    .accessibilityIdentifier("search-open-\(capture.id.uuidString)")
                CaptureCopyButton(state: state, captures: [capture])
            }
        }.padding(zoom.value(10))
            .projectCardBackground(workspace: state.workspace, projectName: project, cornerRadius: 12,
                                   baseColor: selected ? Palette.soft : Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? accent.opacity(0.7) : Palette.line, lineWidth: selected ? 1.2 : 0.7))
            .contextMenu {
                ExplorerCaptureActions(state: state, workspace: state.workspace, capture: capture)
                if capture.parentTaskID == nil {
                    Menu {
                        Button("Unfiled", systemImage: "tray") { state.assignProject(capture, name: nil) }
                        ForEach(Set(state.projectNames + state.workspace.projectNames).sorted(), id: \.self) { project in
                            Button(project, systemImage: "folder") { state.assignProject(capture, name: project) }
                        }
                    } label: { Label("File to project", systemImage: "folder") }
                }
                Divider()
                Button("Show nearby captures", systemImage: "rectangle.stack") { nearbyPresented = true }
            }
            .popover(isPresented: $nearbyPresented, arrowEdge: .trailing) {
                SearchNearbyCaptures(state: state, capture: capture).hoverTooltips()
            }
    }

    private func noteCard(_ note: WorkspaceScratchpad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { state.openSearchNote(note) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("Project note", systemImage: "note.text")
                        Spacer(minLength: 0)
                        Text("Edited \(note.updatedAt.formatted(date: .omitted, time: .shortened))")
                    }.font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
                    Text(note.projectName.map { "\($0) notes" } ?? "Scratchpad")
                        .font(.system(size: zoom.fontSize(15), weight: .semibold)).lineLimit(2)
                    Text(SearchResultExcerpt.excerpt(note.text, words: state.query.split(whereSeparator: \.isWhitespace).map(String.init), requiresMatch: false) ?? "")
                        .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted).lineSpacing(zoom.lineSpacing(2)).lineLimit(4)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).multilineTextAlignment(.leading)
            }.buttonStyle(.plain).focusable().focused(focus, equals: item.id)
                .accessibilityLabel("Open \(note.projectName ?? "Unfiled") notes, edited \(note.updatedAt.formatted(date: .complete, time: .shortened))")
                .accessibilityValue(SearchResultExcerpt.excerpt(note.text, words: state.query.split(whereSeparator: \.isWhitespace).map(String.init), requiresMatch: false) ?? "")
                .nativeContentDrag(label: "Project notes", items: { [note.text as NSString] },
                                   onError: { state.reportFailure($0.localizedDescription) })
            HStack {
                ProjectChipLabel(name: note.projectName, colorHex: note.projectName.flatMap { state.workspace.projectColorHex(for: $0) })
                Spacer(minLength: 0)
                SmallIcon(symbol: "square.and.pencil", label: "Edit note", size: 28) { state.openSearchNote(note) }
                    .accessibilityIdentifier("search-edit-\(item.id)")
                SmallIcon(symbol: copiedNote ? "checkmark" : "doc.on.doc", label: copiedNote ? "Note copied" : "Copy note", size: 28) {
                    guard state.copySearchNote(note) else { return }
                    copiedNote = true
                }.accessibilityIdentifier("search-copy-\(item.id)")
            }
        }.padding(zoom.value(10)).projectCardBackground(workspace: state.workspace, projectName: note.projectName, cornerRadius: 12)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.7))
            .task(id: copiedNote) {
                guard copiedNote else { return }
                try? await Task.sleep(for: .seconds(1.25))
                guard !Task.isCancelled else { return }
                copiedNote = false
            }
    }

    private func filter(for capture: Capture) -> CaptureFilter {
        switch capture.kind {
        case .link: .links
        case .text, .task: .text
        case .image, .video: .media
        default: .files
        }
    }
}

@MainActor
private struct SearchNearbyCaptures: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    let capture: Capture

    private var neighbors: [Capture] {
        let items = CaptureSearch.ordered(state.store.captures.filter { item in
            let project = ExplorerQuery.project(of: item, in: state.store.captures)
            return item.deletedAt == nil && item.captureDay == capture.captureDay
                && (state.searchProject == nil || project == state.searchProject)
                && (!state.searchUnfiledOnly || project == nil)
                && (state.searchSource == nil || WorkspaceQuery.sourceName(item) == state.searchSource)
        })
        guard let index = items.firstIndex(where: { $0.id == capture.id }) else { return [] }
        return [index - 1, index + 1].filter { items.indices.contains($0) }.map { items[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nearby captures").font(.system(size: zoom.fontSize(15), weight: .semibold, design: .rounded))
            Text("Context from \(prettyDay(capture.captureDay)). These items are not included in the match count.")
                .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if neighbors.isEmpty { Text("No nearby captures on this saved day.").font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted) }
                    ForEach(neighbors) { neighbor in CaptureRow(state: state, capture: neighbor, featured: false, isMatch: false) }
                }
            }.frame(maxHeight: 380)
        }.padding(14).frame(width: 312).background(Palette.surface)
            .accessibilityElement(children: .contain).accessibilityLabel("Nearby capture context")
    }
}
