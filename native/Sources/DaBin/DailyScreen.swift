import SwiftUI

@MainActor
struct DailyScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState

    private var cards: [CaptureFeedCard] {
        HourlyCaptureFeed.cards(from: state.receiptCaptures(for: state.selectedDay), filter: state.filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            if cards.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    BoredRobotView(isActive: state.isBoardVisible && !reduceMotion).frame(width: 56, height: 68)
                    Text(state.receiptCaptures(for: state.selectedDay).isEmpty ? "Catch something worth keeping" : "No \(state.filter.title.lowercased()) on this day")
                        .font(.system(size: 14, weight: .medium))
                    if state.receiptCaptures(for: state.selectedDay).isEmpty {
                        Text("Drop a file here, paste from the clipboard, or write a note.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("Paste clipboard") { state.pasteClipboard() }
                            Button("New note") { state.openNewNote() }
                        }.font(.system(size: 12)).padding(.top, 10)
                    } else {
                        Button("Show all captures") { state.filter = .all }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cards) { card in
                            switch card {
                            case .capture(let captureCard):
                                if captureCard.isImportedBatch {
                                    GroupedCaptureCard(state: state, group: captureCard)
                                        .workspaceZoomItem("capture:" + captureCard.primary.id.uuidString)
                                } else {
                                    CaptureRow(state: state, capture: captureCard.primary,
                                               featured: false)
                                }
                            case .automaticHour(let group):
                                HourlyCaptureCard(state: state, group: group)
                                    .workspaceZoomItem("capture:" + group.captures[0].id.uuidString)
                            }
                        }
                    }.scrollTargetLayout().padding(.horizontal, zoom.value(16))
                }.scrollPosition(id: $state.dailyScrollID, anchor: .top)
                    .background {
                        WorkspaceScrollHistory(anchor: state.workspaceViewport,
                            contextID: "daily-" + CaptureCalendar.dayString(state.selectedDay),
                            onAnchor: { state.workspaceViewport = $0 })
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
            }
        }
    }
}
