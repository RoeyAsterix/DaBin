import AppKit
import Foundation

/// Pure controller and layout checks. These do not send global pointer events,
/// open the installed application, access an archive or change preferences.
@main
struct TooltipBehaviorTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool,
                                          _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinTooltipBehaviorTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func descriptor(_ id: String, text: String? = nil) -> TimelineTooltipDescriptor {
        TimelineTooltipDescriptor(id: id, text: text ?? id, index: 0, itemCount: 1)
    }

    @MainActor private static func settled() async throws {
        try await Task.sleep(for: .milliseconds(85))
    }

    @MainActor private static func controllerChecks() async throws {
        let first = descriptor("first", text: "Add capture")
        let second = descriptor("second", text: "Settings")
        let controller = TimelineTooltipController(delay: 0.035)
        try expect(controller.isEnabled && controller.visible == nil,
                   "Hover help starts enabled without showing an unsolicited tooltip")

        controller.begin(first)
        try expect(controller.visible == nil, "Pointer entry observes the configured dwell delay")
        try await settled()
        try expect(controller.visible == first, "A settled hover presents its descriptor")
        controller.end(id: first.id)
        try expect(controller.visible == nil, "Pointer exit dismisses a shown tooltip immediately")

        controller.begin(first)
        controller.begin(second)
        controller.end(id: first.id)
        try expect(controller.visible == nil,
                   "Moving between controls hides the previous tip during the new dwell")
        try await settled()
        try expect(controller.visible == second,
                   "The latest hover wins and a stale exit cannot cancel another control's pending tooltip")
        controller.end(id: "unrelated")
        try expect(controller.visible == second, "An unrelated exit does not dismiss the active control")
        controller.dismiss()

        controller.begin(first)
        controller.end(id: first.id)
        try await settled()
        try expect(controller.visible == nil, "Exiting before dwell cancels delayed presentation")

        controller.begin(first)
        controller.dismiss()
        try await settled()
        try expect(controller.visible == nil,
                   "Route, window or view dismissal cannot resurrect a pending tooltip")

        controller.begin(first, immediate: true)
        try expect(controller.visible == first, "Keyboard focus can present help without pointer dwell")
        controller.activate(id: first.id)
        try expect(controller.visible == nil, "Activation dismisses the control's currently shown tooltip")
        controller.begin(first, immediate: true)
        try expect(controller.visible == nil, "An activated control stays suppressed while still hovered or focused")
        controller.begin(first)
        try await settled()
        try expect(controller.visible == nil, "Delayed hover cannot bypass activation suppression")
        controller.end(id: first.id)
        controller.begin(first, immediate: true)
        try expect(controller.visible == first, "Leaving an activated control allows its next hover or focus")

        let changed = descriptor(first.id, text: "Capture saved — pause Auto Capture")
        controller.begin(changed)
        try expect(controller.visible == changed,
                   "Changing the active visible help updates its text without hiding or another delay")
        controller.begin(changed)
        try expect(controller.visible == changed,
                   "An unchanged active descriptor does not flicker or restart presentation")
        controller.dismiss()
        controller.begin(first)
        controller.begin(changed)
        try await settled()
        try expect(controller.visible == changed, "Updating pending help presents only its newest text")

        controller.setEnabled(false)
        try expect(!controller.isEnabled && controller.visible == nil,
                   "Disabling tooltips immediately removes a visible tip")
        controller.begin(first, immediate: true)
        controller.begin(second)
        controller.presentImmediately(second)
        try await settled()
        try expect(controller.visible == nil,
                   "Disabled help rejects pointer, focus and deterministic presentation paths")
        controller.setEnabled(true)
        controller.begin(first, immediate: true)
        try expect(controller.isEnabled && controller.visible == first,
                   "Re-enabling help permits a fresh focus or hover without replacing the controller")

        controller.dismiss()
        controller.begin(first)
        controller.setEnabled(false)
        try await settled()
        try expect(controller.visible == nil, "Disabling during dwell cancels the pending tooltip")
        controller.setEnabled(true)
        controller.begin(second)
        try await settled()
        try expect(controller.visible == second, "Delayed pointer help works again after re-enabling")
        controller.dismiss()

        controller.begin(first)
        controller.setPresentationActive(false)
        try await settled()
        try expect(!controller.isPresentationActive && controller.visible == nil,
                   "Hiding a mounted surface cancels its pending tooltip")
        controller.begin(first, immediate: true)
        controller.presentImmediately(second)
        try expect(controller.visible == nil, "A hidden surface rejects late focus and immediate presentation")
        controller.setEnabled(false)
        controller.setEnabled(true)
        controller.begin(first, immediate: true)
        try expect(controller.visible == nil, "Re-enabling the preference cannot show help on a hidden surface")
        controller.setPresentationActive(true)
        controller.begin(second, immediate: true)
        try expect(controller.visible == second, "A newly visible surface can present fresh help again")
        controller.dismiss()

        let immediate = TimelineTooltipController(delay: 0)
        immediate.begin(first)
        try expect(immediate.visible == first, "An explicitly zero delay presents synchronously")
        immediate.setEnabled(false)
        try expect(immediate.visible == nil, "Zero-delay help honors the same disable gate")
        immediate.setEnabled(true)
        immediate.presentImmediately(second)
        try expect(immediate.visible == second, "The visual QA hook presents only when enabled")
        immediate.dismiss()
        try expect(immediate.visible == nil, "Explicit dismissal clears deterministic presentation")
    }

    @MainActor private static func layoutChecks() throws {
        let container = CGSize(width: 380, height: 560)
        let topAnchor = CGRect(x: 174, y: 12, width: 32, height: 32)
        guard let top = HoverTooltipLayout.make(text: "Settings", anchor: topAnchor,
                                                containerSize: container) else {
            throw NSError(domain: "DaBinTooltipBehaviorTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "A visible top control requires a valid tooltip layout"])
        }
        try expect(top.pointsUp && top.frame.minY >= topAnchor.maxY + 6 - 0.001,
                   "A top control gets a downward bubble with its pointer facing upward")
        try expect(top.textHeight > 0 && top.frame.height > top.textHeight,
                   "The measured text has room for padding and the pointer")

        let bottomAnchor = CGRect(x: 174, y: 520, width: 32, height: 32)
        guard let bottom = HoverTooltipLayout.make(text: "Copy capture", anchor: bottomAnchor,
                                                   containerSize: container) else {
            throw NSError(domain: "DaBinTooltipBehaviorTests", code: 3)
        }
        try expect(!bottom.pointsUp && bottom.frame.maxY <= bottomAnchor.minY - 6 + 0.001,
                   "A bottom control flips its bubble upward instead of clipping it")

        let longText = Array(repeating: "A very long descriptive tooltip with spaces", count: 30).joined(separator: " ")
        for width: CGFloat in [260, 380, 1200] {
            let size = CGSize(width: width, height: 240)
            let safe = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            let anchors = [
                CGRect(x: 0, y: 8, width: 32, height: 32),
                CGRect(x: width - 32, y: 8, width: 32, height: 32),
                CGRect(x: width / 2 - 16, y: 104, width: 32, height: 32),
                CGRect(x: width - 32, y: 204, width: 32, height: 32)
            ]
            for anchor in anchors {
                guard let layout = HoverTooltipLayout.make(text: longText, anchor: anchor,
                                                            containerSize: size) else {
                    throw NSError(domain: "DaBinTooltipBehaviorTests", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "A visible edge control needs a clamped long-text tooltip"])
                }
                try expect(safe.contains(layout.frame),
                           "Long help stays inside the eight-point inset at \(width)-point width")
                try expect(layout.frame.width > 0 && layout.frame.width <= min(280, width - 16) + 0.001,
                           "Long help obeys both the compact-window and maximum bubble widths")
                try expect([layout.frame.minX, layout.frame.minY, layout.frame.width, layout.frame.height,
                            layout.pointerX, layout.textHeight].allSatisfy { $0.isFinite },
                           "All tooltip geometry remains finite")
                try expect(layout.pointerX >= 0 && layout.pointerX <= layout.frame.width,
                           "The clamped pointer remains inside its bubble rather than overflowing an edge")
                try expect(layout.textHeight > top.textHeight && layout.textHeight <= 60,
                           "Long descriptions wrap into a bounded number of readable lines")
            }
        }

        for text in ["", " \n\t "] {
            try expect(HoverTooltipLayout.make(text: text, anchor: topAnchor, containerSize: container) == nil,
                       "Empty or whitespace-only help does not create a blank bubble")
        }
        for anchor in [CGRect(x: -60, y: 12, width: 32, height: 32),
                       CGRect(x: 400, y: 12, width: 32, height: 32),
                       CGRect(x: 174, y: -60, width: 32, height: 32),
                       CGRect(x: 174, y: 580, width: 32, height: 32),
                       CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: CGFloat.nan, y: 12, width: 32, height: 32)] {
            try expect(HoverTooltipLayout.make(text: "Offscreen", anchor: anchor, containerSize: container) == nil,
                       "Offscreen, empty or invalid controls cannot show detached tooltip bubbles")
        }
        for size in [CGSize.zero, CGSize(width: 10, height: 10), CGSize(width: 380, height: 10),
                     CGSize(width: -1, height: 560), CGSize(width: CGFloat.infinity, height: 560)] {
            try expect(HoverTooltipLayout.make(text: "Settings", anchor: topAnchor, containerSize: size) == nil,
                       "Tiny or invalid containers do not produce clipped or nonfinite tooltip geometry")
        }
    }

    @MainActor private static func anchorPublicationChecks() throws {
        let id = "visible-control"
        for enabled in [false, true] {
            for controlEnabled in [false, true] {
                for hovered in [false, true] {
                    for focused in [false, true] {
                        for visibleID in [nil, "another-control", id] as [String?] {
                            let expected = enabled && controlEnabled && (hovered || focused || visibleID == id)
                            try expect(HoverTooltipAnchorPolicy.shouldPublish(id: id, visibleID: visibleID,
                                enabled: enabled, controlEnabled: controlEnabled, hovered: hovered, focused: focused) == expected,
                                "Anchor publication follows enabled control hover, focus, and exact visible identity")
                        }
                    }
                }
            }
        }
        let idleIDs = (0..<1_000).map { "idle-control-\($0)" }
        try expect(idleIDs.filter {
            HoverTooltipAnchorPolicy.shouldPublish(id: $0, visibleID: nil, enabled: true,
                controlEnabled: true, hovered: false, focused: false)
        }.isEmpty, "A thousand idle controls publish no global tooltip geometry")
        let selectedID = idleIDs[473]
        try expect(idleIDs.filter {
            HoverTooltipAnchorPolicy.shouldPublish(id: $0, visibleID: selectedID, enabled: true,
                controlEnabled: true, hovered: false, focused: false)
        } == [selectedID], "Explicit presentation requests geometry only for their exact control")
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try await controllerChecks()
        try layoutChecks()
        try anchorPublicationChecks()
        print("PASS: \(checks) tooltip delay, cancellation, preference, suppression, active-only anchors and clamped-layout checks")
    }
}
