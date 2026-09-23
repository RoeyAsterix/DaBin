import SwiftUI

@MainActor
struct DailyScreen: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState

    private var cards: [CaptureCardGroup] { CaptureCardGroup.cards(from: state.dailyCaptures) }
    private var featuredID: UUID? {
        cards.first(where: { !$0.isImportedBatch && !$0.primary.isMinimized
            && $0.primary.thumbnailRelativePath != nil })?.primary.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    HStack(spacing: 1) {
                        SmallIcon(symbol: "chevron.left", label: "Previous day") { state.moveDay(-1) }
                        SmallIcon(symbol: "chevron.right", label: "Next day") { state.moveDay(1) }
                            .disabled(Calendar.current.isDateInToday(state.selectedDay))
                    }.frame(width: 68, alignment: .leading)
                    Spacer(minLength: 0)
                    Button("Today") { state.showCurrentWeek() }
                        .font(.system(size: 12, weight: .medium)).buttonStyle(.plain).foregroundStyle(accent)
                        .padding(.vertical, 7).frame(width: 68, alignment: .trailing)
                        .help("Show This Week")
                }
                Button { state.openWeekly() } label: {
                    Text(state.selectedDay, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated))
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                        .padding(.horizontal, 17).padding(.vertical, 7)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "rectangle.split.3x1").font(.system(size: 9, weight: .semibold))
                        }
                }.buttonStyle(.plain).help("Open the last seven days")
                    .accessibilityLabel("Open weekly view ending \(state.selectedDay.formatted(date: .complete, time: .omitted))")
            }.padding(.horizontal, 13).padding(.bottom, 5)
            FilterBar(selection: $state.filter)
            if state.dailyCaptures.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    BoredRobotView(isActive: state.isBoardVisible).frame(width: 56, height: 68)
                    Text(state.allCapturesForDay.isEmpty ? "Nothing to digest yet" : "No \(state.filter.title.lowercased()) on this day")
                        .font(.system(size: 14, weight: .medium))
                    if state.allCapturesForDay.isEmpty {
                        Text("Reach a corner. Give your robot something to do.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
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
                            if card.isImportedBatch {
                                GroupedCaptureCard(state: state, group: card)
                                    .id(card.primary.id)
                            } else {
                                CaptureRow(state: state, capture: card.primary,
                                           featured: card.primary.id == featuredID,
                                           taskAtTop: state.isTaskAtTop(card.primary))
                                    .id(card.primary.id)
                            }
                        }
                    }.scrollTargetLayout().padding(.horizontal, 16)
                }.scrollPosition(id: $state.dailyScrollID, anchor: .top)
            }
            HStack {
                if cards.count == state.dailyCaptures.count {
                    Text("\(state.dailyCaptures.count) \(state.dailyCaptures.count == 1 ? "capture" : "captures")")
                } else {
                    Text("\(state.dailyCaptures.count) items · \(cards.count) cards")
                }
                Spacer()
                Text("DaBin").fontWeight(.medium)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 17).padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }
}
