import AppKit
import SwiftUI

/// Original installed application artwork only; custom products use a neutral
/// glyph and their supplied name. There is no remote favicon lookup.
@MainActor
struct CaptureApplicationMark: View {
    let application: CaptureApplicationIdentity
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = CaptureApplicationIconCache.shared.icon(bundleIdentifier: application.bundleIdentifier) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app")
                    .font(.system(size: size * 0.59, weight: .regular))
                    .foregroundStyle(Palette.muted)
                    .frame(width: size, height: size)
                    .background(Palette.soft.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 0.5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

@MainActor
struct CaptureTrailView: View {
    // The trail observes its own capture; AppState is only an action target.
    let state: AppState
    @ObservedObject var capture: Capture
    var compact = true
    @State private var showingHistory = false
    @StateObject private var errorPresentation = TransientMessagePresentation<String>()
    @StateObject private var confirmationPresentation = TransientMessagePresentation<String>()

    private var source: CaptureApplicationIdentity { CaptureSourcePresentation.origin(for: capture) }
    private var destinations: [CapturePasteDestination] { CapturePasteHistory.destinations(capture.pasteHistory) }
    private var history: [CapturePasteEvent] { CapturePasteHistory.newestFirst(capture.pasteHistory) }
    private var summary: String {
        let usage = destinations.isEmpty ? "No paste destinations recorded."
            : "Destinations recorded: " + destinations.map { "\($0.application.name) (\($0.count))" }.joined(separator: ", ") + "."
        return "From \(source.name). \(usage) Open content trail."
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                clearFeedback()
                showingHistory = true
            } label: {
                ViewThatFits(in: .horizontal) {
                    trailPath(limit: CapturePasteHistory.compactLimit)
                    trailPath(limit: 1)
                    CaptureApplicationMark(application: source, size: compact ? 24 : 28)
                }
                .padding(.horizontal, 3).frame(minHeight: 34)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(TrailButtonStyle())
            .buddyHelp(summary)
            .accessibilityLabel(summary)
            .accessibilityIdentifier("capture-trail-\(capture.id.uuidString)")
            .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                historyPopover
                    .hoverTooltips()
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: capture.id) { _, _ in clearFeedback(); showingHistory = false }
        .onChange(of: showingHistory) { _, shown in if !shown { clearFeedback() } }
        .onDisappear { clearFeedback() }
    }

    private func trailPath(limit: Int) -> some View {
        HStack(spacing: 5) {
            CaptureApplicationMark(application: source, size: compact ? 24 : 28)
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            if destinations.isEmpty {
                Text("No pastes").font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                ForEach(Array(destinations.prefix(limit))) { destination in
                    CaptureApplicationMark(application: destination.application, size: compact ? 24 : 28)
                }
                if destinations.count > limit {
                    Text("+\(destinations.count - limit)")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.muted)
                }
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content trail").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { showingHistory = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("Close content trail").buddyHelp("Close content trail")
            }
            HStack(spacing: 9) {
                CaptureApplicationMark(application: source, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name).font(.system(size: 13, weight: .semibold))
                    Text("Captured \(capture.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.soft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Pasted to").font(.system(size: 12, weight: .semibold))
                Text("\(history.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.muted)
                Spacer()
            }
            if history.isEmpty {
                Text("No paste destinations recorded.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history) { event in historyRow(event) }
                    }
                }.frame(height: min(CGFloat(history.count) * 57, 224))
            }
            if let error = errorPresentation.visibleMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.task)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("capture-trail-error")
            }
            if let confirmation = confirmationPresentation.visibleMessage {
                Label(confirmation, systemImage: "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("capture-trail-success")
            }
        }
        .padding(16).frame(width: 320)
        .onExitCommand { showingHistory = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Content trail")
    }

    private func historyRow(_ event: CapturePasteEvent) -> some View {
        HStack(spacing: 8) {
            CaptureApplicationMark(application: CaptureApplicationIdentity.resolve(name: event.applicationName,
                identifier: event.applicationBundleIdentifier) ?? .init(name: event.applicationName, bundleIdentifier: nil), size: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.applicationName).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text("\(event.evidence.title) · \(event.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            Spacer(minLength: 2)
            if event.evidence == .manual {
                Button { remove(event) } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).frame(width: 26, height: 26)
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .accessibilityLabel("Remove recorded paste to \(event.applicationName)")
                    .buddyHelp("Remove this manually recorded paste")
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
    }

    private func remove(_ event: CapturePasteEvent) {
        do {
            try state.store.removePasteDestination(event.id, from: capture)
            errorPresentation.dismiss()
            confirmationPresentation.present("Paste record removed.")
            AccessibilityAnnouncement.post("Paste record removed.")
        } catch {
            confirmationPresentation.dismiss()
            let message = "Couldn’t save this paste record. \(error.localizedDescription)"
            errorPresentation.present(message)
            AccessibilityAnnouncement.post(message)
        }
    }

    private func clearFeedback() {
        errorPresentation.dismiss()
        confirmationPresentation.dismiss()
    }
}

private struct TrailButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.soft.opacity(configuration.isPressed ? 0.8 : hovering ? 0.5 : 0), in: RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
    }
}
