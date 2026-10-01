import SwiftUI

@MainActor
struct SearchScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent

    private var hasRefinements: Bool { state.filter != .all || state.searchProject != nil || state.searchSource != nil }
    private var projectNames: [String] { Array(Set(state.projectNames + state.workspace.projectNames)).sorted() }

    private var matchCount: Int { state.searchGroups.reduce(0) { $0 + $1.entries.filter(\.isMatch).count } }
    private var noteMatches: [WorkspaceScratchpad] {
        let words = CaptureSearch.normalized(state.query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, state.searchSource == nil, state.filter == .all || state.filter == .text else { return [] }
        return state.workspace.snapshot.scratchpads.values.filter { note in
            (state.searchProject == nil || state.searchProject == note.projectName)
            && state.searchScope.includes(captureDay: CaptureCalendar.dayString(note.updatedAt))
            && words.allSatisfy { CaptureSearch.normalized(note.text + " " + (note.projectName ?? "")).contains($0) }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? state.searchScopeTitle : "\(matchCount + noteMatches.count) matches · \(state.searchScopeTitle)")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("search-scope-summary")
                Spacer(minLength: 0)
                CaptureFilterMenu(selection: $state.filter)
            }.padding(.horizontal, 16).padding(.top, 10)
            HStack(spacing: 8) {
                Menu {
                    Button("All projects") { state.searchProject = nil }
                    ForEach(projectNames, id: \.self) { project in Button(project) { state.searchProject = project } }
                } label: { Label(state.searchProject ?? "All projects", systemImage: "folder").lineLimit(1).truncationMode(.middle) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buddyHelp(state.searchProject ?? "Search all projects")
                    .accessibilityLabel("Search project: \(state.searchProject ?? "All projects")")
                Menu {
                    Button("All apps") { state.searchSource = nil }
                    ForEach(Array(Set(state.store.captures.compactMap(\.sourceApplicationName))).sorted(), id: \.self) { source in
                        Button(source) { state.searchSource = source }
                    }
                } label: { Label(state.searchSource ?? "All apps", systemImage: "app.dashed").lineLimit(1).truncationMode(.middle) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buddyHelp(state.searchSource ?? "Search all source apps")
                    .accessibilityLabel("Search source: \(state.searchSource ?? "All apps")")
            }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true).font(.system(size: 12))
                .padding(.horizontal, 16).padding(.top, 8)
            Toggle("Show nearby captures", isOn: $state.showSearchContext)
                .toggleStyle(.checkbox).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .buddyHelp("Include captures saved immediately around each match")
            if let index = state.contentIndex, index.isBusy {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Making \(index.pendingCount) captures searchable…")
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 16).padding(.bottom, 7).accessibilityElement(children: .combine)
            }
            if state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyMessage(symbol: "magnifyingglass", title: "Find something you saved", message: "Search words, links, filenames, notes or recognized text. The date, project and app filters above define where to look.")
            } else if state.searchGroups.isEmpty && noteMatches.isEmpty {
                VStack(spacing: 8) {
                    EmptyMessage(symbol: "magnifyingglass", title: "No matching captures", message: state.contentIndex?.isBusy == true ? "Results update as saved captures become searchable." : "Try another word, or broaden the date, project, app or type filters.")
                    if hasRefinements {
                        Button("Clear search filters", systemImage: "line.3.horizontal.decrease.circle") {
                            state.filter = .all; state.searchProject = nil; state.searchSource = nil
                        }.accessibilityIdentifier("search-clear-filters")
                    }
                    if state.searchScope != .all {
                        Button("Search all dates", systemImage: "calendar") { state.searchAllDates() }
                            .accessibilityIdentifier("search-all-dates")
                    }
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent).padding(.bottom, 14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(noteMatches, id: \.projectName) { note in
                            Button {
                                state.libraryProject = note.projectName
                                state.workspace.mode = .scratchpad
                                state.openLibrary()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Scratchpad · \(note.projectName ?? "Inbox")", systemImage: "note.text")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(note.text).font(.system(size: 12)).lineLimit(3).foregroundStyle(Palette.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                            }.buttonStyle(.plain)
                        }
                        ForEach(state.searchGroups) { group in
                            Text(prettyDay(group.day)).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.muted).padding(.top, 12).accessibilityAddTraits(.isHeader)
                            ForEach(group.entries) { entry in
                                CaptureRow(state: state, capture: entry.capture, featured: false,
                                           isMatch: state.showSearchContext ? entry.isMatch : nil,
                                           indexedTextMatch: entry.indexedTextMatch).id(entry.id)
                            }
                        }
                    }.scrollTargetLayout().padding(.horizontal, 16)
                }.scrollPosition(id: $state.searchScrollID, anchor: .top)
            }
        }
    }
}
