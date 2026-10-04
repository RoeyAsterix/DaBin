import SwiftUI

/// Only the visible date page owns list and preview views.
@MainActor
struct SearchScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent
    @FocusState private var focusedResult: String?
    private var isBrowsing: Bool { state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasFilters: Bool {
        state.filter != .all || state.searchProject != nil || state.searchUnfiledOnly
            || state.searchSource != nil || state.searchScope != .all
    }
    private var selectedCapture: Capture? {
        guard let id = state.searchSelectedResultID else { return nil }
        return state.store.captures.first { $0.deletedAt == nil && "capture:" + $0.id.uuidString == id }
    }

    var body: some View {
        let groups = state.searchDateGroups
        let total = groups.reduce(0) { $0 + $1.matchCount }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(total.formatted()) \(isBrowsing ? "saved items" : "matches") · \(groups.count.formatted()) dates")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("search-scope-summary")
                Spacer(minLength: 0)
                if hasFilters {
                    Button("Clear filters") { state.clearSearchFilters() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        .accessibilityIdentifier("search-clear-filters")
                }
            }.padding(.horizontal, 16).padding(.top, 9).padding(.bottom, 7)
            if hasFilters { filterChips }
            if let index = state.contentIndex, index.isBusy {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Reading text locally · \(index.pendingCount) remaining")
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 16).padding(.bottom, 7).accessibilityElement(children: .combine)
            }
            if groups.isEmpty {
                EmptyMessage(symbol: isBrowsing ? "tray" : "magnifyingglass",
                    title: isBrowsing ? "Your saved work will appear here" : "Nothing found yet",
                    message: state.contentIndex?.isBusy == true
                        ? "Results update as local text extraction finishes."
                        : hasFilters ? "Remove a filter or try another word."
                        : isBrowsing ? "Capture a file, a link or a thought. Come back here to find it."
                        : "Try a word from the content, project, comment or checklist.")
            } else {
                GeometryReader { geometry in
                    let capture = selectedCapture
                    let showsPreview = geometry.size.width >= 1_000 && capture != nil
                    let previewWidth = showsPreview ? min(380, geometry.size.width * 0.32) : 0
                    let boardWidth = max(0, geometry.size.width - previewWidth - (showsPreview ? 12 : 0))
                    let page = SearchDateBoard.page(groups: groups, anchorDay: state.searchDateAnchor, width: boardWidth)
                    HStack(spacing: 12) {
                        VStack(spacing: 8) {
                            dateNavigation(page)
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(page.groups) { group in
                                    SearchDateColumn(state: state, group: group, expanded: geometry.size.width >= 1_000,
                                                     focus: $focusedResult)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }.frame(width: boardWidth)
                        if showsPreview, let capture {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Preview").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                                    Spacer()
                                    SmallIcon(symbol: "xmark", label: "Close preview", size: 28) { state.searchSelectedResultID = nil }
                                }.padding(.horizontal, 14).padding(.top, 4)
                                ExplorerInspector(state: state, workspace: state.workspace, capture: capture,
                                                  height: max(200, geometry.size.height - 32), compactHeader: true)
                            }.frame(width: previewWidth)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.7))
                                .accessibilityElement(children: .contain).accessibilityLabel("Selected capture preview")
                                .accessibilityIdentifier("search-preview")
                        }
                    }
                    .onAppear { if state.searchDateAnchor == nil { state.searchDateAnchor = page.anchorDay } }
                    .onChange(of: page.anchorDay) { _, day in
                        if state.searchDateAnchor == nil { state.searchDateAnchor = day }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 10)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("Search saved DaBin content")
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if state.searchProject != nil || state.searchUnfiledOnly {
                    chip(state.searchUnfiledOnly ? "Unfiled" : state.searchProject!, symbol: "folder", id: "project") {
                        state.selectSearchProject(nil)
                    }
                }
                if state.filter != .all {
                    chip(state.filter.tooltipLabel, symbol: SearchFiltersControl.symbol(state.filter), id: "type") { state.filter = .all }
                }
                if state.searchScope != .all {
                    chip(state.searchScopeTitle, symbol: "calendar", id: "date") { state.searchAllDates() }
                }
                if let source = state.searchSource {
                    chip(source, symbol: "app", id: "source") { state.searchSource = nil }
                }
            }.padding(.horizontal, 16)
        }.scrollIndicators(.hidden).frame(height: 32).padding(.bottom, 5)
    }

    private func chip(_ title: String, symbol: String, id: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).frame(height: 27)
                .background(accent.opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.25), lineWidth: 0.7))
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityLabel("Remove \(id) filter: \(title)").accessibilityIdentifier("search-chip-\(id)")
            .buddyHelp("Remove \(title) filter")
    }

    private func dateNavigation(_ page: SearchDatePage) -> some View {
        HStack(spacing: 5) {
            Text(page.rangeLabel).font(.system(size: 11)).foregroundStyle(Palette.muted).monospacedDigit()
                .accessibilityIdentifier("search-date-page-label")
            Spacer(minLength: 0)
            SmallIcon(symbol: "chevron.left", label: "Newer dates", size: 28) { state.searchDateAnchor = page.newerAnchor }
                .disabled(!page.hasNewer).accessibilityIdentifier("search-newer-dates")
            SmallIcon(symbol: "chevron.right", label: "Older dates", size: 28) { state.searchDateAnchor = page.olderAnchor }
                .disabled(!page.hasOlder).accessibilityIdentifier("search-older-dates")
        }
    }
}

@MainActor
private struct SearchDateColumn: View {
    @ObservedObject var state: AppState
    let group: SearchDateGroup
    let expanded: Bool
    var focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(group.isUndated ? "Undated" : prettyDay(group.day))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(group.matchCount.formatted())").font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
            }.padding(.horizontal, 5).padding(.bottom, 3)
            Text("Saved · notes use edited date").font(.system(size: 10)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 5).padding(.bottom, 8)
            ScrollViewReader { proxy in
                List {
                    ForEach(group.items) { item in
                        SearchResultCard(state: state, item: item, expanded: expanded, focus: focus)
                            .id(item.id).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                            .listRowSeparator(.hidden).listRowBackground(Color.clear)
                            .onMoveCommand { direction in
                                guard direction == .up || direction == .down,
                                      let index = group.items.firstIndex(where: { $0.id == (focus.wrappedValue ?? item.id) }) else { return }
                                let next = min(group.items.count - 1, max(0, index + (direction == .down ? 1 : -1)))
                                let id = group.items[next].id
                                focus.wrappedValue = id
                                state.searchSelectedResultID = id
                                state.searchColumnScrollIDs[group.day] = id
                                proxy.scrollTo(id, anchor: .center)
                            }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .background {
                        ZStack {
                            SearchColumnViewport(state: state, day: group.day, rowIDs: group.items.map(\.id))
                            // Reuse Explorer's bounded native insertion guard:
                            // a new capture should not move the card being read.
                            ExplorerViewport(store: state.store, rowIDs: group.items.map(\.id),
                                context: ExplorerViewportContext(project: state.searchProject,
                                    unfiledOnly: state.searchUnfiledOnly, dailyFiles: false, query: state.query,
                                    filter: state.filter.rawValue, pinnedOnly: false, dateFilter: state.searchScopeTitle,
                                    source: state.searchSource, origin: "all", grouping: group.day, selectedID: nil),
                                historyAnchor: state.searchColumnViewports[group.day],
                                onHistoryAnchor: { state.searchColumnViewports[group.day] = $0 })
                        }
                    }
                    .onAppear {
                        let saved = state.searchColumnScrollIDs[group.day]
                        if let saved, group.items.contains(where: { $0.id == saved }) { proxy.scrollTo(saved, anchor: .top) }
                    }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("\(group.isUndated ? "Undated" : prettyDay(group.day)), \(group.matchCount) results")
            .accessibilityIdentifier("search-date-column-\(group.day)")
    }
}

/// Deliberate refinements live in one popover, with named chips on the board.
@MainActor
struct SearchFiltersControl: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent
    @State private var presented = false
    private enum Dates: String, CaseIterable { case all = "All dates", day = "One day", week = "One week", range = "Date range" }
    private var dateChoice: Dates {
        switch state.searchScope { case .all: .all; case .day: .day; case .week: .week; case .range: .range }
    }
    private var projects: [String] { Set(state.projectNames + state.workspace.projectNames).sorted() }
    private var sources: [String] { Set(state.store.captures.filter { $0.deletedAt == nil }.compactMap(WorkspaceQuery.sourceName)).sorted() }

    var body: some View {
        Button { presented.toggle() } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 8).frame(minHeight: 32)
                .background(accent.opacity(presented ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).foregroundStyle(accent).fixedSize()
            .buddyHelp("Narrow by project, type, date or source app").accessibilityIdentifier("search-filters")
            .popover(isPresented: $presented, arrowEdge: .bottom) { controls.hoverTooltips() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Filter saved items").font(.system(size: 15, weight: .semibold, design: .rounded)).accessibilityAddTraits(.isHeader)
            Picker("Project", selection: Binding(get: {
                state.searchUnfiledOnly ? "unfiled" : state.searchProject.map { "project:" + $0 } ?? "all"
            }, set: { value in
                if value == "unfiled" { state.searchUnfiledProject() }
                else { state.selectSearchProject(value.hasPrefix("project:") ? String(value.dropFirst(8)) : nil) }
            })) {
                Label("All projects", systemImage: "folder").tag("all")
                Label("Unfiled", systemImage: "tray").tag("unfiled")
                ForEach(projects, id: \.self) { Label($0, systemImage: "folder").tag("project:" + $0) }
            }.accessibilityIdentifier("search-project-picker")
            Picker("Type", selection: $state.filter) {
                ForEach(CaptureFilter.allCases) { Label($0 == .all ? "All types" : $0.tooltipLabel, systemImage: Self.symbol($0)).tag($0) }
            }.accessibilityIdentifier("search-type-picker")
            Picker("Source app", selection: Binding(get: { state.searchSource ?? "" }, set: { state.searchSource = $0.isEmpty ? nil : $0 })) {
                Label("All apps", systemImage: "app").tag("")
                ForEach(sources, id: \.self) { Label($0, systemImage: "app").tag($0) }
            }.accessibilityIdentifier("search-source-picker")
            Divider()
            Picker("Saved date", selection: Binding(get: { dateChoice }, set: { choice in
                switch choice {
                case .all: state.searchAllDates()
                case .day: state.setSearchDay(state.searchDay)
                case .week: state.setSearchWeek(ending: state.searchWeekEndingDay)
                case .range: state.setSearchRange(start: state.searchRangeStartDay, end: state.searchRangeEndDay)
                }
            })) { ForEach(Dates.allCases, id: \.self) { Label($0.rawValue, systemImage: "calendar").tag($0) } }
                .accessibilityIdentifier("search-date-mode")
            dateInputs
            Text(state.searchScopeTitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("search-date-selection")
            Text("Saved on this Mac. Captures keep their original date; notes use their last edit.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Clear filters") { state.clearSearchFilters() }.accessibilityIdentifier("search-clear-filters")
                Spacer()
                Button("Done") { presented = false }.keyboardShortcut(.defaultAction)
            }
        }.pickerStyle(.menu).font(.system(size: 12)).padding(16).frame(width: 288)
            .foregroundStyle(Palette.foreground).tint(accent).background(Palette.surface)
            .onExitCommand { presented = false }
            .accessibilityElement(children: .contain).accessibilityLabel("Search filters").accessibilityIdentifier("search-filters-popover")
    }

    @ViewBuilder private var dateInputs: some View {
        switch dateChoice {
        case .all: EmptyView()
        case .day:
            DatePicker("Day", selection: Binding(get: { state.searchDay }, set: { state.setSearchDay($0) }), displayedComponents: .date)
                .accessibilityIdentifier("search-day")
        case .week:
            DatePicker("Week ending", selection: Binding(get: { state.searchWeekEndingDay }, set: { state.setSearchWeek(ending: $0) }), displayedComponents: .date)
                .accessibilityIdentifier("search-week-ending")
            Text("Seven days, including the end date.").font(.system(size: 11)).foregroundStyle(Palette.muted)
        case .range:
            DatePicker("From", selection: Binding(get: { state.searchRangeStartDay }, set: { state.setSearchRange(start: $0, end: state.searchRangeEndDay) }), displayedComponents: .date)
                .accessibilityIdentifier("search-range-start")
            DatePicker("Through", selection: Binding(get: { state.searchRangeEndDay }, set: { state.setSearchRange(start: state.searchRangeStartDay, end: $0) }), displayedComponents: .date)
                .accessibilityIdentifier("search-range-end")
            Text("Both dates are included.").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    static func symbol(_ filter: CaptureFilter) -> String {
        switch filter {
        case .all: "square.grid.2x2"
        case .text: "text.alignleft"
        case .links: "link"
        case .files: "doc.text"
        case .media: "photo.on.rectangle"
        case .tasks: "checkmark"
        }
    }
}
