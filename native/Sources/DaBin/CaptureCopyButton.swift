import SwiftUI

@MainActor
struct CaptureCopyButton: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState
    let captures: [Capture]
    var compact = false

    @State private var copied = false
    @State private var feedbackGeneration = 0

    static func captureDescription(for captures: [Capture]) -> String {
        if captures.count == 1 {
            let title = captures[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "capture" : title
        }
        return "\(captures.count) captured items"
    }

    static func accessibilityIdentifier(for captures: [Capture]) -> String {
        if captures.count == 1 {
            return "capture-copy-\(captures[0].id.uuidString)"
        }
        return "capture-copy-batch-\(captures[0].id.uuidString)"
    }

    static func accessibilityLabel(for captures: [Capture], copied: Bool) -> String {
        let description = captureDescription(for: captures)
        return copied ? "Copied \(description)" : "Copy \(description) to clipboard"
    }

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .frame(width: compact ? 24 : 28, height: compact ? 22 : 26)
                .background(accent.opacity(copied ? 0.2 : 0.11),
                            in: RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .help(copied ? "Copied" : "Copy to clipboard")
        .accessibilityLabel(Self.accessibilityLabel(for: captures, copied: copied))
        .accessibilityHint("Copies the captured content from DaBin's local archive")
        .accessibilityValue(copied ? "Copied" : "Ready")
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: captures))
    }

    private func copy() {
        guard state.copyCapturesToClipboard(captures) else { return }
        feedbackGeneration &+= 1
        let generation = feedbackGeneration
        if reduceMotion {
            copied = true
        } else {
            withAnimation(.easeOut(duration: 0.14)) { copied = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.25))
            guard generation == feedbackGeneration else { return }
            if reduceMotion {
                copied = false
            } else {
                withAnimation(.easeIn(duration: 0.14)) { copied = false }
            }
        }
    }
}
