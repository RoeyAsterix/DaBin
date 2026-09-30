import SwiftUI

@MainActor
struct SearchScreen: View {
    @ObservedObject var state: AppState

    private var matchCount: Int { state.searchGroups.reduce(0) { $0 + $1.entries.filter(\.isMatch).count } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "All dates · all projects" : "\(matchCount) \(matchCount == 1 ? "match" : "matches") · all dates")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .accessibilityLabel("\(matchCount) search matches across all dates and projects")
                Spacer(minLength: 0)
                CaptureFilterMenu(selection: $state.filter)
            }.padding(.horizontal, 16).padding(.top, 10)
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
                EmptyMessage(symbol: "magnifyingglass", title: "Find something you saved", message: "Search words, links, filenames, notes, recognized text or a date across your entire archive.")
            } else if state.searchGroups.isEmpty {
                EmptyMessage(symbol: "magnifyingglass", title: "No matching captures", message: state.contentIndex?.isBusy == true ? "Results update as saved captures become searchable." : "Try another word or clear the type filter.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
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
