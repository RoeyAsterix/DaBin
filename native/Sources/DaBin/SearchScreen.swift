import SwiftUI

@MainActor
struct SearchScreen: View {
    @ObservedObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
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
            FilterBar(selection: $state.filter)
            if state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyMessage(symbol: "magnifyingglass", title: "Remember the moment", message: "Search words, links, filenames, comments or a date. Matches keep a little of their day around them.")
            } else if state.searchGroups.isEmpty {
                EmptyMessage(symbol: "magnifyingglass", title: "No matching captures", message: "Try another word or choose All.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.searchGroups) { group in
                            Text(prettyDay(group.day)).font(.system(size: 13, weight: .semibold))
                                .padding(.top, 15).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
                            ForEach(group.entries) { entry in
                                CaptureRow(state: state, capture: entry.capture, featured: false, isMatch: entry.isMatch)
                                    .id(entry.id)
                            }
                        }
                    }.scrollTargetLayout().padding(.horizontal, 16)
                }.scrollPosition(id: $state.searchScrollID, anchor: .top)
            }
        }.onAppear { focused = true }
    }
}
