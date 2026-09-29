import SwiftUI

@MainActor
struct LibraryScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent

    private var items: [Capture] { state.libraryCaptures }
    private var pinned: [Capture] { items.filter(\.isPinned) }
    private var nextActions: [Capture] {
        items.filter { !$0.isPinned && !($0.isTask && $0.isCompleted) && ($0.isTask || $0.reminderAt != nil) }
    }
    private var recent: [Capture] {
        let surfaced = Set((pinned + nextActions).map(\.id))
        return items.filter { !surfaced.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Library").font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    CaptureFilterMenu(selection: $state.filter)
                }
                HStack(spacing: 9) {
                    Menu {
                        Button("All projects") { state.libraryProject = nil }
                        ForEach(state.projectNames, id: \.self) { project in
                            Button(project) { state.libraryProject = project }
                        }
                    } label: {
                        Label(state.libraryProject ?? "All projects", systemImage: "folder")
                            .lineLimit(1).font(.system(size: 12))
                    }.menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Project filter, \(state.libraryProject ?? "all projects")")
                    Toggle("Pinned", isOn: $state.libraryPinnedOnly).toggleStyle(.checkbox).font(.system(size: 12))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if items.isEmpty {
                EmptyMessage(symbol: "square.stack", title: "Your saved things belong here", message: state.libraryPinnedOnly ? "Pin a capture from its More menu, or turn off the Pinned filter." : "Capture a note, link or file. Projects are optional.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if state.libraryProject != nil && !state.libraryPinnedOnly {
                            librarySection("Pinned", items: pinned)
                            librarySection("Next actions", items: nextActions)
                            librarySection("Recent captures", items: recent)
                        } else {
                            ForEach(items) { capture in
                                CaptureRow(state: state, capture: capture, featured: false, showsDate: true)
                            }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }
    }

    @ViewBuilder private func librarySection(_ title: String, items: [Capture]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                .padding(.top, 8).accessibilityAddTraits(.isHeader)
            ForEach(items) { capture in CaptureRow(state: state, capture: capture, featured: false, showsDate: true) }
        }
    }
}
