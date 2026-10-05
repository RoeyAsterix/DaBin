import SwiftUI

/// Daily stays a chronological, row-major feed as the window grows. A bounded
/// card width makes room for neighbours without stretching captions across the
/// display; zoom gently increases that width while native text stays sharp.
struct DailyGridLayout {
    let columnCount: Int
    let columnWidth: CGFloat
    let spacing: CGFloat
    let horizontalPadding: CGFloat

    init(width: CGFloat, zoom: WorkspaceZoomLayout, retainedColumns: Int? = nil) {
        let width = width.isFinite ? max(0, width) : 0
        horizontalPadding = min(24, max(12, zoom.value(16)))
        spacing = min(18, max(12, zoom.value(12)))
        let available = max(0, width - 2 * horizontalPadding)
        let minimum = max(280, 300 * sqrt(zoom.factor))
        columnCount = min(5, max(1, retainedColumns ?? Int((available + spacing) / (minimum + spacing))))
        columnWidth = max(0, (available - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount))
    }

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing, alignment: .top), count: columnCount)
    }
}

@MainActor
struct DailyScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState
    @State private var restingColumnCount: Int?

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
                GeometryReader { geometry in
                    let layout = DailyGridLayout(width: geometry.size.width, zoom: zoom,
                        retainedColumns: zoom.isInteracting ? restingColumnCount : nil)
                    ScrollView {
                        LazyVGrid(columns: layout.columns, alignment: .leading,
                                  spacing: max(0, layout.spacing - 12)) {
                            ForEach(cards) { card in
                                feedCard(card)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("daily-card-" + (card.captures.first?.id.uuidString ?? ""))
                                    .id(card.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.bottom, 8)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("daily-grid")
                    }
                    .scrollPosition(id: $state.dailyScrollID, anchor: .top)
                    // Reflow once when a pinch settles, rather than moving
                    // cards between columns on every magnification event.
                    .onChange(of: layout.columnCount, initial: true) { _, count in
                        if !zoom.isInteracting { restingColumnCount = count }
                    }
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

    @ViewBuilder private func feedCard(_ card: CaptureFeedCard) -> some View {
        switch card {
        case .capture(let captureCard):
            if captureCard.isImportedBatch {
                GroupedCaptureCard(state: state, group: captureCard)
                    .workspaceZoomItem("capture:" + captureCard.primary.id.uuidString)
            } else {
                CaptureRow(state: state, capture: captureCard.primary, featured: false)
            }
        case .automaticHour(let group):
            HourlyCaptureCard(state: state, group: group)
                .workspaceZoomItem("capture:" + (group.captures.first?.id.uuidString ?? ""))
        }
    }

}
