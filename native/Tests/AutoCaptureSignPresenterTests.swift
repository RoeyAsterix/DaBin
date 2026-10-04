import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class SignReceiptScreenshotMonitor: ScreenshotFolderMonitoring {
    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var projectAtDirectoryActivity: (() -> String?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?, String?) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false

    func start() throws { isRunning = true }
    func stop() { isRunning = false }

    func emit(_ url: URL) {
        guard isRunning else { return }
        onNewScreenshot?(url, sourceApplicationAtDirectoryActivity?(), projectAtDirectoryActivity?())
    }
}

/// Typed success receipts only, with synthetic displays, clocks and private
/// pasteboards. This suite never reads the general clipboard, user archives,
/// installed applications, screenshot permissions or real display contents.
@main
@MainActor
private struct AutoCaptureSignPresenterTests {
    private static var checks = 0

    private static let islandRect = CGRect(x: 690, y: 950, width: 132, height: 32)
    private static let builtIn = AutoCaptureRobotScreen(
        displayID: 7,
        frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
        safeAreaTop: 32,
        isBuiltIn: true,
        cameraIslandRect: islandRect
    )
    private static let external = AutoCaptureRobotScreen(
        displayID: 19,
        frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_055),
        safeAreaTop: 0,
        isBuiltIn: false
    )

    private enum Interruption {
        case board
        case interaction
        case taskTimer

        var name: String {
            switch self {
            case .board: return "board"
            case .interaction: return "interaction"
            case .taskTimer: return "task timer"
            }
        }

        @MainActor
        func suspend(_ presenter: AutoCaptureRobotPresenter) {
            switch self {
            case .board: presenter.suspendForBoard()
            case .interaction: presenter.suspendForInteraction()
            case .taskTimer: presenter.suspendForTaskTimer()
            }
        }

        @MainActor
        func resume(_ presenter: AutoCaptureRobotPresenter) -> Bool {
            switch self {
            case .board: return presenter.resumeAfterBoard()
            case .interaction: return presenter.resumeAfterInteraction()
            case .taskTimer: return presenter.resumeAfterTaskTimer()
            }
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool,
                               _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func waitUntil(timeout: TimeInterval = 3,
                                  _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 9_999,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for isolated sign QA state."])
    }

    private static func animationSummary(in layer: CALayer?) -> String {
        guard let layer else { return "no content layer" }
        var summaries: [String] = []
        func visit(_ layer: CALayer) {
            if let keys = layer.animationKeys(), !keys.isEmpty {
                summaries.append("\(layer.name ?? "unnamed"): \(keys.sorted().joined(separator: ","))")
            }
            for child in layer.sublayers ?? [] { visit(child) }
        }
        visit(layer)
        return summaries.isEmpty ? "no layer animations" : summaries.joined(separator: "; ")
    }

    private static func storedAnimationSummary(in view: AutoCaptureSignView) -> String {
        var summaries: [String] = []
        for child in Mirror(reflecting: view).children {
            let name = child.label ?? "unnamed"
            let layer = (child.value as? CALayer) ?? (child.value as? NSView)?.layer
            if let keys = layer?.animationKeys(), !keys.isEmpty {
                summaries.append("\(name): \(keys.sorted().joined(separator: ","))")
            }
        }
        return summaries.isEmpty ? "no stored-layer animations" : summaries.joined(separator: "; ")
    }

    private static func action(origin: CaptureOrigin, captures: [Capture],
                               privateValue: String) -> AutoCaptureSavedAction {
        AutoCaptureSavedAction(
            actionID: UUID(),
            origin: origin,
            capturedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            sourceApplication: AutoCaptureSourceApplication(
                name: privateValue,
                bundleIdentifier: "invalid.private.\(privateValue)"
            ),
            projectName: privateValue,
            captures: captures
        )
    }

    private static func privateCapture(_ privateValue: String,
                                       origin: CaptureOrigin) -> Capture {
        let receipt: CaptureReceiptContext = origin.isAutomatic
            ? .automatic(origin, sourceApplicationName: privateValue,
                         sourceApplicationBundleIdentifier: "invalid.private.source")
            : .manual
        let capture = Capture(
            capturedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            kind: .text,
            originalText: privateValue,
            originalFilename: privateValue,
            title: privateValue,
            receipt: receipt
        )
        capture.projectName = privateValue
        capture.comment = privateValue
        return capture
    }

    private static func receiptFactoryChecks() throws {
        let secret = "PRIVATE-TITLE-PROJECT-SOURCE-\(UUID().uuidString)"
        let screenshotAction = action(
            origin: .automaticScreenshot,
            captures: [privateCapture(secret, origin: .automaticScreenshot)],
            privateValue: secret
        )
        let clipboardAction = action(
            origin: .automaticClipboard,
            captures: [privateCapture(secret, origin: .automaticClipboard),
                       privateCapture(secret + "-SECOND", origin: .automaticClipboard)],
            privateValue: secret
        )
        let manualAction = action(
            origin: .manual,
            captures: [privateCapture(secret, origin: .manual)],
            privateValue: secret
        )

        guard let screenshot = AutoCaptureSignReceipt(savedAction: screenshotAction),
              let clipboard = AutoCaptureSignReceipt(savedAction: clipboardAction) else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Typed receipt factory rejected a successful automatic action."])
        }
        try expect(screenshot == AutoCaptureSignReceipt(kind: .screenshot)
                   && screenshot.icon == "camera.viewfinder"
                   && screenshot.message == "Screenshot saved!"
                   && screenshot.accessibilityText == "Screenshot saved",
                   "A screenshot action produces only the closed screenshot icon and copy")
        try expect(clipboard == AutoCaptureSignReceipt(kind: .clipboard)
                   && clipboard.count == 1
                   && clipboard.icon == "doc.on.clipboard.fill"
                   && clipboard.message == "Copied!"
                   && clipboard.accessibilityText == "Copied",
                   "A multi-file clipboard save remains one user action on the confirmation sign")
        let mixed = screenshot.merging(AutoCaptureSignReceipt(kind: .clipboard, count: 2))
        try expect(mixed == AutoCaptureSignReceipt(kind: .mixed, count: 3)
                   && mixed.icon == "square.stack.3d.up.fill"
                   && mixed.message == "Captures saved!"
                   && mixed.accessibilityText == "3 captures saved",
                   "Mixed rapid receipts expose their exact count and generic capture icon")
        let rendered = [screenshot.icon, screenshot.message, screenshot.accessibilityText,
                        clipboard.icon, clipboard.message, clipboard.accessibilityText,
                        mixed.icon, mixed.message, mixed.accessibilityText].joined(separator: " ")
        try expect(!rendered.localizedCaseInsensitiveContains(secret)
                   && !rendered.localizedCaseInsensitiveContains("project")
                   && !rendered.localizedCaseInsensitiveContains("source"),
                   "Receipt-visible fields cannot reveal titles, content, projects or source applications")
        try expect(AutoCaptureSignReceipt(savedAction: manualAction) == nil
                   && AutoCaptureSignReceipt(savedAction: action(
                        origin: .automaticClipboard, captures: [], privateValue: secret)) == nil,
                   "Manual and empty actions cannot manufacture a success confirmation")
        try expect(AutoCaptureSignReceipt(kind: .screenshot, count: 0).count == 1,
                   "A malformed nonpositive count is clamped to one without exposing input")
    }

    private static func panelAndImmediateMergeChecks() throws {
        var clock = Date(timeIntervalSinceReferenceDate: 2_000)
        var announcements: [String] = []
        let presenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            currentDate: { clock },
            signDeck: AutoCaptureSignDeck(seed: 71),
            announce: { announcements.append($0) }
        )
        defer { presenter.shutdown() }
        let panelIdentity = ObjectIdentifier(presenter.panel)
        let first = AutoCaptureSignReceipt(kind: .screenshot, count: 2)
        try expect(presenter.present(confirmation: first),
                   "A typed screenshot receipt starts a confirmation performance")
        guard let performance = presenter.currentSignPerformance else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Typed presentation did not create a sign performance."])
        }
        guard let sign = presenter.panel.contentView as? AutoCaptureSignView else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 31,
                          userInfo: [NSLocalizedDescriptionKey: "Typed presentation did not install its dedicated sign view."])
        }
        try expect(presenter.currentSignReceipt == first
                   && presenter.currentPerformance == nil
                   && presenter.signMessage == "Screenshot saved!"
                   && presenter.badgeText == "×2"
                   && presenter.pendingConfirmationPerformances == 0
                   && presenter.pendingConfirmationCount == 0
                   && presenter.signHasActiveAnimations,
                   "The sign's read-only state exactly describes its active screenshot receipt")
        try expect(sign.performance == performance
                   && sign.receipt == first
                   && sign.receipt?.icon == "camera.viewfinder"
                   && sign.signMessage == "Screenshot saved!"
                   && sign.countText == "×2"
                   && sign.accessibilityStatus == "2 screenshots saved"
                   && sign.usesIsland
                   && !sign.reduceMotion
                   && sign.nativeArmsAreHidden
                   && sign.hasArmConnection
                   && sign.hasActiveAnimations
                   && sign.hitTest(.zero) == nil,
                   "The island sign renders only the closed receipt vocabulary and cannot receive input")
        try expect(presenter.panel.styleMask.contains(.borderless)
                   && presenter.panel.styleMask.contains(.nonactivatingPanel)
                   && !presenter.panel.canBecomeKey
                   && !presenter.panel.canBecomeMain
                   && !presenter.panel.isKeyWindow
                   && !presenter.panel.isMainWindow
                   && presenter.panel.ignoresMouseEvents
                   && presenter.panel.sharingType == .none,
                   "The confirmation is one passive, nonfocusable, click-through panel with the legacy sharing hint")

        let second = AutoCaptureSignReceipt(kind: .clipboard, count: 3)
        try expect(presenter.present(confirmation: second)
                   && presenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 5)
                   && presenter.signMessage == "Captures saved!"
                   && presenter.badgeText == "×5"
                   && presenter.state.visibleCount == 5
                   && presenter.currentSignPerformance == performance
                   && presenter.performanceStartCount == 1
                   && presenter.pendingConfirmationPerformances == 0
                   && presenter.panel.contentView === sign
                   && sign.receipt == AutoCaptureSignReceipt(kind: .mixed, count: 5)
                   && sign.receipt?.icon == "square.stack.3d.up.fill"
                   && sign.signMessage == "Captures saved!"
                   && sign.countText == "×5"
                   && sign.accessibilityStatus == "5 captures saved"
                   && ObjectIdentifier(presenter.panel) == panelIdentity,
                   "An immediate mixed burst updates the existing sign and exact count without another panel or performance")
        try expect(announcements.isEmpty,
                   "Presentation never synchronously announces before the sign becomes readable")
        clock.addTimeInterval(0.01)
    }

    private static func lateBurstQueueChecks() throws {
        var clock = Date(timeIntervalSinceReferenceDate: 3_000)
        let presenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { external },
            reduceMotion: { false },
            currentDate: { clock },
            signDeck: AutoCaptureSignDeck(seed: 72),
            announce: { _ in }
        )
        defer { presenter.shutdown() }
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot)),
                   "A sign starts before exercising its late-arrival queue")
        let active = presenter.currentSignReceipt
        clock.addTimeInterval(10)
        for index in 0..<4 {
            let kind: AutoCaptureSignKind = index.isMultiple(of: 2) ? .clipboard : .screenshot
            try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: kind, count: 2_500)),
                       "Late receipt \(index + 1) is retained")
        }
        try expect(presenter.currentSignReceipt == active
                   && presenter.state.visibleCount == 1
                   && presenter.pendingConfirmationCount == 10_000
                   && presenter.pendingCaptureCount == 10_000
                   && presenter.pendingConfirmationPerformances == 1
                   && presenter.performanceStartCount == 1,
                   "Ten thousand late saves retain one exact, allocation-bounded pending confirmation")
    }

    private static func enablementAndReducedMotionChecks() async throws {
        let disabled = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            signDeck: AutoCaptureSignDeck(seed: 73),
            announce: { _ in }
        )
        try expect(disabled.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard, count: 2)),
                   "An enabled presenter accepts a typed confirmation")
        guard let disabledSign = disabled.panel.contentView as? AutoCaptureSignView else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 42,
                          userInfo: [NSLocalizedDescriptionKey: "Enablement fixture did not install the sign view."])
        }
        disabled.suspendForBoard()
        try expect(disabled.pendingConfirmationCount == 2
                   && disabled.pendingConfirmationPerformances == 1,
                   "The enablement fixture holds a pending receipt before disable")
        disabled.setConfirmationEnabled(false)
        try expect(!disabled.confirmationEnabled,
                   "Turning confirmations off updates the presenter gate immediately")
        try expect(!disabled.state.isVisible && !disabled.panel.isVisible,
                   "Turning confirmations off immediately dismisses the active panel")
        try expect(disabled.currentSignPerformance == nil
                   && disabled.currentSignReceipt == nil
                   && disabled.signMessage == nil,
                   "Turning confirmations off clears the active sign's read-only fields")
        try expect(disabled.pendingConfirmationCount == 0
                   && disabled.pendingConfirmationPerformances == 0,
                   "Turning confirmations off clears the bounded receipt queue")
        try expect(!disabled.signHasActiveAnimations && !disabledSign.hasActiveAnimations,
                   "Turning confirmations off removes every sign animation immediately "
                   + "(same view: \(disabled.panel.contentView === disabledSign); "
                   + "presenter: \(disabled.signHasActiveAnimations); view: \(disabledSign.hasActiveAnimations); "
                   + "\(animationSummary(in: disabledSign.layer)); \(storedAnimationSummary(in: disabledSign)))")
        try expect(!disabled.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot)),
                   "Turning confirmations off immediately rejects later typed receipts")
        disabled.shutdown()

        let legacy = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            signDeck: AutoCaptureSignDeck(seed: 730),
            announce: { _ in }
        )
        defer { legacy.shutdown() }
        try expect(legacy.present(additionalCaptureCount: 2, projectName: "Local fixture")
                   && legacy.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot, count: 3))
                   && legacy.currentPerformance != nil
                   && legacy.currentSignReceipt == nil
                   && legacy.pendingConfirmationCount == 3,
                   "The legacy presenter can remain active while one typed confirmation waits")
        legacy.setConfirmationEnabled(false)
        try expect(!legacy.confirmationEnabled
                   && legacy.state.isVisible
                   && legacy.panel.isVisible
                   && legacy.currentPerformance != nil
                   && legacy.currentSignPerformance == nil
                   && legacy.currentSignReceipt == nil
                   && legacy.state.visibleCount == 2
                   && legacy.pendingCaptureCount == 0
                   && legacy.pendingConfirmationPerformances == 0
                   && !legacy.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard)),
                   "Disabling typed confirmations drops their queue without interrupting legacy feedback")

        let reduced = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { true },
            signDeck: AutoCaptureSignDeck(seed: 74),
            announce: { _ in }
        )
        defer { reduced.shutdown() }
        try expect(reduced.present(confirmation: AutoCaptureSignReceipt(kind: .mixed, count: 4)),
                   "Reduce Motion still presents a readable typed confirmation")
        guard let performance = reduced.currentSignPerformance else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Reduced presentation has no performance."])
        }
        try expect(performance.reduceMotion && performance.frames.allSatisfy {
            $0.robotTranslationX == 0 && $0.robotTranslationY == 0
                && $0.robotScaleX == 1 && $0.robotScaleY == 1
                && $0.robotRotationDegrees == 0
                && $0.signTranslationX == 0 && $0.signTranslationY == 0
                && $0.signScaleX == 1 && $0.signScaleY == 1
                && $0.signRotationDegrees == 0 && $0.signYRotationDegrees == 0
        }, "Reduced confirmation uses opacity only, without robot or sign travel")
        try expect(reduced.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 4)
                   && reduced.signMessage == "Captures saved!"
                   && reduced.signHasActiveAnimations,
                   "Reduced motion preserves exact read-only receipt state and a bounded fade animation")
        guard let reducedSign = reduced.panel.contentView as? AutoCaptureSignView else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 41,
                          userInfo: [NSLocalizedDescriptionKey: "Reduced presentation did not install the sign view."])
        }
        try expect(reducedSign.reduceMotion
                   && reducedSign.receipt == AutoCaptureSignReceipt(kind: .mixed, count: 4)
                   && reducedSign.countText == "×4"
                   && reducedSign.nativeArmsAreHidden
                   && reducedSign.hasArmConnection,
                   "Reduced Motion keeps the same private sign content and physical grip")
        await Task.yield()
    }

    private static func announcementMergeChecks() async throws {
        var announcements: [String] = []
        let presenter = AutoCaptureRobotPresenter(
            dismissDelay: 4,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            signDeck: AutoCaptureSignDeck(seed: 731),
            announce: { announcements.append($0) }
        )
        defer { presenter.shutdown() }
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot)),
                   "The accessibility merge fixture starts one typed confirmation")
        guard let performance = presenter.currentSignPerformance else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 43,
                          userInfo: [NSLocalizedDescriptionKey: "Accessibility merge fixture has no performance."])
        }
        let formerAnnouncementTime = min(4 * 0.55, performance.readableStartTime + 0.1)
        let updateDuration = max(0, min(4 * 0.65, performance.readableEndTime - 0.25))
        let currentAnnouncementTime = min(4, updateDuration + 0.01)
        let mergeTime = formerAnnouncementTime
            + (currentAnnouncementTime - formerAnnouncementTime) / 2
        try await Task.sleep(for: .seconds(mergeTime))
        try expect(announcements.isEmpty,
                   "Accessibility output waits until the active receipt's merge window closes")
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard, count: 2)),
                   "A receipt late in the update window merges before accessibility output")
        try await waitUntil(timeout: 3) { announcements.count == 1 }
        try expect(announcements == ["3 captures saved"]
                   && presenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 3)
                   && presenter.performanceStartCount == 1,
                   "The one accessibility announcement includes every receipt merged into the active sign")
        try await Task.sleep(for: .milliseconds(80))
        try expect(announcements.count == 1,
                   "An immediate merge never emits a stale or duplicate accessibility announcement")
    }

    private static func earlyMergeInterruptionChecks() throws {
        var clock = Date(timeIntervalSinceReferenceDate: 4_500)
        let presenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            currentDate: { clock },
            signDeck: AutoCaptureSignDeck(seed: 732),
            announce: { _ in }
        )
        defer { presenter.shutdown() }
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot)),
                   "The early-interruption fixture starts its first receipt")
        clock.addTimeInterval(0.05)
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard))
                   && presenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 2),
                   "A second receipt at 50 milliseconds merges into the active sign")
        clock.addTimeInterval(0.45)
        presenter.suspendForBoard()
        try expect(presenter.currentSignReceipt == nil
                   && presenter.pendingConfirmationCount == 2
                   && presenter.pendingConfirmationPerformances == 1,
                   "An interruption before readability preserves both early merged receipts")
        try expect(presenter.resumeAfterBoard()
                   && presenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 2)
                   && presenter.state.visibleCount == 2
                   && presenter.pendingConfirmationCount == 0,
                   "Resuming after the early interruption presents both retained receipts once")
    }

    private static func naturalCompletionChecks() async throws {
        var announcements: [String] = []
        let presenter = AutoCaptureRobotPresenter(
            primaryScreen: { external },
            reduceMotion: { true },
            signDeck: AutoCaptureSignDeck(seed: 733),
            announce: { announcements.append($0) }
        )
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard, count: 2)),
                   "The natural-completion fixture starts one reduced-motion typed receipt")
        try await waitUntil(timeout: 4) {
            !presenter.state.isVisible && !presenter.panel.isVisible
        }
        try expect(presenter.currentPerformance == nil
                   && presenter.currentSignPerformance == nil
                   && presenter.currentSignReceipt == nil
                   && presenter.signMessage == nil
                   && presenter.pendingConfirmationCount == 0
                   && presenter.pendingConfirmationPerformances == 0
                   && !presenter.signHasActiveAnimations
                   && presenter.performanceStartCount == 1
                   && announcements == ["2 clipboard captures saved"],
                   "Natural completion clears typed state and animation after one exact announcement")
        presenter.shutdown()
    }

    private static func interruptionChecks(_ interruption: Interruption,
                                           seed: UInt64) throws {
        var clock = Date(timeIntervalSinceReferenceDate: 4_000)
        let presenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            currentDate: { clock },
            signDeck: AutoCaptureSignDeck(seed: seed),
            announce: { _ in }
        )
        defer { presenter.shutdown() }
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot, count: 4)),
                   "The \(interruption.name) interruption starts with an unconsumed receipt")
        interruption.suspend(presenter)
        try expect(!presenter.state.isVisible
                   && !presenter.panel.isVisible
                   && presenter.currentSignPerformance == nil
                   && presenter.currentSignReceipt == nil
                   && presenter.signMessage == nil
                   && presenter.pendingConfirmationCount == 4
                   && presenter.pendingConfirmationPerformances == 1
                   && !presenter.signHasActiveAnimations,
                   "The \(interruption.name) interruption hides the panel and preserves the unconsumed receipt once")
        try expect(presenter.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard, count: 6))
                   && presenter.pendingConfirmationCount == 10
                   && presenter.pendingConfirmationPerformances == 1,
                   "Receipts arriving during the \(interruption.name) interruption merge into the same bounded pending performance")
        try expect(interruption.resume(presenter)
                   && presenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 10)
                   && presenter.state.visibleCount == 10
                   && presenter.signMessage == "Captures saved!"
                   && presenter.pendingConfirmationCount == 0
                   && presenter.pendingConfirmationPerformances == 0
                   && presenter.performanceStartCount == 2
                   && presenter.signHasActiveAnimations,
                   "Releasing the \(interruption.name) owner resumes one exact mixed confirmation")
        clock.addTimeInterval(0.01)
    }

    private static func displayAndScreenshotSuspensionChecks() throws {
        var clock = Date(timeIntervalSinceReferenceDate: 5_000)
        var screen: AutoCaptureRobotScreen? = builtIn
        let displayPresenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { screen },
            reduceMotion: { false },
            currentDate: { clock },
            signDeck: AutoCaptureSignDeck(seed: 78),
            announce: { _ in }
        )
        defer { displayPresenter.shutdown() }
        let panelIdentity = ObjectIdentifier(displayPresenter.panel)
        try expect(displayPresenter.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot, count: 2)),
                   "A display-loss sign starts on the synthetic built-in display")
        screen = nil
        displayPresenter.displayConfigurationChanged()
        try expect(!displayPresenter.panel.isVisible
                   && displayPresenter.currentSignReceipt == nil
                   && displayPresenter.pendingConfirmationCount == 2
                   && displayPresenter.pendingConfirmationPerformances == 1,
                   "Disconnecting every display hides the panel and preserves the unconsumed receipt")
        try expect(!displayPresenter.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard, count: 3))
                   && displayPresenter.pendingConfirmationCount == 5
                   && displayPresenter.pendingConfirmationPerformances == 1,
                   "A save with no display remains queued without guessing a presentation target")
        screen = external
        displayPresenter.displayConfigurationChanged()
        try expect(displayPresenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 5)
                   && displayPresenter.currentSignPerformance?.entrance == .right
                   && displayPresenter.state.visibleCount == 5
                   && displayPresenter.pendingConfirmationCount == 0
                   && displayPresenter.pendingConfirmationPerformances == 0
                   && displayPresenter.panel.isVisible
                   && ObjectIdentifier(displayPresenter.panel) == panelIdentity,
                   "Reconnecting an external display resumes the exact mixed receipt in the original passive panel")

        let capturePresenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { builtIn },
            reduceMotion: { false },
            currentDate: { clock },
            signDeck: AutoCaptureSignDeck(seed: 79),
            announce: { _ in }
        )
        defer { capturePresenter.shutdown() }
        try expect(AutoCaptureScreenshotActivity.isSystemCaptureTool("com.apple.screencaptureui")
                   && AutoCaptureScreenshotActivity.isSystemCaptureTool("COM.APPLE.SCREENCAPTUREUI")
                   && AutoCaptureScreenshotActivity.isSystemCaptureTool("com.apple.screenshot.launcher")
                   && !AutoCaptureScreenshotActivity.isSystemCaptureTool("com.apple.Preview")
                   && !AutoCaptureScreenshotActivity.isSystemCaptureTool(nil),
                   "Only the system screenshot UI activates the best-effort suspension signal")
        try expect(capturePresenter.present(confirmation: AutoCaptureSignReceipt(kind: .screenshot, count: 2)),
                   "The screenshot-UI fixture begins with a completed save receipt")
        capturePresenter.setScreenCaptureInProgress(true)
        capturePresenter.setScreenCaptureInProgress(true)
        try expect(capturePresenter.isSuspendedForScreenCapture
                   && !capturePresenter.panel.isVisible
                   && capturePresenter.currentSignReceipt == nil
                   && capturePresenter.pendingConfirmationCount == 2
                   && capturePresenter.pendingConfirmationPerformances == 1,
                   "Screenshot UI suspension hides once and preserves the completed unconsumed receipt")
        try expect(capturePresenter.present(confirmation: AutoCaptureSignReceipt(kind: .clipboard, count: 3))
                   && capturePresenter.pendingConfirmationCount == 5
                   && capturePresenter.pendingConfirmationPerformances == 1,
                   "Completed saves received during screenshot UI stay in one bounded pending receipt")
        capturePresenter.setScreenCaptureInProgress(false)
        let startsAfterResume = capturePresenter.performanceStartCount
        capturePresenter.setScreenCaptureInProgress(false)
        try expect(!capturePresenter.isSuspendedForScreenCapture
                   && capturePresenter.currentSignReceipt == AutoCaptureSignReceipt(kind: .mixed, count: 5)
                   && capturePresenter.state.visibleCount == 5
                   && capturePresenter.pendingConfirmationCount == 0
                   && capturePresenter.pendingConfirmationPerformances == 0
                   && capturePresenter.performanceStartCount == startsAfterResume,
                   "Screenshot UI dismissal resumes exactly once with every saved receipt")
        clock.addTimeInterval(0.01)
    }

    private static func staleTimerAndCleanupChecks() async throws {
        let presenter = AutoCaptureRobotPresenter(
            dismissDelay: 0.8,
            primaryScreen: { external },
            reduceMotion: { false },
            signDeck: AutoCaptureSignDeck(seed: 80),
            announce: { _ in }
        )
        let first = AutoCaptureSignReceipt(kind: .screenshot)
        let second = AutoCaptureSignReceipt(kind: .clipboard, count: 2)
        try expect(presenter.present(confirmation: first),
                   "The stale-timer fixture starts its first sign")
        try await Task.sleep(for: .milliseconds(250))
        presenter.dismiss()
        try expect(presenter.currentSignPerformance == nil
                   && presenter.currentSignReceipt == nil
                   && presenter.signMessage == nil
                   && presenter.pendingConfirmationPerformances == 0,
                   "Explicit dismissal synchronously clears readable sign state")
        try expect(presenter.present(confirmation: second),
                   "A second sign can begin while the first dismissal fade is stale")
        try await Task.sleep(for: .milliseconds(150))
        try expect(presenter.panel.isVisible
                   && presenter.currentSignReceipt == second
                   && presenter.currentSignPerformance != nil
                   && presenter.signHasActiveAnimations,
                   "The cancelled dismissal fade cannot order out a newer sign")
        try await Task.sleep(for: .milliseconds(500))
        try expect(presenter.panel.isVisible
                   && presenter.state.isVisible
                   && presenter.currentSignReceipt == second
                   && presenter.performanceStartCount == 2,
                   "The first performance's stale completion cannot clear the newer sign")
        presenter.shutdown()
        try expect(!presenter.panel.isVisible
                   && !presenter.state.isVisible
                   && presenter.currentSignPerformance == nil
                   && presenter.currentSignReceipt == nil
                   && presenter.signMessage == nil
                   && presenter.pendingConfirmationCount == 0
                   && presenter.pendingConfirmationPerformances == 0
                   && !presenter.signHasActiveAnimations
                   && !presenter.present(confirmation: AutoCaptureSignReceipt(kind: .mixed)),
                   "Shutdown clears every sign field and permanently rejects later confirmations")
        try await Task.sleep(for: .milliseconds(250))
        try expect(!presenter.panel.isVisible
                   && presenter.currentSignPerformance == nil
                   && presenter.currentSignReceipt == nil
                   && presenter.pendingConfirmationPerformances == 0
                   && !presenter.signHasActiveAnimations,
                   "Cancelled timers cannot resurrect sign state after shutdown")
    }

    private static func pngData() throws -> Data {
        guard let context = CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 5)
        }
        context.setFillColor(CGColor(red: 0.35, green: 0.18, blue: 0.62, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        guard let image = context.makeImage() else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 6)
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            result, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 7)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DaBinAutoCaptureSignPresenterTests", code: 8)
        }
        return result as Data
    }

    private static func serviceReceiptChecks() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appendingPathComponent("DaBin-Sign-Service-\(UUID().uuidString)", isDirectory: true)
        let screenshotFolder = root.appendingPathComponent("Screenshots", isDirectory: true)
        try files.createDirectory(at: screenshotFolder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let suite = "DaBin.Sign.Service.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let privateBoard = NSPasteboard(name: .init("DaBin.Sign.Private.\(UUID().uuidString)"))
        privateBoard.clearContents()
        defer { privateBoard.clearContents() }

        let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        let settings = AutoCaptureSettings(defaults: defaults, ownBundleIdentifier: "com.dabin.sign-tests")
        settings.setScreenshotFolderBookmark(Data("private-fixture-bookmark".utf8))
        settings.setClipboardEnabled(true)
        settings.setScreenshotsEnabled(true)
        let monitor = SignReceiptScreenshotMonitor()
        let service = AutoCaptureService(
            settings: settings,
            input: InputService(store: store),
            pasteboardProvider: { privateBoard },
            sourceApplicationProvider: {
                AutoCaptureSourceApplication(name: "Fixture", bundleIdentifier: "invalid.fixture.source")
            },
            screenshotMonitorFactory: { _ in monitor },
            bookmarkCreator: { Data($0.path.utf8) },
            bookmarkResolver: { _ in (screenshotFolder, false) },
            pollInterval: 60,
            clipboardImageDelay: .milliseconds(20),
            duplicateInterval: 0.1
        )
        defer { service.shutdown() }
        var receipts: [AutoCaptureSignReceipt] = []
        var failures: [String] = []
        service.onSaved = { action in
            if let receipt = AutoCaptureSignReceipt(savedAction: action) { receipts.append(receipt) }
        }
        service.onFailure = { failures.append($0) }
        service.start()
        try expect(service.isClipboardRunning && service.isScreenshotsRunning && monitor.isRunning,
                   "The service receipt fixture uses only its private clipboard and fake screenshot monitor")

        privateBoard.clearContents()
        privateBoard.setString("Private success fixture", forType: .string)
        service.pollNow()
        try await waitUntil { receipts.count == 1 }
        try expect(receipts == [AutoCaptureSignReceipt(kind: .clipboard)]
                   && store.captures.count == 1,
                   "A durable private clipboard action emits one typed confirmation receipt")

        let screenshot = screenshotFolder.appendingPathComponent("Private screenshot fixture.png")
        try pngData().write(to: screenshot, options: .atomic)
        monitor.emit(screenshot)
        try await waitUntil { receipts.count == 2 }
        try expect(receipts.last == AutoCaptureSignReceipt(kind: .screenshot)
                   && store.captures.count == 2,
                   "A durable fake-monitor screenshot emits one typed screenshot receipt")

        let receiptCount = receipts.count
        monitor.emit(screenshotFolder.appendingPathComponent("Missing screenshot fixture.png"))
        try await waitUntil { !failures.isEmpty }
        try expect(receipts.count == receiptCount,
                   "A failed screenshot import never emits a positive confirmation receipt")
    }

    static func main() async throws {
        try receiptFactoryChecks()
        try panelAndImmediateMergeChecks()
        try lateBurstQueueChecks()
        try await enablementAndReducedMotionChecks()
        try await announcementMergeChecks()
        try earlyMergeInterruptionChecks()
        try await naturalCompletionChecks()
        try interruptionChecks(.board, seed: 75)
        try interruptionChecks(.interaction, seed: 76)
        try interruptionChecks(.taskTimer, seed: 77)
        try displayAndScreenshotSuspensionChecks()
        try await staleTimerAndCleanupChecks()
        try await serviceReceiptChecks()
        print("PASS: \(checks) typed Auto Capture sign presenter, queue, interruption, privacy and service receipt checks")
    }
}
