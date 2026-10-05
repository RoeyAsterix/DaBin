import AppKit
import Darwin
import Foundation

@MainActor private final class ZoomPerformanceWindow: NSWindow {
    var onDisplayMeasurement: ((String, Double) -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func display() {
        guard let onDisplayMeasurement else { super.display(); return }
        let before = ProcessInfo.processInfo.systemUptime
        super.display()
        onDisplayMeasurement("display", (ProcessInfo.processInfo.systemUptime - before) * 1000)
    }
    override func displayIfNeeded() {
        guard let onDisplayMeasurement else { super.displayIfNeeded(); return }
        let before = ProcessInfo.processInfo.systemUptime
        super.displayIfNeeded()
        onDisplayMeasurement("displayIfNeeded", (ProcessInfo.processInfo.systemUptime - before) * 1000)
    }
}
@MainActor private final class ZoomPerformanceNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ request: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Production BoardView with durable fictional arrivals, never the user's
/// archive or clipboard. Samples measure synthetic input-to-layout completion
/// and main-runloop intervals, not physical input latency or display refresh.
@main @MainActor private final class WorkspaceZoomPerformanceTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = WorkspaceZoomPerformanceTests()
        app.setActivationPolicy(.prohibited); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.run() }
            catch { result = 1; fputs("Workspace zoom performance QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "WorkspaceZoomPerformanceTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let ordered = values.sorted()
        return ordered.isEmpty ? 0 : ordered[min(ordered.count - 1, Int(Double(ordered.count - 1) * fraction))]
    }
    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
    private static func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }
    private static func settle(_ host: NSView, milliseconds: Int = 150) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        host.layoutSubtreeIfNeeded()
    }
    private static func imageData() -> Data {
        let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8,
            bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.28, green: 0.20, blue: 0.51, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        context.setFillColor(CGColor(red: 0.80, green: 0.67, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 25, y: 25, width: 150, height: 150))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }
    private static func render(_ view: NSView, to url: URL) throws {
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "ZoomBitmap", code: 1)
        }
        bitmap.size = size; view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ZoomPNG", code: 1)
        }
        try data.write(to: url)
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        // Optional retention experiment; the default stress workload and its
        // capture/latency gates remain unchanged. Never label this a burst run.
        let fixedData = environment["DABIN_ZOOM_PERFORMANCE_FIXED_DATA"] == "1"
        // Routine QA stays inside its per-suite timeout. Release validation
        // explicitly requests 600 seconds; the JSON records which was run.
        let duration = min(600, max(10, environment["DABIN_ZOOM_PERFORMANCE_SECONDS"].flatMap(Double.init) ?? 30))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinZoomPerformance-\(UUID())")
        let suite = "DaBinZoomPerformance.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let output = environment["DABIN_ZOOM_PERFORMANCE_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/qa/workspace-zoom-performance")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let fictionalImage = imageData()
        let fictionalDocument = Data("Fictional client brief; no private content.".utf8)
        let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-7 * 86_400)
        let captures = try (0..<5_000).map { index -> Capture in
            let id = UUID()
            let kind: CaptureKind = [.text, .task, .link, .image, .document][index % 5]
            let filename = kind == .image ? "Fictional concept \(index).png"
                : kind == .document ? "Fictional creative brief \(index).txt" : nil
            let originalPath = filename.map { "Originals/\(id.uuidString)/\(CaptureClassifier.storageFilename($0))" }
            if let originalPath {
                let url = root.appendingPathComponent(originalPath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (kind == .image ? fictionalImage : fictionalDocument).write(to: url)
            }
            let text = "Fictional item \(index): client feedback — مراجعة — レビュー. "
                + (index % 17 == 0 ? String(repeating: "A longer note retains its original context. ", count: 25) : "Next action is easy to find.")
            let capture = Capture(id: id, capturedAt: base.addingTimeInterval(Double(index)), kind: kind,
                originalURL: kind == .link ? "https://example.invalid/brief/\(index)" : nil,
                originalText: [.text, .task].contains(kind) ? text : nil,
                attachmentRelativePath: originalPath, originalFilename: filename,
                title: "\(kind == .task ? "Review" : "Reference") \(index) · North Studio",
                receipt: .automatic(kind == .image ? .automaticScreenshot : .automaticClipboard,
                    sourceApplicationName: "Fictional source", sourceApplicationBundleIdentifier: "invalid.example.fixture"))
            capture.projectName = index % 10 == 0 ? "South Studio" : "North Studio"
            capture.previewState = "ready"
            if kind == .image {
                let thumbnailPath = "Previews/\(id.uuidString)/thumbnail.png"
                let url = root.appendingPathComponent(thumbnailPath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fictionalImage.write(to: url)
                capture.thumbnailRelativePath = thumbnailPath
            }
            if kind == .task { capture.setTaskPlanning(TaskPlanning(priority: index % 2 == 0 ? .high : .medium)) }
            return capture
        }
        let seedStarted = ProcessInfo.processInfo.systemUptime
        try CaptureRepository(root: root).save(captures)
        let seedSeconds = ProcessInfo.processInfo.systemUptime - seedStarted
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let managedAssets = store.captures.filter { $0.attachmentRelativePath != nil }
        let images = store.captures.filter { $0.kind == .image }
        try expect(managedAssets.count == 2_000 && managedAssets.allSatisfy {
            store.managedURL(for: $0) != nil && CapturePreviewFileReference.original(store: store, capture: $0) != nil
        }, "All 2000 fictional image/document originals satisfy production ownership and file validation")
        try expect(images.count == 1_000 && images.allSatisfy {
            CapturePreviewFileReference.thumbnail(store: store, capture: $0) != nil
                && store.previewURL(for: $0).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }, "All 1000 image thumbnails use accepted per-capture paths and exist on disk")
        let firstImage = images[0]
        let decoded = await CapturePreviewImageCache.shared.image(for: CapturePreviewImageRequest(
            file: CapturePreviewFileReference.thumbnail(store: store, capture: firstImage)!,
            maximumPixelSize: 600, revision: firstImage.previewState))
        try expect(decoded?.image.width == 320 && decoded?.image.height == 200,
                   "The production preview cache decodes the fictional image, rather than displaying a missing-file placeholder")
        let previews = PreviewService(store: store, defaults: defaults)
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Staging"))
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: input,
            pasteboardProvider: { fatalError("Performance fixture must never read the clipboard") }, sourceApplicationProvider: { nil })
        let zoom = WorkspaceZoomSettings(defaults: defaults)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ZoomPerformanceNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Performance fixture must never write the clipboard") }),
            workspaceZoom: zoom, manualInput: input)
        defer { state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); auto.shutdown(); previews.shutdown(); store.cancelArchiveRepair() }
        state.openLibrary(); state.navigateProject("North Studio")
        let selected = store.captures.first { $0.projectName == "North Studio" && $0.kind == .image }!.id
        state.workspace.selectedCaptureID = selected
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        let hosting = DailyCaptureHostingView(state: state, theme: theme)
        let frame = RobotAppFrameView(contentView: hosting)
        let original = CGRect(x: -10_000, y: -10_000, width: 940, height: 750)
        let window = ZoomPerformanceWindow(contentRect: original, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = frame
        frame.autoresizingMask = [.width, .height]
        window.sharingType = .none; window.orderFront(nil); frame.setVisible(true)
        state.isBoardVisible = true
        defer { zoom.finishInteraction(); frame.setVisible(false); window.orderOut(nil); window.contentView = nil; window.close() }
        let reference = WorkspaceZoomGeometry(frame: original, factor: 1)!
        let available = CGRect(x: -10_000, y: -11_000, width: 1_600, height: 1_750)
        var lastCoupledResizeMilliseconds = 0.0
        zoom.onInteractionBegan = { WorkspaceZoomViewport.begin(in: window, anchorInWindow: zoom.anchorInWindow); return true }
        zoom.onFactorChanged = { factor in
            if zoom.resizeWindowWithZoom, let target = reference.frame(at: factor, visible: available) {
                let before = ProcessInfo.processInfo.systemUptime
                window.setFrame(target, display: true)
                lastCoupledResizeMilliseconds = (ProcessInfo.processInfo.systemUptime - before) * 1000
            }
        }
        zoom.onInteractionEnded = { WorkspaceZoomViewport.end(in: window) }
        try await settle(frame, milliseconds: 350)
        try expect(store.captures.count == 5_000 && !window.isKeyWindow && !window.isMainWindow,
                   "5000 mixed records load in a nonactivating production board fixture")
        guard let nativeTable = table(in: hosting), nativeTable.numberOfRows > 100 else {
            throw NSError(domain: "WorkspaceZoomPerformanceTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Project fixture must create a recycled native table"])
        }
        let middleRow = min(nativeTable.numberOfRows - 1, 250)
        nativeTable.scrollRowToVisible(middleRow)
        try await settle(frame)

        var phase = "warm baseline"
        var nativeDisplayStages: [String: [Double]] = [:]
        window.onDisplayMeasurement = { stage, milliseconds in
            guard phase == "steady zoom", nativeDisplayStages[stage, default: []].count < 4_000 else { return }
            nativeDisplayStages[stage, default: []].append(milliseconds)
        }
        defer { window.onDisplayMeasurement = nil }
        var baselineIntervals: [Double] = [], activeIntervals: [Double] = [], maximumAvailableRows = 0
        var allIntervals: [Double] = []
        var intervalsByPhase: [String: [Double]] = [:]
        var intervalSampleCount = 0
        let maximumIntervalSamples = 60_000
        var lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = (now - lastTick) * 1000; lastTick = now
                intervalSampleCount += 1
                if allIntervals.count < maximumIntervalSamples {
                    allIntervals.append(elapsed)
                    intervalsByPhase[phase, default: []].append(elapsed)
                    if phase == "warm baseline" { baselineIntervals.append(elapsed) }
                    else if phase == "steady zoom" { activeIntervals.append(elapsed) }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }
        try await Task.sleep(for: .seconds(1))
        let baselineRSS = residentBytes()
        let started = ProcessInfo.processInfo.systemUptime
        var arrivals = 0, burstDone = false, cycle = 0, nextArrival = started + 2
        var inputLayoutMilliseconds: [Double] = [], saveMilliseconds: [Double] = []
        var inputStages: [String: [Double]] = [:]
        var memory: [[String: Any]] = [["phase": "baseline", "rssBytes": baselineRSS]]
        var cycles: [[String: Any]] = []

        func saveArrival() throws {
            let before = ProcessInfo.processInfo.systemUptime
            let capture = try store.capture(text: "Fictional automatic follow-up \(arrivals)",
                receipt: .automatic(.automaticClipboard, sourceApplicationName: "Fictional source",
                    sourceApplicationBundleIdentifier: "invalid.example.fixture"), projectName: "North Studio")
            state.didAutoCapture(capture); arrivals += capture.count
            saveMilliseconds.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
        }
        while ProcessInfo.processInfo.systemUptime - started < duration || cycle < 5 {
            let now = ProcessInfo.processInfo.systemUptime
            if !fixedData, now >= nextArrival {
                phase = "durable arrival"; try saveArrival(); nextArrival += 2
            }
            if cycle < 5 && now - started >= Double(cycle) * duration / 5 {
                phase = "navigation"
                if cycle > 0 {
                    state.navigateProject("South Studio"); state.navigateProject("North Studio")
                    try await settle(frame)
                }
                state.workspace.selectedCaptureID = selected
                WorkspaceZoomViewport.flushHistory()
                let beforeAnchor = state.projectPresentation["North Studio"]?.viewport
                let cycleStart = ProcessInfo.processInfo.systemUptime
                guard zoom.beginInteraction() else { throw NSError(domain: "ZoomBegin", code: 1) }
                try expect(state.isNavigationBlocked, "History is blocked while the long-list zoom owns the gesture")
                for step in 0..<32 {
                    phase = "steady zoom"
                    let value: CGFloat = step < 16 ? 1 + CGFloat(step) / 15 : 2 - CGFloat(step - 16) / 15
                    lastCoupledResizeMilliseconds = 0
                    let before = ProcessInfo.processInfo.systemUptime
                    zoom.update(to: value)
                    let updated = ProcessInfo.processInfo.systemUptime
                    frame.layoutSubtreeIfNeeded()
                    let firstLayout = ProcessInfo.processInfo.systemUptime
                    try await Task.sleep(for: .milliseconds(1))
                    let resumed = ProcessInfo.processInfo.systemUptime
                    frame.layoutSubtreeIfNeeded()
                    let completed = ProcessInfo.processInfo.systemUptime
                    inputLayoutMilliseconds.append((completed - before) * 1000)
                    // Nested resize is already included in update.total. Keep
                    // the original workload and completion boundary unchanged.
                    inputStages["update.total", default: []].append((updated - before) * 1000)
                    inputStages["update.coupledResize", default: []].append(lastCoupledResizeMilliseconds)
                    inputStages["update.excludingCoupledResize", default: []].append(max(0, (updated - before) * 1000 - lastCoupledResizeMilliseconds))
                    inputStages["firstLayout", default: []].append((firstLayout - updated) * 1000)
                    inputStages["schedulingWait", default: []].append((resumed - firstLayout) * 1000)
                    inputStages["secondLayout", default: []].append((completed - resumed) * 1000)
                    if !fixedData && !burstDone && step == 8 {
                        phase = "100 durable arrivals during zoom"
                        for burst in 0..<100 {
                            try saveArrival()
                            if burst % 5 == 4 { try await Task.sleep(for: .milliseconds(1)) }
                        }
                        burstDone = true
                        try expect(zoom.isInteracting && state.workspace.selectedCaptureID == selected,
                                   "A 100-capture burst retains the gesture and selected identity")
                    }
                    if !fixedData, ProcessInfo.processInfo.systemUptime >= nextArrival {
                        phase = "durable arrival"; try saveArrival(); nextArrival += 2
                    }
                    try await Task.sleep(for: .milliseconds(15))
                }
                zoom.finishInteraction(); phase = "settling"; try await settle(frame)
                WorkspaceZoomViewport.flushHistory()
                let afterAnchor = state.projectPresentation["North Studio"]?.viewport
                if cycle == 0 {
                    try expect(beforeAnchor != nil && afterAnchor != nil,
                               "The long-list fixture records native viewport anchors")
                    if let beforeAnchor, let afterAnchor {
                        let survivors = Set([afterAnchor.itemID] + afterAnchor.neighbors)
                        try expect(survivors.contains(beforeAnchor.itemID),
                                   fixedData ? "Fixed-data round-trip zoom preserves the visible item or its immediate neighbors"
                                       : "A 100-item insertion and round-trip zoom preserve the visible item or its immediate neighbors")
                    }
                }
                if let table = table(in: hosting) {
                    var count = 0; table.enumerateAvailableRowViews { _, _ in count += 1 }
                    maximumAvailableRows = max(maximumAvailableRows, count)
                    try expect(count < 100 && table.numberOfRows > 100,
                               "Native project rows remain viewport-bounded in cycle \(cycle)")
                }
                try expect(state.workspace.selectedCaptureID == selected && state.libraryProject == "North Studio",
                           "Zoom and arrivals preserve selection and project in cycle \(cycle)")
                let rss = residentBytes()
                memory.append(["phase": "cycle \(cycle + 1)", "rssBytes": rss])
                cycles.append(["cycle": cycle + 1, "durationSeconds": ProcessInfo.processInfo.systemUptime - cycleStart,
                               "captures": store.captures.count, "rssBytes": rss,
                               "anchorBefore": beforeAnchor?.itemID ?? "none", "anchorAfter": afterAnchor?.itemID ?? "none"])
                cycle += 1
                print("CYCLE: \(cycle)/5, records=\(store.captures.count), RSS=\(rss)"); fflush(stdout)
            }
            phase = "idle between inputs"
            try await Task.sleep(for: .milliseconds(20))
        }
        timer.invalidate()
        let runSeconds = ProcessInfo.processInfo.systemUptime - started
        memory.append(["phase": "end of measured run", "rssBytes": residentBytes()])
        try expect(store.captures.count == 5_000 + arrivals && (fixedData ? arrivals == 0 && !burstDone : burstDone),
                   fixedData ? "Fixed-data mode retains exactly the original 5000 records without capture writes or arrivals"
                       : "Every fictional automatic receipt remains present")
        try expect(zoom.persistenceCount <= 5, "160 magnification ticks write at most five scale preferences")
        try expect(!zoom.isInteracting && !WorkspaceZoomViewport.isZooming(in: window), "Long run leaves no transient gesture owner")
        let p95Input = percentile(inputLayoutMilliseconds, 0.95), p95Frame = percentile(activeIntervals, 0.95)
        let baselineP95 = percentile(baselineIntervals, 0.95)
        let phaseMetrics: [[String: Any]] = intervalsByPhase.keys.sorted().map { name in
            let samples = intervalsByPhase[name] ?? []
            return ["phase": name, "count": samples.count,
                    "p95Milliseconds": percentile(samples, 0.95), "maximumMilliseconds": samples.max() ?? 0,
                    "intervalsAbove100Milliseconds": samples.filter { $0 > 100 }.count]
        }
        let inputStageMetrics: [[String: Any]] = inputStages.keys.sorted().map { name in
            let samples = inputStages[name] ?? []
            return ["stage": name, "count": samples.count,
                    "medianMilliseconds": percentile(samples, 0.5), "p95Milliseconds": percentile(samples, 0.95),
                    "maximumMilliseconds": samples.max() ?? 0]
        }
        let nativeDisplayStageMetrics: [[String: Any]] = nativeDisplayStages.keys.sorted().map { name in
            let samples = nativeDisplayStages[name] ?? []
            return ["stage": name, "count": samples.count,
                    "medianMilliseconds": percentile(samples, 0.5), "p95Milliseconds": percentile(samples, 0.95),
                    "maximumMilliseconds": samples.max() ?? 0]
        }
        var warnings: [String] = []
        if p95Input > 50 { warnings.append("Synthetic input-to-layout p95 exceeds 50 ms") }
        if p95Frame > 33 { warnings.append("Steady zoom main-runloop interval p95 exceeds 33 ms") }
        if (activeIntervals.max() ?? 0) > 100 { warnings.append("A steady zoom main-runloop interval exceeds 100 ms; compare baseline and inspect attribution") }
        for name in intervalsByPhase.keys.sorted() {
            if let maximum = intervalsByPhase[name]?.max(), maximum > 100 {
                warnings.append("Main-runloop interval reached \(maximum) ms in phase '\(name)'; delivery-phase labeling can include preceding operation time")
            }
        }
        if intervalSampleCount > maximumIntervalSamples { warnings.append("Timer sample storage reached its bounded 60000-record limit") }
        let rssValues = memory.compactMap { $0["rssBytes"] as? UInt64 }
        if zip(rssValues, rssValues.dropFirst()).allSatisfy({ $0.1 > $0.0 }) {
            warnings.append(fixedData
                ? "RSS increased at every fixed-data checkpoint; retained timing samples and cache warm-up still require allocation attribution"
                : "RSS increased at every checkpoint; archive arrivals and thumbnail caches grow too, so isolate retention before attributing a leak")
        }
        let timerCapacityBytes = MemoryLayout<Double>.stride * (allIntervals.capacity
            + intervalsByPhase.values.reduce(0) { $0 + $1.capacity } + baselineIntervals.capacity + activeIntervals.capacity)
        let inputStageCapacityBytes = MemoryLayout<Double>.stride * inputStages.values.reduce(0) { $0 + $1.capacity }
        let displayStageCapacityBytes = MemoryLayout<Double>.stride * nativeDisplayStages.values.reduce(0) { $0 + $1.capacity }
        let report: [String: Any] = [
            "workload": fixedData ? "fixed-data retention experiment" : "durable arrivals and burst stress",
            "fixedData": fixedData, "retainedTimerCapacityBytes": timerCapacityBytes,
            "retainedInputStageCapacityBytes": inputStageCapacityBytes,
            "retainedNativeDisplayStageCapacityBytes": displayStageCapacityBytes,
            "retainedCaptureModels": store.captures.count,
            "measurement": "Synthetic native input-to-layout flush and main-runloop timer intervals; not physical input-to-display latency",
            "durationSeconds": runSeconds, "requestedDurationSeconds": duration, "fullTenMinuteRun": duration == 600,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "processors": ProcessInfo.processInfo.processorCount,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory, "architecture": "arm64",
            "backingScale": window.backingScaleFactor, "initialRecords": 5_000, "automaticArrivals": arrivals,
            "validatedManagedOriginals": managedAssets.count, "validatedImageThumbnails": images.count,
            "burstSize": fixedData ? 0 : 100, "arrivalCadenceSeconds": fixedData ? 0 : 2, "cycles": cycles, "seedSeconds": seedSeconds,
            "baselineTimerP95Milliseconds": baselineP95, "steadyZoomTimerP95Milliseconds": p95Frame,
            "steadyZoomTimerMaxMilliseconds": activeIntervals.max() ?? 0, "timerSamples": activeIntervals.count,
            "wholeRunTimerMaximumMilliseconds": allIntervals.max() ?? 0,
            "wholeRunTimerP95Milliseconds": percentile(allIntervals, 0.95),
            "wholeRunTimerIntervalsAbove100Milliseconds": allIntervals.filter { $0 > 100 }.count,
            "wholeRunTimerSamples": allIntervals.count, "observedTimerSamples": intervalSampleCount,
            "timerIntervalsByPhase": phaseMetrics,
            "timerPhaseAttribution": "Every interval is retained including burst, navigation, save, settle and idle phases; labels describe phase at callback delivery, so an interval can span an earlier phase boundary",
            "inputToLayoutP95Milliseconds": p95Input, "inputSamples": inputLayoutMilliseconds.count,
            "inputStageMilliseconds": inputStageMetrics,
            "nativeDisplayStageMilliseconds": nativeDisplayStageMetrics,
            "performanceGates": ["inputToLayoutP95MaximumMilliseconds": 50,
                "steadyZoomTimerP95MaximumMilliseconds": 33,
                "passed": p95Input <= 50 && p95Frame <= 33],
            "durableSaveP95Milliseconds": percentile(saveMilliseconds, 0.95), "memory": memory,
            "maximumAvailableNativeRows": maximumAvailableRows, "warnings": warnings,
            "limitations": ["No physical trackpad or mouse-driver coverage", "Offscreen native rendering cannot measure presentation timestamps",
                fixedData ? "RSS includes the fixed fixture, cache warm-up and retained timing arrays; this is not a heap-leak diagnosis"
                    : "RSS includes the growing fixture archive, caches and retained timing arrays"]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("performance.json"))
        print("STAGES: \(inputStageMetrics); native display: \(nativeDisplayStageMetrics)"); fflush(stdout)
        try expect(p95Input <= 50, "Synthetic input-to-layout p95 must stay within the existing 50 ms budget; report: \(output.path)")
        try expect(p95Frame <= 33, "Steady zoom main-runloop p95 must stay within the existing 33 ms budget; report: \(output.path)")
        for factor in [CGFloat(0.75), 1, 1.5, 2] {
            zoom.setFactor(factor); try await settle(frame, milliseconds: 200)
            try render(frame, to: output.appendingPathComponent("production-board-\(Int(factor * 100))@2x.png"))
        }
        print("PASS: \(checks) workspace zoom performance checks. \(runSeconds)s, \(arrivals) arrivals, 5 cycles. Synthetic input-to-layout p95 \(p95Input)ms; steady runloop p95 \(p95Frame)ms; warnings: \(warnings). Report: \(output.path)")
    }
}
