import AppKit
import SwiftUI

private final class PrivacyRenderWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main @MainActor
private final class PrivacyRenderTests: NSObject, NSApplicationDelegate {
    private var result: Int32 = 0
    private var checks = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = PrivacyRenderTests()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "PrivacyRenderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        print("PASS: \(message)")
    }

    private func run() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let document = PrivacyInformation.document()
        let sections = PrivacyInformation.sections(in: document)
        try expect(Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md") != nil, "Real policy resource is present in the isolated app bundle")
        try expect(sections.count == 6, "Full six-section policy is loaded, not fallback text")
        try expect(document.contains("Choose Remove") && document.contains("Minimize only collapses"), "Policy includes current removal and minimize behavior")
        try expect(PrivacyInformation.configuredURL(for: PrivacyInformation.policyURLKey) == nil &&
                   PrivacyInformation.configuredURL(for: PrivacyInformation.supportURLKey) == nil, "Unconfigured public policy/support links are absent")
        var renders: [[String: Any]] = []
        for mode in ["light", "dark"] {
            let dark = mode == "dark"
            let size = NSSize(width: 350, height: 440)
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let hosting = NSHostingView(rootView: AnyView(EmptyView()))
            // AppKit normally supplies this appearance while evaluating SwiftUI.
            // This isolated, hidden host is constructed manually, so provide the
            // matching context when dynamic NSColors enter the view hierarchy.
            appearance.performAsCurrentDrawingAppearance {
                hosting.rootView = AnyView(PrivacyPolicySheet(dataFolder: output.appendingPathComponent("fictional-data-folder"))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.daBinAccent, ThemeSettings.accentColor(for: ThemeSettings.defaultHex))
                    .background(Color(nsColor: .windowBackgroundColor)))
            }
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.wantsLayer = true
            hosting.appearance = appearance
            let window = PrivacyRenderWindow(contentRect: NSRect(x: -20000, y: -20000, width: 350, height: 440),
                                             styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView = hosting
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(220))
            hosting.layoutSubtreeIfNeeded()
            try expect(!window.isKeyWindow && !window.isMainWindow, "\(mode): render window never takes keyboard focus")
            guard let scroll = scrollView(in: hosting), let content = scroll.documentView else {
                throw NSError(domain: "PrivacyRenderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Privacy policy has no scrollable content"])
            }
            try expect(content.bounds.height > scroll.contentView.bounds.height, "\(mode): full policy has a scrollable reading area")
            let top = output.appendingPathComponent("privacy-policy-\(mode)-top.png")
            try snapshot(hosting, to: top)
            let maxOffset = max(0, content.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: content.isFlipped ? maxOffset : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(160))
            hosting.layoutSubtreeIfNeeded()
            let visible = scroll.documentVisibleRect
            try expect(content.isFlipped ? abs(visible.maxY - content.bounds.maxY) < 2 : visible.minY < 2,
                       "\(mode): bottom of the complete policy is reachable")
            let bottom = output.appendingPathComponent("privacy-policy-\(mode)-bottom.png")
            try snapshot(hosting, to: bottom)
            renders.append(["appearance": mode, "top": top.lastPathComponent, "bottom": bottom.lastPathComponent,
                            "policySectionCount": sections.count, "documentHeight": content.bounds.height,
                            "viewportHeight": scroll.contentView.bounds.height, "scrollBottom": visible.maxY,
                            "windowKey": window.isKeyWindow, "windowMain": window.isMainWindow])
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostBefore, "Rendering preserved the user's foreground application")
        try JSONSerialization.data(withJSONObject: ["renders": renders, "checks": checks,
            "fixturePrivacy": "Production policy view and locally bundled policy only. No personal archive, clipboard, network, notification or input actions.",
            "visualReviewRequired": "Inspect all four PNGs for readable headings/body, a visible Done control and the bottom Show DaBin data folder button."],
            options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("privacy-renders.json"))
        print("PASS: \(checks) privacy-render checks; 4 native offscreen PNGs")
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let result = view as? NSScrollView { return result }
        for child in view.subviews { if let result = scrollView(in: child) { return result } }
        return nil
    }

    private func snapshot(_ view: NSView, to url: URL) throws {
        view.displayIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 350, pixelsHigh: 440,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 350, height: 440)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PrivacyRenderTests", code: 3)
        }
        try png.write(to: url)
    }
}
