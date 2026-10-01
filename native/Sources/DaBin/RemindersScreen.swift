import SwiftUI

@MainActor
struct RemindersScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent
    private var items: [Capture] { state.followUpCaptures }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Follow-ups").font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("New task") { state.openNewTask() }.font(.system(size: 12))
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if items.isEmpty {
                EmptyMessage(symbol: "checkmark.circle", title: "All caught up", message: "Turn a capture into a task or add a reminder. Its original stays in your archive.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        followUpSection("Due now", items: items.filter { ($0.reminderAt ?? .distantFuture) <= Date() })
                        followUpSection("Later", items: items.filter { ($0.reminderAt ?? .distantPast) > Date() })
                        followUpSection("Anytime", items: items.filter { $0.reminderAt == nil })
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder private func followUpSection(_ title: String, items: [Capture]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                .padding(.top, 8).accessibilityAddTraits(.isHeader)
            ForEach(items) { capture in
                VStack(alignment: .leading, spacing: 0) {
                    CaptureRow(state: state, capture: capture, featured: false, embeddedInCard: true)
                    HStack(spacing: 16) {
                        Button { state.completeFollowUp(capture) } label: { Label("Complete", systemImage: "checkmark.circle") }
                        Button { state.snoozeFollowUp(capture) } label: { Label("Snooze", systemImage: "clock.arrow.circlepath") }
                            .buddyHelp("Remind me tomorrow")
                        Spacer(minLength: 0)
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent).padding(.bottom, 10)
                }.padding(.horizontal, 11).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
            }
        }
    }
}
