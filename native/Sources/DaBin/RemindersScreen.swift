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
                Button { state.openNewTask() } label: {
                    Text("New task").frame(minHeight: 32).contentShape(Rectangle())
                }.font(.system(size: 12))
            }.padding(.horizontal, 12).padding(.vertical, 8)
            if items.isEmpty {
                EmptyMessage(symbol: "checkmark.circle", title: "All caught up", message: "Turn a capture into a task or add a reminder. Its original stays in your archive.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        followUpSection("Due now", items: items.filter { ($0.reminderAt ?? .distantFuture) <= Date() })
                        followUpSection("Later", items: items.filter { ($0.reminderAt ?? .distantPast) > Date() })
                        followUpSection("Anytime", items: items.filter { $0.reminderAt == nil })
                    }.padding(.horizontal, 12).padding(.bottom, 12)
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
                    BuddyActionFlow(spacing: 8) {
                        Button { state.completeFollowUp(capture) } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                                .frame(minHeight: 32).contentShape(Rectangle())
                        }
                        Button { state.snoozeFollowUp(capture) } label: {
                            Label("Snooze", systemImage: "clock.arrow.circlepath")
                                .frame(minHeight: 32).contentShape(Rectangle())
                        }
                            .buddyHelp("Remind me tomorrow")
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                        .padding(.horizontal, 4)
                }.padding(8)
                    .projectCardBackground(workspace: state.workspace,
                                           projectName: ExplorerQuery.project(of: capture, in: state.store.captures),
                                           cornerRadius: 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
            }
        }
    }
}
