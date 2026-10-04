import AppKit
import Foundation
import QuartzCore

/// Isolated native fixtures: no clipboard, real project, capture archive, global
/// pointer or installed application is accessed. Renders make grip/text QA visible.
@main struct RobotProjectSignRenderTests {
    @MainActor private static var checks = 0
    @MainActor private static var windows: [NSWindow] = []

    @MainActor private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "RobotProjectSignRenderTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func host(_ view: NSView) {
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000,
            width: view.frame.width, height: view.frame.height), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        window.orderFront(nil)
        windows.append(window)
    }

    @MainActor private static func render(_ view: NSView, name: String, directory: URL, scale: Int = 2) throws {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        view.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * CGFloat(scale)), pixelsHigh: Int(view.bounds.height * CGFloat(scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "RobotProjectSignRenderTests", code: 2)
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "RobotProjectSignRenderTests", code: 3)
        }
        try data.write(to: directory.appendingPathComponent(name + "@\(scale)x.png"), options: .atomic)
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        defer {
            for window in windows { window.orderOut(nil); window.contentView = nil; window.close() }
        }
        let directory = ProcessInfo.processInfo.environment["DABIN_RECORDING_SIGN_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: "../docs/qa/project-recording-sign-compact-2026-10-03/renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let corner = RobotView(frame: CGRect(x: 0, y: 0, width: 144, height: 112), reduceMotion: { true })
        corner.cornerCharacterFrame = CGRect(x: 36, y: 20, width: 72, height: 88)
        host(corner)
        corner.present(from: .right)
        corner.setProjectRecording(projectName: "Project Atlas", color: .systemTeal, isEnabled: true)
        try expect(corner.recordingSignIsVisible && corner.recordingSignFontSize == 12,
                   "Named project recording visibly holds a twelve-point board")
        try expect(corner.bounds.contains(corner.recordingSignFrame), "Corner board fits reserved stage")
        try expect(corner.recordingSignFrame.height == 24 && corner.recordingSignFrame.width < 128,
                   "The short project name uses a content-sized single-row plate")
        try expect(!corner.containsInteraction(CGPoint(x: 10, y: 10)),
                   "Expanded board space remains outside the robot mouse/drop destination")
        guard let sign = corner.subviews.compactMap({ $0 as? RobotProjectSignView }).first,
              let character = corner.subviews.compactMap({ $0 as? RobotCharacterView }).first else {
            throw NSError(domain: "RobotProjectSignRenderTests", code: 4)
        }
        try expect(sign.hasArmConnection && character.nativeArmsAreHidden,
                   "Visible grip hands and connected arms replace the greeting palms")
        try expect(abs(sign.leftGrip.y - sign.boardFrame.maxY) <= 1
                   && abs(sign.rightGrip.y - sign.boardFrame.maxY) <= 1,
                   "Both hands visibly overlap the top edge of the board")
        let projectLabels = sign.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }
        try expect(projectLabels.count == 1 && projectLabels[0].maximumNumberOfLines == 1
                   && projectLabels[0].lineBreakMode == .byTruncatingTail,
                   "Only the one-line project name consumes visible sign space")
        try expect(projectLabels[0].frame.width >= (projectLabels[0].cell?.cellSize.width ?? .infinity),
                   "An ordinary project name fits completely, including native text-cell insets")
        try render(corner, name: "corner-recording", directory: directory)
        try render(corner, name: "corner-recording", directory: directory, scale: 1)
        let shortNameWidth = corner.recordingSignFrame.width

        corner.setProjectRecording(projectName: "A", color: .systemTeal, isEnabled: true)
        try expect(corner.recordingSignFrame.width < shortNameWidth
                   && projectLabels[0].frame.width >= (projectLabels[0].cell?.cellSize.width ?? .infinity),
                   "A one-letter name fits in a snug plate without a fixed minimum width")
        try render(corner, name: "corner-short-name", directory: directory)
        try render(corner, name: "corner-short-name", directory: directory, scale: 1)

        corner.setProjectRecording(projectName: "Project Atlas", color: .systemTeal,
                                   isEnabled: true, isPaused: true)
        corner.layoutSubtreeIfNeeded()
        try expect(!corner.recordingSignIsVisible && corner.recordingProjectName == nil
                   && corner.recordingStatusLabel == nil && !character.nativeArmsAreHidden,
                   "Paused recording removes the sign and restores the robot's native arms")
        corner.present(from: .right)
        try expect(!corner.recordingSignIsVisible,
                   "An ordinary reveal cannot resurrect a paused recording board")
        try render(corner, name: "corner-paused", directory: directory)
        corner.setProjectRecording(projectName: "Project Atlas", color: .systemTeal,
                                   isEnabled: true, isPaused: false)
        try expect(corner.recordingSignIsVisible && character.nativeArmsAreHidden,
                   "Resuming reinstates the compact board and connected sign arms")
        corner.setProjectRecording(projectName: "Project Atlas — International Research and Production",
                                   color: .systemOrange, isEnabled: true)
        try expect(corner.recordingSignFontSize == 12
                   && corner.recordingSignFrame.width > shortNameWidth
                   && corner.recordingSignFrame.width <= corner.bounds.width - 8,
                   "Long titles grow to the safe width cap and truncate without shrinking the font")
        try render(corner, name: "corner-long-title", directory: directory)
        corner.hideCharacter()
        try expect(!corner.recordingSignIsVisible && corner.recordingProjectName != nil,
                   "Temporary hiding retains the session destination")
        corner.present(from: .right)
        try expect(corner.recordingSignIsVisible, "A reveal restores the held recording board")
        corner.digest(success: true)
        try expect(corner.recordingSignIsVisible && character.nativeArmsAreHidden,
                   "Receipt feedback cannot remove the held project board or reintroduce extra palms")
        corner.stopFeedback()
        corner.present(from: .right)
        corner.setProjectRecording(projectName: "Project Atlas", color: nil, isEnabled: false)
        try expect(corner.recordingProjectName == nil && !corner.recordingSignIsVisible
                   && !character.nativeArmsAreHidden, "Recording off clears board and restores normal arms")
        corner.setProjectRecording(projectName: "  ", color: .systemTeal, isEnabled: true)
        try expect(!corner.recordingSignIsVisible && corner.recordingProjectName == nil,
                   "An empty destination never creates a recording placard")

        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let camera = CGRect(x: 648, y: 866, width: 144, height: 34)
        guard let layout = QuietOrbitLayout(cameraIsland: camera, displayFrame: display) else {
            throw NSError(domain: "RobotProjectSignRenderTests", code: 5)
        }
        for perch in QuietOrbitPerch.allCases {
            let stage = RobotView(frame: CGRect(origin: .zero,
                size: CGSize(width: layout.panelFrame.width, height: layout.panelFrame.height + 24)),
                reduceMotion: { true })
            stage.orbitContentOffset = CGPoint(x: 0, y: 24)
            host(stage)
            stage.revealOrbit(in: layout, at: perch)
            stage.setProjectRecording(projectName: "Atlas שלום 未来", color: .systemPurple, isEnabled: true)
            try expect(stage.recordingSignIsVisible && stage.recordingSignFontSize == 12,
                       "Each physical camera perch displays upright fixed-size project text")
            try expect(stage.bounds.contains(stage.recordingSignFrame), "Perch board is not clipped: \(perch)")
            let cameraLocal = layout.cameraFrameInPanel.offsetBy(dx: 0, dy: 24)
            try expect(!stage.recordingSignFrame.intersects(cameraLocal),
                       "Physical camera cannot obscure project title: \(perch)")
            try expect(!stage.containsInteraction(CGPoint(x: cameraLocal.midX, y: cameraLocal.midY)),
                       "Expanded recording stage keeps hardware excluded from input")
            if let sign = stage.subviews.compactMap({ $0 as? RobotProjectSignView }).first {
                try expect(sign.layer?.affineTransform().a == 1,
                           "Mirrored robot artwork never mirrors the project board")
            }
            try await Task.sleep(for: .milliseconds(180))
            try render(stage, name: "orbit-" + perch.rawValue, directory: directory)
        }

        let compact = RobotProjectSignView(frame: CGRect(x: 0, y: 0, width: 144, height: 40))
        compact.configure(projectName: "Project Atlas", color: .systemTeal, isPaused: false)
        compact.updateAttachment(boardFrame: CGRect(x: 14, y: 6, width: 116, height: 23),
            leftShoulder: CGPoint(x: 8, y: 30), rightShoulder: CGPoint(x: 136, y: 30), armWidth: 3)
        host(compact)
        try expect(compact.fontSize == 12 && compact.hasArmConnection,
                   "Compact chrome board preserves the same live twelve-point title and grip")
        try render(compact, name: "compact-chrome", directory: directory)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        let fullBoard = RobotAppFrameView(contentView: content)
        fullBoard.frame = CGRect(x: 0, y: 0, width: 400, height: 670)
        host(fullBoard)
        fullBoard.cancelTransition(open: true)
        fullBoard.setProjectRecording(projectName: "Project Atlas", color: .systemTeal,
                                      isEnabled: true, statusText: "Capturing to")
        fullBoard.layoutSubtreeIfNeeded()
        try expect(fullBoard.recordingSignIsVisible && fullBoard.recordingSignFontSize == 12,
                   "Open board robot retains a live twelve-point recording destination")
        try expect(!fullBoard.recordingSignFrame.intersects(RobotAppFrameView.contentRect(in: fullBoard.bounds)),
                   "The held chrome board leaves application content unobstructed")
        try render(fullBoard, name: "full-board-recording", directory: directory)
        fullBoard.setProjectRecording(projectName: "Project Atlas", color: .systemTeal,
                                      isEnabled: true, isPaused: true)
        fullBoard.layoutSubtreeIfNeeded()
        try expect(!fullBoard.recordingSignIsVisible && fullBoard.recordingProjectName == nil,
                   "Pausing removes the open-frame board even after another layout pass")
        try render(fullBoard, name: "full-board-paused", directory: directory)
        fullBoard.setProjectRecording(projectName: "Project Atlas", color: .systemTeal,
                                      isEnabled: true, isPaused: false)
        try expect(fullBoard.recordingSignIsVisible,
                   "Resuming restores the open-frame board without an app transition")

        let timer = TaskTimerRobotView(frame: CGRect(origin: .zero, size: TaskTimerRobotView.stageSize),
                                       reduceMotion: { true })
        host(timer)
        timer.setProjectRecording(projectName: "Project Atlas", isPaused: false)
        timer.show(taskTitle: "Review design", reduceMotion: true)
        try expect(timer.recordingProjectName == "Project Atlas" && timer.recordingSignFontSize == 12,
                   "The task alarm's physically held board also retains the twelve-point project destination")
        try render(timer, name: "timer-recording", directory: directory)
        timer.reset()
        timer.show(taskTitle: "Review next draft", reduceMotion: true)
        try expect(timer.recordingProjectName == "Project Atlas" && timer.recordingSignFontSize == 12,
                   "Reset and the next alarm preserve persistent recording destination")
        timer.setProjectRecording(projectName: "Project Atlas", isPaused: true)
        try expect(timer.recordingProjectName == nil
                   && timer.accessibilityLabel()?.contains("Recording paused for") != true
                   && timer.accessibilityLabel()?.contains("Recording to") != true,
                   "The paused alarm retains its task but removes recording destination claims")
        try render(timer, name: "timer-paused", directory: directory)
        timer.setProjectRecording(projectName: "Project Atlas", isPaused: false)
        try expect(timer.recordingProjectName == "Project Atlas",
                   "Resuming reinstates the timer's recording line")
        timer.setProjectRecording(projectName: nil, isPaused: false)
        try expect(timer.recordingProjectName == nil, "Recording off clears the alarm's project line")
        try render(timer, name: "timer-recording-off", directory: directory)
        print("PASS: \(checks) native recording-board checks; renders: \(directory.path)")
    }
}
