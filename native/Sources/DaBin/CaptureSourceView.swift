import AppKit
import SwiftUI

/// Presentation derives only from recorded provenance, never from the app that
/// happens to be in front while an old capture is being viewed.
enum CaptureSourcePresentation {
    static func websiteHost(_ location: String?) -> String? {
        guard let location, let url = URL(string: location),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func applicationName(name: String?, identifier: String?) -> String? {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        guard let identifier, !identifier.isEmpty else { return nil }
        return identifier.split(separator: ".").last.map(String.init) ?? identifier
    }

    /// Legacy link receipts also put the link target in sourceURL. That is
    /// useful location data but does not prove which product it came from.
    static func originWebsite(for capture: Capture) -> String? {
        guard capture.sourceURL != capture.originalURL else { return nil }
        return websiteHost(capture.sourceURL)
    }

    static func origin(for capture: Capture) -> CaptureApplicationIdentity {
        if let application = CaptureApplicationIdentity.resolve(name: capture.sourceApplicationName,
                                                                 identifier: capture.sourceApplicationBundleIdentifier) { return application }
        if let website = originWebsite(for: capture) { return .init(name: website, bundleIdentifier: nil) }
        return .init(name: "Unknown source", bundleIdentifier: nil)
    }
}

/// App icons are read from installed bundles and retained in memory only.
/// No site, favicon service, or network request is used to display provenance.
@MainActor
final class CaptureApplicationIconCache {
    static let shared = CaptureApplicationIconCache()
    private let images = NSCache<NSString, NSImage>()
    private var unavailable: Set<String> = []

    private init() { images.countLimit = 80 }

    func icon(bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        if let cached = images.object(forKey: bundleIdentifier as NSString) { return cached }
        guard !unavailable.contains(bundleIdentifier) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            // A small negative cache prevents repeated Launch Services queries
            // when scrolling old captures from apps no longer installed.
            if unavailable.count >= 80 { unavailable.removeAll(keepingCapacity: true) }
            unavailable.insert(bundleIdentifier)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: bundleIdentifier as NSString)
        return image
    }
}

/// Compact source glyph for a card's metadata. The accessible source name and
/// hover label remain available even where the visual name would not fit.
@MainActor
struct CaptureSourceIcon: View {
    @ObservedObject var capture: Capture
    var size: CGFloat = 16
    @Environment(\.daBinAccent) private var accent

    private var application: String? {
        CaptureSourcePresentation.applicationName(name: capture.sourceApplicationName,
                                                   identifier: capture.sourceApplicationBundleIdentifier)
    }
    private var website: String? { CaptureSourcePresentation.originWebsite(for: capture) }
    private var title: String {
        if let application { return "Captured from \(application)" }
        if let website { return "Captured from \(website)" }
        if capture.sourceFilePath != nil { return "Captured from a file" }
        return "Capture source unavailable"
    }

    var body: some View {
        Group {
            if let image = CaptureApplicationIconCache.shared.icon(bundleIdentifier: capture.sourceApplicationBundleIdentifier) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: application != nil ? "app" : website != nil ? "globe"
                      : capture.sourceFilePath != nil ? "folder" : "app")
                    .font(.system(size: max(10, size * 0.82), weight: .medium))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .buddyHelp(title)
    }
}

/// Shows recorded origin separately from DaBin's verified local destination.
/// It does not claim to detect pastes made into other applications.
@MainActor
struct CaptureSourceView: View {
    @ObservedObject var capture: Capture
    @Environment(\.daBinAccent) private var accent
    @State private var showLocation = false
    @State private var copied = false
    @StateObject private var copyFailure = TransientMessagePresentation<String>()
    @State private var copyGeneration = 0
    @State private var copyTask: Task<Void, Never>?

    private var location: String? { capture.sourceFilePath ?? capture.sourceURL }
    private var locationName: String {
        capture.sourceFilePath == nil && capture.sourceURL == capture.originalURL ? "Captured link" : "Source location"
    }
    private var application: String? {
        CaptureSourcePresentation.applicationName(name: capture.sourceApplicationName,
                                                   identifier: capture.sourceApplicationBundleIdentifier)
    }
    private var website: String? { CaptureSourcePresentation.originWebsite(for: capture) }
    private var sourceName: String { application ?? website ?? (capture.sourceFilePath != nil ? "File" : "Unknown source") }

    private var isCreatedTask: Bool {
        capture.kind == .task && capture.sourceApplicationName == nil
            && capture.sourceApplicationBundleIdentifier == nil
            && capture.sourceFilePath == nil && capture.sourceURL == nil
    }

    @ViewBuilder
    var body: some View {
        if isCreatedTask {
            Label("Created in DaBin", systemImage: "tray.and.arrow.down")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .accessibilityLabel("Task created locally in DaBin")
        } else {
            provenance
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { badges }
                VStack(alignment: .leading, spacing: 9) { badges }
            }
            if let website, application != nil {
                Label(website, systemImage: "globe")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .lineLimit(1).textSelection(.enabled)
                    .accessibilityLabel("Source website: \(website)")
            }
            if let location {
                HStack(spacing: 5) {
                    Button { showLocation.toggle() } label: {
                        Label(locationName, systemImage: showLocation ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(accent)
                    .accessibilityLabel("\(showLocation ? "Hide" : "Show") \(locationName.lowercased())")
                    .accessibilityValue(showLocation ? "Expanded" : "Collapsed")
                    Spacer(minLength: 0)
                    BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc",
                                    title: copied ? "\(locationName) copied" : "Copy \(locationName.lowercased())") {
                        copyLocation(location)
                    }
                }
                if showLocation {
                    Text(location).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(locationName): \(location)")
                }
            }
            if let message = copyFailure.visibleMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.task)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Palette.soft.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture origin and saved location")
        .onChange(of: capture.id) { _, _ in clearCopyFeedback(); showLocation = false }
        .onChange(of: location) { _, _ in clearCopyFeedback() }
        .onDisappear { clearCopyFeedback() }
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 7) {
            CaptureSourceIcon(capture: capture, size: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("From").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text(sourceName).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(application == nil && website == nil && capture.sourceFilePath == nil
                            ? "Capture source was not provided" : "Captured from \(sourceName)")
        Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.muted).accessibilityHidden(true)
        HStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(accent)
                .frame(width: 26, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Saved in").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text("DaBin").font(.system(size: 12, weight: .medium))
            }
        }.accessibilityElement(children: .combine)
            .accessibilityLabel("Saved locally in DaBin")
    }

    private func copyLocation(_ location: String) {
        clearCopyFeedback()
        let generation = copyGeneration
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(location, forType: .string) else {
            let message = "\(locationName) could not be copied."
            copyFailure.present(message)
            AccessibilityAnnouncement.post(message)
            return
        }
        copied = true
        AccessibilityAnnouncement.post("\(locationName) copied")
        let captureID = capture.id
        copyTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1.4)) } catch { return }
            guard !Task.isCancelled, copyGeneration == generation, capture.id == captureID,
                  self.location == location else { return }
            copied = false
            copyTask = nil
        }
    }

    private func clearCopyFeedback() {
        copyGeneration &+= 1
        copyTask?.cancel()
        copyTask = nil
        copied = false
        copyFailure.dismiss()
    }
}
