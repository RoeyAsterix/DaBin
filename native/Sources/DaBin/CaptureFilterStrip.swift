import SwiftUI

extension CaptureFilter {
    var buddySymbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .links: return "link"
        case .files: return "doc.text"
        case .media: return "photo.on.rectangle.angled"
        case .tasks: return "checkmark.circle"
        }
    }
}

@MainActor
struct CaptureFilterStrip: View {
    @Binding var selection: CaptureFilter
    var body: some View {
        HStack(spacing: 10) {
            ForEach(CaptureFilter.allCases) { filter in
                BuddyIconButton(symbol: filter.buddySymbol,
                    title: filter.title,
                    isActive: selection == filter, tooltipID: "filter-tooltip-\(filter.rawValue)") { selection = filter }
                    .accessibilityIdentifier("capture-filter-\(filter.rawValue)")
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
            }
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain).accessibilityLabel("Capture filters")
            .daBinTutorialAnchor(.captureFilters)
    }
}
