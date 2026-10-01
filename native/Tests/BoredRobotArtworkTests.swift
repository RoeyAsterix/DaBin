import AppKit
import QuartzCore
import SwiftUI

/// Uses synthetic offscreen hosts only. The empty state must borrow the same
/// native vector character as the island and stop it when SwiftUI removes it.
@main
struct BoredRobotArtworkTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool,
                                          _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinBoredRobotArtworkTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func characters(in view: NSView) -> [RobotCharacterView] {
        (view as? RobotCharacterView).map { [$0] } ?? view.subviews.flatMap { characters(in: $0) }
    }

    @MainActor private static func layers(in layer: CALayer?) -> [CALayer] {
        guard let layer else { return [] }
        return [layer] + (layer.sublayers ?? []).flatMap { layers(in: $0) }
    }

    @MainActor private static func pixels(in view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        view.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 256, pixelsHigh: 312,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bytes = bitmap.bitmapData else {
            throw NSError(domain: "DaBinBoredRobotArtworkTests", code: 2)
        }
        bitmap.size = view.bounds.size
        let count = bitmap.bytesPerRow * bitmap.pixelsHigh
        bytes.initialize(repeating: 0, count: count)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return Data(bytes: bytes, count: count)
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for dark in [false, true] {
            let hosting = NSHostingView(rootView: AnyView(
                BoredRobotView(isActive: false)
                    .preferredColorScheme(dark ? .dark : .light)
                    .frame(width: 128, height: 156)))
            hosting.frame = CGRect(x: 0, y: 0, width: 128, height: 156)
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 128, height: 156),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = hosting
            defer {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(200))
            hosting.layoutSubtreeIfNeeded()
            let nativeCharacters = characters(in: hosting)
            try expect(nativeCharacters.count == 1,
                       "The empty state hosts exactly one canonical native island character")
            guard let character = nativeCharacters.first else {
                throw NSError(domain: "DaBinBoredRobotArtworkTests", code: 3)
            }
            try expect(character.mood == .idle && character.bounds.width > 0 && character.bounds.height > 0,
                       "The native character is revealed at usable vector bounds")
            try expect(!character.hasActiveAmbientMotion
                       && layers(in: character.layer).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                       "The native pose adds no independent timer or animation to the bounded SwiftUI motion")
            let first = try pixels(in: hosting)
            try expect(first.filter { $0 != 0 }.count > 1_000,
                       "The canonical empty-state artwork is actually rendered")
            try await Task.sleep(for: .milliseconds(200))
            let second = try pixels(in: hosting)
            try expect(first == second, "An inactive empty state remains pixel-identical")
            hosting.rootView = AnyView(EmptyView())
            try await Task.sleep(for: .milliseconds(200))
            try expect(characters(in: hosting).isEmpty && character.mood == .hidden
                       && !character.hasActiveAmbientMotion,
                       "Removing the empty state dismantles and stops the canonical character")
        }
        print("PASS: \(checks) canonical empty-state robot hosting, static rendering and cleanup checks")
    }
}
