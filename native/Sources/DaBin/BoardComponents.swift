import AppKit
import SwiftUI

enum Palette {
    static let background = adaptive(light: 0xFDFCFE, dark: 0x1D1C21)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x252328)
    static let foreground = adaptive(light: 0x2B2731, dark: 0xEBEAED)
    static let muted = adaptive(light: 0x615A69, dark: 0xA9A6AE)
    static let line = adaptive(light: 0xE3E0E6, dark: 0x3C3940)
    static let soft = adaptive(light: 0xF3F1F5, dark: 0x2D2A30)
    static let task = adaptive(light: 0xB43D45, dark: 0xF28D99)
    static let completed = adaptive(light: 0x287447, dark: 0x7CCD99)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

@MainActor
struct FilterBar: View {
    @Environment(\.daBinAccent) private var accent
    @Binding var selection: CaptureFilter
    var body: some View {
        HStack(spacing: 12) {
            ForEach(CaptureFilter.allCases) { filter in
                Button { selection = filter } label: {
                    Image(systemName: symbol(for: filter))
                        .font(.system(size: 15, weight: selection == filter ? .semibold : .regular))
                        .accessibilityHidden(true)
                        .foregroundStyle(accent.opacity(selection == filter ? 1 : 0.8))
                        .frame(width: 40, height: 34)
                        .background(selection == filter ? accent.opacity(0.13) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).help(filter.title).accessibilityLabel(filter.title)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                    .accessibilityRemoveTraits(selection == filter ? [] : .isSelected)
            }
        }.padding(.top, 2).padding(.bottom, 6).frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }

    private func symbol(for filter: CaptureFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2"
        case .links: return "link"
        case .files: return "doc.text"
        case .media: return "photo.on.rectangle"
        case .tasks: return "checkmark"
        }
    }
}

@MainActor
struct SmallIcon: View {
    let symbol: String
    let label: String
    var tint: Color = Palette.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(tint).help(label).accessibilityLabel(label)
    }
}

@MainActor
struct EmptyMessage: View {
    @Environment(\.daBinAccent) private var accent
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 8)
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(accent).padding(.bottom, 3)
            Text(title).font(.system(size: 17, weight: .medium))
            Text(message).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 265).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
        }.padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
