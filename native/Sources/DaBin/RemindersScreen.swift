import SwiftUI

@MainActor
struct RemindersScreen: View {
    @ObservedObject var state: AppState
    private var items: [Capture] {
        state.store.captures.filter { $0.reminderAt != nil && !($0.isTask && $0.isCompleted) }.sorted { $0.reminderAt! < $1.reminderAt! }
    }
    var body: some View {
        if items.isEmpty {
            EmptyMessage(symbol: "bell", title: "A nudge for later", message: "Add a reminder to any capture. It will always stay on the day you saved it.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    reminderSection("Upcoming", items: items.filter { $0.reminderAt! > Date() })
                    reminderSection("Past", items: Array(items.filter { $0.reminderAt! <= Date() }.reversed()))
                }.padding(.horizontal, 16)
            }
        }
    }
    @ViewBuilder
    private func reminderSection(_ title: String, items: [Capture]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted).padding(.top, 9).accessibilityAddTraits(.isHeader)
            ForEach(items) { capture in
                CaptureRow(state: state, capture: capture, featured: false)
            }
        }
    }
}
