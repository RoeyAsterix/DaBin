import AppKit
import Foundation
import QuartzCore
import SwiftUI

@MainActor private final class VisualRobotReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Production renderer checks in offscreen windows. Fixtures are fictional and
/// isolated: no personal captures, clipboard, notifications, external apps,
/// global pointer events or installed application are accessed.
@main @MainActor
private final class RobotVisualConsistencyTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var windows: [NSWindow] = []
    private static var renderFiles: [String] = []
    private static var appearanceFixtures: [[String: Any]] = []
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = RobotVisualConsistencyTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.runChecks() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            for window in Self.windows {
                window.orderOut(nil); window.contentView = nil; window.close()
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw failure(message) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "RobotVisualConsistencyTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func allLayers(_ layer: CALayer?) -> [CALayer] {
        guard let layer else { return [] }
        return [layer] + (layer.sublayers ?? []).flatMap { allLayers($0) }
    }

    private static func named(_ name: String, in root: CALayer?) throws -> CALayer {
        guard let found = allLayers(root).first(where: { $0.name == name }) else {
            throw failure("Missing production artwork layer: \(name)")
        }
        return found
    }

    private static func host(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000,
            width: view.frame.width, height: view.frame.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        window.orderFront(nil)
        windows.append(window)
        return window
    }

    private static func bitmap(size: CGSize, pixelScale: CGFloat = 2) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * pixelScale), pixelsHigh: Int(size.height * pixelScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Could not allocate an isolated robot render")
        }
        bitmap.size = size
        return bitmap
    }

    private static func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        view.displayIfNeeded()
        let result = try bitmap(size: view.bounds.size)
        view.cacheDisplay(in: view.bounds, to: result)
        return result
    }

    private static func save(_ bitmap: NSBitmapImageRep, named name: String, output: URL,
                             pixelScale: Int = 2) throws {
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw failure("Could not encode the robot render: \(name)")
        }
        let filename = "\(name)@\(pixelScale)x.png"
        try png.write(to: output.appendingPathComponent(filename), options: .atomic)
        renderFiles.append(filename)
    }

    /// Record coordinates, not just bounds: an ellipse and a rectangular LED
    /// must not pass merely because their bounding boxes happen to match.
    private static func normalizedPath(_ path: CGPath, reference: CGRect,
                                       topDown: Bool = true) -> [(Int, [CGFloat])] {
        var records: [(Int, [CGFloat])] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            var coordinates: [CGFloat] = []
            for index in 0..<count {
                let point = element.points[index]
                let y = (point.y - reference.minY) / reference.height
                coordinates += [(point.x - reference.minX) / reference.width, topDown ? y : 1 - y]
            }
            records.append((Int(element.type.rawValue), coordinates))
        }
        return records
    }

    private static func pathsMatch(_ first: CGPath, reference firstBounds: CGRect,
                                   firstTopDown: Bool = true,
                                   _ second: CGPath, reference secondBounds: CGRect,
                                   secondTopDown: Bool = true) -> Bool {
        let lhs = normalizedPath(first, reference: firstBounds, topDown: firstTopDown)
        let rhs = normalizedPath(second, reference: secondBounds, topDown: secondTopDown)
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            a.0 == b.0 && a.1.count == b.1.count
                && zip(a.1, b.1).allSatisfy { abs($0 - $1) < 0.00001 }
        }
    }

    private static func colorsMatch(_ first: CGColor?, _ second: CGColor?) -> Bool {
        guard let first, let second,
              let lhs = NSColor(cgColor: first)?.usingColorSpace(.deviceRGB),
              let rhs = NSColor(cgColor: second)?.usingColorSpace(.deviceRGB) else {
            return first == nil && second == nil
        }
        return abs(lhs.redComponent - rhs.redComponent) < 0.00001
            && abs(lhs.greenComponent - rhs.greenComponent) < 0.00001
            && abs(lhs.blueComponent - rhs.blueComponent) < 0.00001
            && abs(lhs.alphaComponent - rhs.alphaComponent) < 0.00001
    }

    private static func visiblePixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var pixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { pixels += 1 }
            }
        }
        return pixels
    }

    private static func headBitmap(_ head: CALayer, bounds: CGRect,
                                   topDown: Bool) throws -> NSBitmapImageRep {
        let size = CGSize(width: 48, height: 32.64)
        let pixelWidth = Int(size.width * 4)
        let pixelHeight = Int(size.height * 4)
        guard let cg = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Could not create a native head-only graphics context")
        }
        cg.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        // Render both production heads with an identical crop, orientation,
        // point size and pixel density, without resampling a prior screenshot.
        // A raw pixel context avoids NSGraphicsContext's automatic scale from
        // NSBitmapImageRep.size, which would multiply this explicit scale twice.
        cg.translateBy(x: 0, y: CGFloat(pixelHeight))
        cg.scaleBy(x: CGFloat(pixelWidth) / bounds.width,
                   y: -CGFloat(pixelHeight) / bounds.height)
        if topDown { cg.translateBy(x: -bounds.minX, y: -bounds.minY) }
        else {
            cg.translateBy(x: -bounds.minX, y: bounds.maxY)
            cg.scaleBy(x: 1, y: -1)
        }
        head.render(in: cg)
        guard let image = cg.makeImage() else { throw failure("Could not snapshot the actual robot head") }
        let result = NSBitmapImageRep(cgImage: image)
        result.size = size
        return result
    }

    private static func rasterDifference(_ lhs: NSBitmapImageRep,
                                         _ rhs: NSBitmapImageRep) -> CGFloat {
        guard lhs.pixelsWide == rhs.pixelsWide && lhs.pixelsHigh == rhs.pixelsHigh else { return 1 }
        var difference: CGFloat = 0
        for y in 0..<lhs.pixelsHigh {
            for x in 0..<lhs.pixelsWide {
                guard let a = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 1 }
                // Compare premultiplied colors so the RGB of clear pixels is
                // irrelevant, while silhouette alpha is still checked.
                difference += abs(a.redComponent * a.alphaComponent - b.redComponent * b.alphaComponent)
                    + abs(a.greenComponent * a.alphaComponent - b.greenComponent * b.alphaComponent)
                    + abs(a.blueComponent * a.alphaComponent - b.blueComponent * b.alphaComponent)
                    + abs(a.alphaComponent - b.alphaComponent)
            }
        }
        return difference / CGFloat(lhs.pixelsWide * lhs.pixelsHigh * 4)
    }

    private static func runChecks() async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                         isDirectory: true).appendingPathComponent("build/qa/robot-visual-consistency", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await checkProductionHead(output: output)
        try await checkFullApplication(output: output)
        let report: [String: Any] = [
            "schemaVersion": 1,
            "checksPassed": checks,
            "renderedFiles": renderFiles,
            "appearanceFixtures": appearanceFixtures,
            "renderMethod": "Production RobotCharacterView and RobotAppFrameView layers; production BoardView in isolated offscreen windows at 2x",
            "privacy": "Fictional text captures only; no personal archive, clipboard, network, installed application or global pointer events",
            "limitations": "Native renderer and interaction geometry; actual hardware-island placement is independently covered by island suites"
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("robot-visual-consistency-report.json"), options: .atomic)
        print("PASS: \(checks) robot visual consistency, native frame layout, click-through, and Reduce Motion checks. \(output.path)")
    }

    private static func checkProductionHead(output: URL) async throws {
        let robot = RobotCharacterView(frame: CGRect(x: 0, y: 0, width: 64, height: 78),
                                       reduceMotion: { true })
        _ = host(robot)
        robot.send(.reveal(.top))
        try await Task.sleep(for: .milliseconds(40))
        try expect(robot.mood == .idle && !robot.hasActiveAmbientMotion,
                   "The island artwork starts at its quiet, timer-free endpoint")
        try save(render(robot), named: "island-robot-idle", output: output)
        defer { robot.stopMotion() }

        let frame = RobotAppFrameView(contentView: NSView(frame: .zero))
        frame.frame = CGRect(x: 0, y: 0, width: 400, height: 550)
        _ = host(frame)
        frame.setVisible(true)
        frame.layoutSubtreeIfNeeded()
        let islandHead = try named("quietOrbit.head", in: robot.layer)
        let fullHead = try named("quietOrbit.head", in: frame.layer)
        try expect((islandHead.sublayers ?? []).count == 11
            && (fullHead.sublayers ?? []).count == 11,
                   "Both heads contain only the same eleven artwork parts, with no extra lid or handle")
        guard let islandShell = try named("quietOrbit.headShell", in: robot.layer) as? CAGradientLayer,
              let fullShell = try named("quietOrbit.headShell", in: frame.layer) as? CAGradientLayer,
              let islandMask = islandShell.mask as? CAShapeLayer,
              let fullMask = fullShell.mask as? CAShapeLayer,
              let islandPath = islandMask.path, let fullPath = fullMask.path else {
            throw failure("Both actual robots must render their head as a masked metal gradient")
        }
        let islandBounds = islandPath.boundingBoxOfPath
        let fullBounds = fullPath.boundingBoxOfPath
        try expect(abs(islandBounds.width / islandBounds.height - 100 / 68) < 0.00001
            && abs(fullBounds.width / fullBounds.height - 100 / 68) < 0.00001,
                   "Both robot heads preserve the island character's 100:68 silhouette")
        try expect(pathsMatch(islandPath, reference: islandBounds, fullPath,
                              reference: fullBounds, secondTopDown: false),
                   "Full-size and island robots use the identical eight-corner head polygon")
        try expect(normalizedPath(islandPath, reference: islandBounds).count == 9,
                   "The approved island head remains an eight-corner mechanical polygon, not a rounded bin")
        let lhsColors = (islandShell.colors as? [CGColor]) ?? []
        let rhsColors = (fullShell.colors as? [CGColor]) ?? []
        try expect(lhsColors.count == 5 && rhsColors.count == 5,
                   "Both metal heads retain all five approved soft-violet gradient colors")
        for (index, pair) in zip(lhsColors, rhsColors).enumerated() {
            try expect(colorsMatch(pair.0, pair.1), "Metal gradient stop \(index) matches across robot surfaces")
        }
        for name in ["quietOrbit.headOutline", "quietOrbit.visor", "quietOrbit.mouth"] {
            guard let island = try named(name, in: robot.layer) as? CAShapeLayer,
                  let full = try named(name, in: frame.layer) as? CAShapeLayer,
                  let a = island.path, let b = full.path else {
                throw failure("Both production robots require the shared shape: \(name)")
            }
            try expect(pathsMatch(a, reference: islandBounds, b,
                                  reference: fullBounds, secondTopDown: false),
                       "\(name) keeps matching mechanical geometry after coordinate conversion")
            try expect(colorsMatch(island.fillColor, full.fillColor)
                && colorsMatch(island.strokeColor, full.strokeColor),
                       "\(name) uses the exact same approved fill and stroke colors")
            try expect(abs(island.lineWidth / islandBounds.width - full.lineWidth / fullBounds.width) < 0.00001,
                       "\(name) retains proportional outline weight")
        }
        for name in ["quietOrbit.eye.left", "quietOrbit.eye.right"] {
            guard let island = try named(name, in: robot.layer) as? CAShapeLayer,
                  let full = try named(name, in: frame.layer) as? CAShapeLayer,
                  let a = island.path, let b = full.path else {
                throw failure("Both actual heads require a rectangular LED eye: \(name)")
            }
            try expect(colorsMatch(island.fillColor, full.fillColor),
                       "\(name) is the same mint LED color on both surfaces")
            let aBounds = a.boundingBoxOfPath
            let bBounds = b.boundingBoxOfPath
            try expect(abs(aBounds.width / islandBounds.width - 0.13) < 0.00001
                && abs(bBounds.width / fullBounds.width - 0.13) < 0.00001
                && abs(aBounds.height / islandBounds.height - 15 / 68) < 0.00001
                && abs(bBounds.height / fullBounds.height - 15 / 68) < 0.00001,
                       "\(name) keeps the original 13×15 rectangular LED proportions")
            try expect(abs((aBounds.minX - islandBounds.minX) / islandBounds.width
                - (bBounds.minX - fullBounds.minX) / fullBounds.width) < 0.00001
                && abs((aBounds.minY - islandBounds.minY) / islandBounds.height
                - (fullBounds.maxY - bBounds.maxY) / fullBounds.height) < 0.00001,
                       "\(name) is in the same canonical face location on both surfaces")
            for path in [a, b] {
                let records = normalizedPath(path, reference: path.boundingBoxOfPath)
                try expect(!records.contains(where: { $0.0 == Int(CGPathElementType.addCurveToPoint.rawValue)
                    || $0.0 == Int(CGPathElementType.addQuadCurveToPoint.rawValue) }),
                           "\(name) is a flat LED rectangle without an old circular pupil")
            }
            guard let aScan = try named("quietOrbit.eye.scanlines", in: island) as? CAShapeLayer,
                  let bScan = try named("quietOrbit.eye.scanlines", in: full) as? CAShapeLayer,
                  let aScanPath = aScan.path, let bScanPath = bScan.path else {
                throw failure("Both LED eyes require the same three visible scanlines")
            }
            try expect(pathsMatch(aScanPath, reference: islandBounds, bScanPath,
                                  reference: fullBounds, secondTopDown: false),
                       "\(name) retains the matching three scanline details")
            try expect(colorsMatch(aScan.strokeColor, bScan.strokeColor),
                       "\(name) scanlines retain the same contrast and transparency")
        }
        let islandVisor = try named("quietOrbit.visorGradient", in: robot.layer) as? CAGradientLayer
        let fullVisor = try named("quietOrbit.visorGradient", in: frame.layer) as? CAGradientLayer
        let islandVisorColors = (islandVisor?.colors as? [CGColor]) ?? []
        let fullVisorColors = (fullVisor?.colors as? [CGColor]) ?? []
        try expect(islandVisorColors.count == 3 && fullVisorColors.count == 3
            && zip(islandVisorColors, fullVisorColors).allSatisfy { colorsMatch($0, $1) },
                   "The angular visor retains the identical three-color dark-screen gradient")
        let islandCrop = try headBitmap(islandHead, bounds: islandBounds, topDown: true)
        let fullCrop = try headBitmap(fullHead, bounds: fullBounds, topDown: false)
        try expect(visiblePixelCount(islandCrop) > 1000 && visiblePixelCount(fullCrop) > 1000,
                   "Both head-only comparison renders contain actual opaque robot artwork")
        try save(islandCrop, named: "island-head-comparison", output: output, pixelScale: 4)
        try save(fullCrop, named: "full-app-head-comparison", output: output, pixelScale: 4)
        let difference = rasterDifference(islandCrop, fullCrop)
        try expect(difference < 0.025,
                   "Same-scale production head raster difference \(difference) stays below 2.5%")

        guard let mouth = try named("quietOrbit.mouth", in: frame.layer) as? CAShapeLayer,
              let idleMouth = mouth.path else { throw failure("The full robot needs its canonical mouth") }
        frame.celebrateTaskCompletion(reduceMotion: true)
        guard let smile = mouth.animation(forKey: "robotFrame.taskSmile") as? CAKeyframeAnimation,
              let smilePaths = smile.values as? [CGPath] else {
            throw failure("Saved task completion needs a real native mouth animation")
        }
        let topology = normalizedPath(idleMouth, reference: fullBounds).map(\.0)
        try expect(topology == [CGPathElementType.moveToPoint, .addLineToPoint, .addLineToPoint, .addLineToPoint]
            .map { Int($0.rawValue) },
                   "Canonical idle mouth is the approved four-point mechanical polyline")
        try expect(smilePaths.count == 4 && smilePaths.allSatisfy {
            normalizedPath($0, reference: fullBounds).map(\.0) == topology
        }, "Every happy-mouth keyframe has the same path topology as the idle mouth")
        try expect(!pathsMatch(smilePaths[1], reference: fullBounds,
                              idleMouth, reference: fullBounds),
                   "Saved-task acknowledgement visibly changes the expression")
        try expect(pathsMatch(smilePaths[0], reference: fullBounds,
                              idleMouth, reference: fullBounds)
            && pathsMatch(smilePaths[3], reference: fullBounds,
                          idleMouth, reference: fullBounds),
                   "Happy-mouth animation starts and ends at the canonical island expression")
        try expect(fullHead.animation(forKey: "robotFrame.taskHappy") == nil
            && !frame.hasActiveEyeMotion,
                   "Reduced task acknowledgement keeps the mechanical smile without hop or eye motion")
        frame.setVisible(false)
    }

    private static func checkFullApplication(output: URL) async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinRobotVisual-\(UUID().uuidString)", isDirectory: true)
        let store = try CaptureStore(root: fixtureRoot)
        let suiteName = "DaBinRobotVisualTests.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: suiteName) else {
            throw failure("Could not create isolated visual preferences")
        }
        preferences.set(false, forKey: PreviewService.linkPreviewPreference)
        let previews = PreviewService(store: store, defaults: preferences)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: VisualRobotReminderClient()))
        let theme = ThemeSettings(defaults: preferences, systemDarkMode: false)
        defer {
            previews.cancelNetwork()
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        let captured = try store.capture(text: "Workshop notes: the same soft-violet robot in both views.", at: Date())[0]
        try store.update(captured, comment: "A fictional local visual fixture.", reminderAt: nil, reminderTimeZoneID: nil)
        state.route = .daily
        for size in [CGSize(width: 380, height: 500), CGSize(width: 1200, height: 800)] {
            for dark in [false, true] {
                theme.setDarkMode(dark)
                let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme)
                    .environment(\.displayScale, 2)
                    .frame(width: size.width, height: size.height))
                let frame = RobotAppFrameView(contentView: hosting)
                frame.frame = CGRect(origin: .zero, size: RobotAppFrameView.outerSize(forContentSize: size))
                let window = host(frame)
                // Production places NSHostingView inside the robot shell, not
                // at the window root. Use its real AppKit appearance bridge;
                // preferredColorScheme alone cannot update a nested host.
                CornerController.applyBoardAppearance(darkMode: theme.darkModeEnabled,
                                                       to: window, frame: frame, hosting: hosting)
                frame.setVisible(true)
                try await Task.sleep(for: .milliseconds(160))
                frame.layoutSubtreeIfNeeded()
                let expectedAppearance: NSAppearance.Name = dark ? .darkAqua : .aqua
                try expect(theme.darkModeEnabled == dark,
                           "Each fixture uses its isolated, intended dark-mode preference")
                try expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expectedAppearance
                    && frame.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expectedAppearance
                    && hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expectedAppearance,
                           "Window, robot shell and nested production content all honor the intended appearance")
                try expect(hosting.frame == CGRect(origin: .zero, size: size),
                           "\(size) preserves the real application's full content dimensions")
                try expect(hosting.superview?.frame == RobotAppFrameView.contentRect(in: frame.bounds),
                           "\(size) applies the canonical content inset exactly once")
                try expect(RobotAppFrameView.contentInsets.top == 32
                    && RobotAppFrameView.contentInsets.left == 10
                    && RobotAppFrameView.contentInsets.bottom == 18
                    && RobotAppFrameView.contentInsets.right == 10,
                           "Consistent artwork never changes the application's existing clearances")
                let snapshot = try render(frame)
                try expect(snapshot.pixelsWide == Int(size.width + 20) * 2
                    && snapshot.pixelsHigh == Int(size.height + 50) * 2,
                           "Full production app renders at native 2x without bitmap upscaling")
                try expect(visiblePixelCount(snapshot) > snapshot.pixelsWide * snapshot.pixelsHigh / 2,
                           "The actual application and its robot shell are visible, not an empty render")
                let backgroundX = Int((RobotAppFrameView.contentRect(in: frame.bounds).minX + 8) * 2)
                guard let background = snapshot.colorAt(x: backgroundX, y: snapshot.pixelsHigh / 2)?
                    .usingColorSpace(.deviceRGB) else { throw failure("The real board background must be visible") }
                let brightness = (background.redComponent + background.greenComponent + background.blueComponent) / 3
                try expect(dark ? brightness < 0.35 : brightness > 0.8,
                           "The rendered board pixels are actually \(dark ? "dark" : "light"), not merely labelled so")
                appearanceFixtures.append([
                    "contentWidth": size.width, "contentHeight": size.height,
                    "darkModePreference": theme.darkModeEnabled,
                    "windowAppearance": window.effectiveAppearance.name.rawValue,
                    "frameAppearance": frame.effectiveAppearance.name.rawValue,
                    "hostingAppearance": hosting.effectiveAppearance.name.rawValue,
                    "renderedBackgroundBrightness": brightness
                ])
                try save(snapshot, named: "full-app-\(Int(size.width))x\(Int(size.height))-\(dark ? "dark" : "light")", output: output)
                let before = hosting.frame
                var opened = 0
                var closed = 0
                frame.animateOpen(from: CGRect(x: -9990, y: -9480, width: 72, height: 88),
                                  island: true, reduceMotion: true) { opened += 1 }
                try expect(frame.isTransitioning
                    && frame.layer?.animation(forKey: "robotFrame.reduced") != nil,
                           "Reduce Motion opens with the existing short opacity fade")
                try expect(hosting.frame == before,
                           "Opening never resizes the mounted production content")
                try await Task.sleep(for: .milliseconds(200))
                try expect(opened == 1 && frame.isFrameVisible && !frame.isTransitioning,
                           "Reduced opening completes exactly once at the visible endpoint")
                try expect(!frame.hasActiveEyeMotion,
                           "Reduce Motion does not animate gaze or blink in the full-size robot")
                try expect(hosting.frame == before,
                           "Reduced opening preserves the real content geometry")
                frame.animateClose(to: CGRect(x: -9990, y: -9480, width: 72, height: 88),
                                   island: true, reduceMotion: true) { closed += 1 }
                try await Task.sleep(for: .milliseconds(200))
                try expect(closed == 1 && !frame.isFrameVisible && !frame.isTransitioning,
                           "Reduced closing completes once and hides the native app frame")
                try expect(hosting.frame == before,
                           "Closing never changes the application's reserved content dimensions")
                window.orderOut(nil)
            }
        }

        // Use actual AppKit controls to distinguish decorative click-through
        // from application interaction without private SwiftUI hit-test hooks.
        let stage = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 700))
        let content = NSView(frame: .zero)
        let button = NSButton(title: "Capture control", target: nil, action: nil)
        button.frame = CGRect(x: 28, y: 35, width: 136, height: 32)
        content.addSubview(button)
        let frame = RobotAppFrameView(contentView: content)
        frame.frame = CGRect(x: 80, y: 70, width: 400, height: 550)
        stage.addSubview(frame)
        frame.setVisible(true)
        frame.layoutSubtreeIfNeeded()
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: stage)
        try expect(frame.hitTest(point) === button,
                   "Native controls remain directly interactive through the matching robot shell")
        let headPoint = CGPoint(x: frame.frame.midX, y: frame.frame.maxY - 4)
        try expect(frame.hitTest(headPoint) == nil,
                   "Decorative full-size robot artwork remains click-through")
        frame.onResize = { _ in }
        try expect(frame.hitTest(point) === button,
                   "Enabling resize edges never covers the existing content control")
        frame.setVisible(false)
        try expect(frame.hitTest(point) == nil,
                   "Hidden robot chrome cannot intercept a stale native control hit")
    }
}
