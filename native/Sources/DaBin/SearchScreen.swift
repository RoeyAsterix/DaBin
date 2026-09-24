import SwiftUI

@MainActor
struct SearchScreen: View {
    @ObservedObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        let groups = state.searchGroups
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Find something from your day", text: $state.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
                    .accessibilityLabel("Search captures")
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                        .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
                }
            }.padding(10).background(Palette.soft, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16).padding(.bottom, 7)
            if state.searchScope != .all {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                    Text(state.searchScopeTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Search scope, \(state.searchScopeTitle)")
            }
            FilterBar(selection: $state.filter)
            if let index = state.contentIndex, index.isBusy {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(index.pendingCount == 1
                         ? "Making 1 capture searchable…"
                         : "Making \(index.pendingCount) captures searchable…")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 18).padding(.top, 5)
                .accessibilityElement(children: .combine)
            }
            if state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyMessage(symbol: "magnifyingglass", title: "Remember the moment", message: searchPrompt)
            } else if groups.isEmpty, state.contentIndex?.isBusy == true {
                EmptyMessage(symbol: "text.viewfinder", title: "Search is still getting ready",
                             message: "Results update as saved captures become searchable.")
            } else if groups.isEmpty {
                EmptyMessage(symbol: "magnifyingglass", title: "No matching captures", message: "Try another word or choose All.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            Text(prettyDay(group.day)).font(.system(size: 13, weight: .semibold))
                                .padding(.top, 15).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
                            ForEach(group.entries) { entry in
                                CaptureRow(state: state, capture: entry.capture, featured: false,
                                           isMatch: entry.isMatch, indexedTextMatch: entry.indexedTextMatch)
                                    .id(entry.id)
                            }
                        }
                    }.scrollTargetLayout().padding(.horizontal, 16)
                }.scrollPosition(id: $state.searchScrollID, anchor: .top)
            }
        }.onAppear { focused = true }
    }

    private var searchPrompt: String {
        let base = "Search words, links, filenames, comments, screenshots, supported documents or a date. Matches keep a little of their day around them."
        return state.searchScope == .all ? base : "Search within \(state.searchScopeTitle). Matches keep a little of their day around them."
    }
}
