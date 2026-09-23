import AppKit
import SwiftUI

/// Origin at capture time, kept separate from DaBin's managed copy of the original.
@MainActor
struct CaptureSourceView: View {
    @ObservedObject var capture: Capture

    private var location: String? {
        capture.sourceFilePath ?? capture.sourceURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("Source location", systemImage: capture.sourceFilePath == nil ? "link" : "folder")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                if let location {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(location, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Copy source location")
                    .accessibilityLabel("Copy source location")
                }
            }
            if let location {
                Text(location)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Source location: \(location)")
            } else {
                Text("Source location wasn’t provided with this capture.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
