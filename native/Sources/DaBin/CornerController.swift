import AppKit
import SwiftUI
import Combine

enum ScreenCorner: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight
    var isRight: Bool { self == .bottomRight || self == .topRight }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

enum RobotRevealTarget: Equatable {
    case corner(ScreenCorner)
    case cameraIsland
}

enum CornerGeometry {
    /// Preserve the compact single-line size, while leaving enough initial
    /// room for visible card content and its capture actions. Taller boards
    /// still cap at 500 points and scroll within the available screen space.
    @MainActor static func dailyPanelHeight(for state: AppState) -> CGFloat {
        let extra: CGFloat = state.status != nil || state.store.error != nil ? 45 : 0
        let captures = state.dailyCaptures
        guard !captures.isEmpty else { return 290 + extra }
        let feed = HourlyCaptureFeed.cards(from: state.allCapturesForDay, filter: state.filter)
        let featuredID = feed.compactMap { item -> CaptureCardGroup? in
            if case .capture(let card) = item { return card }
            return nil
        }.first { !$0.isImportedBatch && !$0.primary.isMinimized
            && $0.primary.thumbnailRelativePath != nil }?.primary.id

        func cardHeight(_ card: CaptureCardGroup, includesSingleFrameSpacing: Bool = true) -> CGFloat {
            if card.isImportedBatch {
                if card.isMinimized { return 88 }
                var height = CGFloat(92 + card.captures.count * 58)
                if !card.primary.comment.isEmpty { height += 30 }
                if card.primary.reminderAt != nil { height += 22 }
                return height
            }
            let capture = card.primary
            let promoted = state.isTaskAtTop(capture)
            // Top-level single-caption cards include six points of breathing
            // room on each side of their rounded frame. Automatic-hour actions
            // supply their own outer card and omit this spacing.
            let frameSpacing: CGFloat = includesSingleFrameSpacing ? 12 : 0
            // The minimized row still keeps its action controls inside the
            // frame, so reserve enough room for the complete rounded bottom
            // edge above the board footer.
            var height: CGFloat = (capture.isMinimized ? 112 : 118) + frameSpacing
            if promoted { height += 32 }
            if capture.isMinimized {
                if capture.isTask { height += 12 }
                return height
            }
            let featured = capture.id == featuredID
            let titleSize: CGFloat = featured ? 19.55 : 16.1
            let timestampWidth: CGFloat = capture.isTask ? (capture.isCompleted ? 98 : 66) : 44
            let thumbnailWidth: CGFloat = !featured && capture.kind != .text && !capture.isTask ? 67 : 0
            let contentWidth: CGFloat = 348 - (promoted ? 20 : 0)
            let titleWidth = max(100, contentWidth - timestampWidth - 11 - thumbnailWidth)
            let titleFont = NSFont.systemFont(ofSize: titleSize, weight: .medium)
            let lineHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
            let titleHeight = measuredTextHeight(capture.title.isEmpty ? "Untitled capture" : capture.title,
                                                font: titleFont, width: titleWidth, maximumLines: 3)
            height += max(0, titleHeight - lineHeight)
            if !capture.previewDescription.isEmpty {
                height += measuredTextHeight(capture.previewDescription, font: .systemFont(ofSize: 12),
                                             width: titleWidth, maximumLines: 2) + 4
            }
            if !capture.comment.isEmpty {
                height += measuredTextHeight(capture.comment, font: .systemFont(ofSize: 12),
                                             width: contentWidth, maximumLines: 2) + 7
            }
            if capture.reminderAt != nil { height += 22 }
            if capture.kind == .link && !promoted { height += 18 }
            return height
        }

        let rows = feed.reduce(CGFloat.zero) { total, item in
            switch item {
            case .capture(let card):
                return total + cardHeight(card)
            case .automaticHour(let group):
                guard state.isHourlyGroupExpanded(group.id) else { return total + 66 }
                let actions = group.actions.reduce(CGFloat.zero) { partial, action in
                    partial + action.cards.reduce(CGFloat.zero) {
                        $0 + cardHeight($1, includesSingleFrameSpacing: false)
                    } + 34
                }
                return total + 58 + actions
            }
        }
        return min(500, 155 + rows + (featuredID == nil ? 0 : 125) + extra)
    }

    private static func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat, maximumLines: Int) -> CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let bounds = (text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: font])
        return min(CGFloat(maximumLines) * lineHeight, max(lineHeight, ceil(bounds.height)))
    }

    static func corner(at point: NSPoint, in frame: NSRect, threshold: CGFloat = 9) -> ScreenCorner? {
        guard frame.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        let left = point.x <= frame.minX + threshold
        let right = point.x >= frame.maxX - threshold
        let bottom = point.y <= frame.minY + threshold
        let top = point.y >= frame.maxY - threshold
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left && top { return .topLeft }
        if right && top { return .topRight }
        return nil
    }

    /// The physical camera cutout is the gap between macOS' two usable menu-bar
    /// areas. Display names and model lists are intentionally not used.
    static func cameraIslandRect(frame: NSRect, safeAreaTop: CGFloat,
                                 auxiliaryLeft: NSRect?, auxiliaryRight: NSRect?) -> NSRect? {
        guard safeAreaTop.isFinite, safeAreaTop > 0,
              let left = auxiliaryLeft, let right = auxiliaryRight,
              left.maxX.isFinite, right.minX.isFinite,
              right.minX - left.maxX >= 24 else { return nil }
        let bottom = max(frame.minY, frame.maxY - safeAreaTop)
        let candidate = NSRect(x: left.maxX, y: bottom,
                               width: right.minX - left.maxX,
                               height: min(safeAreaTop, frame.height))
        guard candidate.width > 0, candidate.height > 0,
              frame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: candidate.midX, y: candidate.midY)) else { return nil }
        return candidate
    }

    static func cameraIslandRect(on screen: NSScreen) -> NSRect? {
        cameraIslandRect(frame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                         auxiliaryLeft: screen.auxiliaryTopLeftArea,
                         auxiliaryRight: screen.auxiliaryTopRightArea)
    }

    static func cameraIslandTriggerFrame(on screen: NSScreen) -> NSRect? {
        cameraIslandRect(on: screen).map {
            $0.insetBy(dx: -10, dy: 0).union(NSRect(x: $0.minX - 10, y: $0.minY - 12,
                                                   width: $0.width + 20, height: 12))
        }
    }

    static func revealTarget(at point: NSPoint, on screen: NSScreen, home: RobotHome) -> RobotRevealTarget? {
        if home == .cameraIsland, let trigger = cameraIslandTriggerFrame(on: screen) {
            return trigger.contains(point) ? .cameraIsland : nil
        }
        return corner(at: point, in: screen.frame).map(RobotRevealTarget.corner)
    }

    static func robotFrame(corner: ScreenCorner, visible: NSRect) -> NSRect {
        let size = NSSize(width: min(72, visible.width), height: min(88, visible.height))
        return NSRect(x: corner.isRight ? visible.maxX - size.width - 3 : visible.minX + 3,
                      y: corner.isTop ? visible.maxY - size.height - 3 : visible.minY + 3,
                      width: size.width, height: size.height)
    }

    static func robotFrame(cameraIsland: NSRect, visible: NSRect) -> NSRect {
        let size = NSSize(width: min(72, visible.width), height: min(88, visible.height))
        // Borderless NSWindows resolve their origin to whole display points.
        // Match that placement up front so geometry and the actual panel agree.
        let idealX = floor(cameraIsland.midX - size.width / 2)
        return NSRect(x: min(max(idealX, visible.minX), visible.maxX - size.width),
                      y: max(visible.minY, visible.maxY - size.height - 3),
                      width: size.width, height: size.height)
    }

    static func robotFrame(target: RobotRevealTarget, on screen: NSScreen) -> NSRect {
        switch target {
        case .corner(let corner): return robotFrame(corner: corner, visible: screen.visibleFrame)
        case .cameraIsland:
            let island = cameraIslandRect(on: screen)
                ?? NSRect(x: screen.frame.midX, y: screen.visibleFrame.maxY, width: 0, height: 0)
            return robotFrame(cameraIsland: island, visible: screen.visibleFrame)
        }
    }

    static func panelFrame(robot: NSRect, visible: NSRect, corner: ScreenCorner, preferredHeight: CGFloat = 500) -> NSRect {
        let width = min(380, max(260, visible.width - 16))
        let height = min(preferredHeight, max(240, visible.height - 16))
        var frame = NSRect(x: corner.isRight ? robot.maxX - width : robot.minX,
                           y: corner.isTop ? robot.minY - height - 6 : robot.maxY + 6,
                           width: min(width, visible.width), height: min(height, visible.height))
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    static func panelFrame(robot: NSRect, visible: NSRect, target: RobotRevealTarget,
                           preferredHeight: CGFloat = 500) -> NSRect {
        guard target == .cameraIsland else {
            if case .corner(let corner) = target {
                return panelFrame(robot: robot, visible: visible, corner: corner, preferredHeight: preferredHeight)
            }
            return panelFrame(robot: robot, visible: visible, corner: .bottomRight, preferredHeight: preferredHeight)
        }
        let width = min(380, max(260, visible.width - 16))
        let height = min(preferredHeight, max(240, visible.height - 16))
        var frame = NSRect(x: robot.midX - width / 2, y: robot.minY - height - 6,
                           width: min(width, visible.width), height: min(height, visible.height))
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    /// Keep the header at the user's chosen point when the board changes height.
    static func movedPanelFrame(topLeft: NSPoint, visible: NSRect, preferredHeight: CGFloat) -> NSRect {
        let size = panelFrame(robot: .zero, visible: visible, corner: .bottomLeft, preferredHeight: preferredHeight).size
        return NSRect(x: min(max(topLeft.x, visible.minX), visible.maxX - size.width),
                      y: min(max(topLeft.y - size.height, visible.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }

    /// A filtered board keeps its header still. Extra content scrolls when
    /// there is no more room below the header on this display.
    static func filterPanelFrame(current: NSRect, visible: NSRect, preferredHeight: CGFloat) -> NSRect {
        let width = min(max(0, current.width), max(0, visible.width))
        let top = min(max(current.maxY, visible.minY), visible.maxY)
        let height = min(max(0, preferredHeight), max(0, top - visible.minY))
        return NSRect(x: min(max(current.minX, visible.minX), visible.maxX - width),
                      y: top - height, width: width, height: height)
    }

    static func shouldAnimateFilterTransition(from previous: BoardRoute?, to next: BoardRoute,
                                             previousFilter: CaptureFilter?, filter: CaptureFilter,
                                             visible: Bool, reduceMotion: Bool) -> Bool {
        visible && !reduceMotion && previous == next && (next == .daily || next == .search)
            && previousFilter != nil && previousFilter != filter
    }

    /// Open away from the closest display edge. The compact board's edge stays
    /// fixed whenever the display has enough room for the expanded view.
    static func weeklyExpansionDirection(compact: NSRect, visible: NSRect) -> WeeklyExpansionDirection {
        let leftRoom = max(0, compact.minX - visible.minX)
        let rightRoom = max(0, visible.maxX - compact.maxX)
        return leftRoom > rightRoom ? .left : .right
    }

    static func weeklyPanelFrame(compact: NSRect, visible: NSRect, direction: WeeklyExpansionDirection,
                                 preferredHeight: CGFloat = 560) -> NSRect {
        let width = min(1440, max(0, visible.width - 16))
        let height = min(preferredHeight, max(0, visible.height - 16))
        let x = direction == .left ? compact.maxX - width : compact.minX
        return NSRect(x: min(max(x, visible.minX), visible.maxX - width),
                      y: min(max(compact.maxY - height, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }

    static func compactTopLeft(weeklyFrame: NSRect, compactWidth: CGFloat, direction: WeeklyExpansionDirection) -> NSPoint {
        NSPoint(x: direction == .left ? weeklyFrame.maxX - compactWidth : weeklyFrame.minX,
                y: weeklyFrame.maxY)
    }

    static func shouldAnimateWeeklyTransition(from previous: BoardRoute?, to next: BoardRoute,
                                             visible: Bool, reduceMotion: Bool) -> Bool {
        visible && !reduceMotion && previous != nil && previous != next && (previous == .weekly || next == .weekly)
    }
}

class DaBinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CornerController: NSObject {
    let state: AppState
    let input: InputService
    let robot = RobotView(frame: NSRect(x: 0, y: 0, width: 72, height: 88))
    let bin: DaBinPanel
    let board: DailyCapturePanel
    private var timer: Timer?
    private(set) var isShutDown = false
    private var activeScreen: NSScreen?
    private var activeTarget: RobotRevealTarget = .corner(.bottomRight)
    private var dragActive = false
    private var saving = false
    private var lastInteraction = Date.distantPast
    private var feedbackUntil = Date.distantPast
    private var keyboardHold = false
    private var hoverFocus = false
    private var focusPoint = NSPoint.zero
    private var suppressUntilExit = false
    private var escapeMonitor: Any?
    private var message: NSPopover?
    private var layoutSubscription: AnyCancellable?
    private var placementSubscription: AnyCancellable?
    private let placementDefaults: UserDefaults?
    private var boardTopLeft: NSPoint?
    private var boardDragStartFrame: NSRect?
    private var boardDragTimer: Timer?
    private var applyingBoardFrame = false
    private var lastAppliedBoardFrame: NSRect?
    private var lastLayoutRoute: BoardRoute?
    private var lastLayoutFilter: CaptureFilter?
    private var weeklyDirection: WeeklyExpansionDirection?
    private var boardFrameAnimation: Timer?
    private var boardAnimationTarget: NSRect?
    private enum BoardFrameAnimationKind: Equatable { case weekly, filter }
    private var boardAnimationKind: BoardFrameAnimationKind?
    static let filterResizeDuration: TimeInterval = 0.38
    static let boardPlacementKey = "DaBin.boardTopLeft.v1"

    init(state: AppState, input: InputService, placementDefaults: UserDefaults? = .standard, theme: ThemeSettings? = nil) {
        self.state = state; self.input = input
        self.placementDefaults = placementDefaults
        if let point = placementDefaults?.array(forKey: Self.boardPlacementKey) as? [Double],
           point.count == 2, point.allSatisfy({ $0.isFinite }) {
            boardTopLeft = NSPoint(x: point[0], y: point[1])
        }
        bin = DaBinPanel(contentRect: NSRect(x: 0, y: 0, width: 72, height: 88), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        board = DailyCapturePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 500), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        configure(bin, shadow: false)
        configure(board, shadow: true)
        bin.title = "DaBin robot"
        board.title = "DaBin Daily"
        bin.contentView = robot
        let hosting = DailyCaptureHostingView(state: state, theme: theme)
        board.contentView = hosting
        hosting.onPaste = { [weak self] in self?.receiveOnDaily(.general) }
        hosting.onDrop = { [weak self] pasteboard in self?.receiveOnDaily(pasteboard) }
        hosting.onDragState = { [weak state] active in
            if state?.isDailyDropTargeted != active { state?.isDailyDropTargeted = active }
        }
        robot.onPaste = { [weak self] in self?.input.paste() }
        robot.onDaily = { [weak self] in self?.openDaily() }
        robot.onDrop = { [weak self] pasteboard in self?.input.receive(pasteboard) }
        robot.onDragState = { [weak self] active in
            self?.dragActive = active
            self?.lastInteraction = Date()
            self?.updateHoverFocus(at: NSEvent.mouseLocation, pressedMouseButtons: NSEvent.pressedMouseButtons)
        }
        robot.onHoverChange = { [weak self] in
            self?.updateHoverFocus(at: NSEvent.mouseLocation, pressedMouseButtons: NSEvent.pressedMouseButtons)
        }
        robot.onFocus = { [weak self] in self?.keyboardHold = true; self?.focusPoint = NSEvent.mouseLocation; self?.lastInteraction = Date() }
        input.onBusy = { [weak self] busy in
            self?.saving = busy; self?.robot.isSaving = busy
        }
        input.onResult = { [weak self] captures, errors in self?.received(captures, errors: errors) }
        state.onDismiss = { [weak self] in self?.dismiss() }
        state.onBoardDragStarted = { [weak self] in self?.beginBoardDrag() }
        layoutSubscription = state.objectWillChange.debounce(for: .milliseconds(40), scheduler: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.resizeBoard() }
        }
        placementSubscription = state.robotPlacement.$home.dropFirst().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.robotHomeChanged() }
        }
        state.reminders.onOpenCapture = { [weak self] id in
            self?.state.openCapture(id); self?.showBoard()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(boardMoved), name: NSWindow.didMoveNotification, object: board)
        NotificationCenter.default.addObserver(self, selector: #selector(updateBoardVisibility), name: NSWindow.didChangeOcclusionStateNotification, object: board)
        NotificationCenter.default.addObserver(self, selector: #selector(updateBoardVisibility), name: NSApplication.didHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateBoardVisibility), name: NSApplication.didUnhideNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, event.window === self?.board || event.window === self?.bin {
                // Let native popovers/pickers handle their own Escape first.
                self?.dismiss(); return nil
            }
            return event
        }
    }

    private func configure(_ panel: NSPanel, shadow: Bool) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = shadow
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
    }

    func start(pointerPosition: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        guard timer == nil, !isShutDown else { return }
        // Global pointer position needs no global key monitor, clipboard poll or Accessibility grant.
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPointer(at: pointerPosition()) }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One-way disposal removes every native event source owned by this session.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        timer?.invalidate(); timer = nil
        boardDragTimer?.invalidate(); boardDragTimer = nil
        stopBoardAnimation()
        layoutSubscription?.cancel(); layoutSubscription = nil
        placementSubscription?.cancel(); placementSubscription = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        message?.close(); message = nil
        if let hosting = board.contentView as? DailyCaptureHostingView {
            hosting.clearDropTarget()
            hosting.onPaste = nil; hosting.onDrop = nil; hosting.onDragState = nil
        }
        robot.onPaste = nil; robot.onDaily = nil; robot.onDrop = nil
        robot.onDragState = nil; robot.onHoverChange = nil; robot.onFocus = nil
        robot.stopFeedback()
        input.onBusy = nil; input.onResult = nil
        state.onDismiss = nil; state.onBoardDragStarted = nil
        state.reminders.onOpenCapture = nil
        board.orderOut(nil); bin.orderOut(nil)
        state.isBoardVisible = false; state.isDailyDropTargeted = false
        board.contentView = nil; bin.contentView = nil
        board.close(); bin.close()
    }

    func pollPointer(at simulatedPoint: NSPoint? = nil, now: Date = Date(), pressedMouseButtons: Int = NSEvent.pressedMouseButtons) {
        guard !isShutDown else { return }
        let point = simulatedPoint ?? NSEvent.mouseLocation
        let target = NSScreen.screens.compactMap { screen -> (NSScreen, RobotRevealTarget)? in
            guard let target = CornerGeometry.revealTarget(at: point, on: screen,
                                                           home: state.robotPlacement.home) else { return nil }
            return (screen, target)
        }.first
        if target == nil { suppressUntilExit = false }
        // A file or text drag can reach the robot while the board stays open.
        // Moving DaBin's own header must not reveal a second surface.
        let draggingTowardCorner = pressedMouseButtons & 1 != 0 && boardDragStartFrame == nil
        if let (screen, target) = target, !suppressUntilExit,
           (!board.isVisible || draggingTowardCorner), !saving, !dragActive {
            keyboardHold = false
            reveal(on: screen, target: target)
            updateHoverFocus(at: point, pressedMouseButtons: pressedMouseButtons)
            lastInteraction = now
            return
        }
        guard bin.isVisible else { return }
        updateHoverFocus(at: point, pressedMouseButtons: pressedMouseButtons)
        var corridor = bin.frame.insetBy(dx: -12, dy: -12)
        if let screen = activeScreen {
            switch activeTarget {
            case .corner(let corner):
                let cornerPoint = NSPoint(x: corner.isRight ? screen.frame.maxX : screen.frame.minX,
                                          y: corner.isTop ? screen.frame.maxY : screen.frame.minY)
                corridor = corridor.union(NSRect(x: cornerPoint.x - 9, y: cornerPoint.y - 9, width: 18, height: 18))
            case .cameraIsland:
                if let trigger = CornerGeometry.cameraIslandTriggerFrame(on: screen) {
                    corridor = corridor.union(trigger)
                }
            }
        }
        if corridor.contains(point) || dragActive || saving {
            lastInteraction = now; return
        }
        if keyboardHold && bin.isKeyWindow && hypot(point.x - focusPoint.x, point.y - focusPoint.y) < 4 { return }
        keyboardHold = false
        // The grace interval lets the pointer cross menu-bar / Dock insets onto the robot.
        if now > feedbackUntil, now.timeIntervalSince(lastInteraction) > 0.8 {
            hideRobot()
        }
    }

    private func updateHoverFocus(at point: NSPoint, pressedMouseButtons: Int) {
        let localPoint = robot.convert(bin.convertPoint(fromScreen: point), from: nil)
        let hovering = bin.isVisible && !board.isVisible && !dragActive && pressedMouseButtons == 0
            && robot.bounds.insetBy(dx: 4, dy: 4).contains(localPoint)
        if hovering {
            guard !hoverFocus else { return }
            hoverFocus = true
            // A nonactivating panel accepts keys without activating DaBin or
            // observing other applications' keyboard events.
            bin.makeKey()
            bin.makeFirstResponder(robot)
        } else {
            releaseHoverFocus()
        }
    }

    private func releaseHoverFocus() {
        // Ordering the destination out in a drag callback can cancel AppKit's
        // transfer. Release any previous hover focus after the drag ends.
        guard !dragActive else { return }
        guard hoverFocus else { return }
        hoverFocus = false
        guard !keyboardHold, bin.isVisible, bin.isKeyWindow else { return }
        // Ordering out releases a nonactivating panel's keyboard focus. Bring
        // the peek back without key status for the existing retreat grace.
        // NSWindow.resignKey() is an override hook, not a callable focus API.
        bin.orderOut(nil)
        bin.orderFrontRegardless()
    }

    func reveal(on screen: NSScreen, corner: ScreenCorner, focus: Bool = false) {
        reveal(on: screen, target: .corner(corner), focus: focus)
    }

    func reveal(on screen: NSScreen, target: RobotRevealTarget, focus: Bool = false) {
        guard !isShutDown else { return }
        let frame = CornerGeometry.robotFrame(target: target, on: screen)
        let changed = activeScreen != screen || activeTarget != target
        if changed { releaseHoverFocus() }
        // A new drop corner must not relocate an already-open board when the
        // incoming capture resizes it. This is only an in-memory anchor; the
        // user's saved placement still changes exclusively through header drag.
        if board.isVisible, boardTopLeft == nil {
            boardTopLeft = NSPoint(x: board.frame.minX, y: board.frame.maxY)
        }
        activeScreen = screen; activeTarget = target
        if !bin.isVisible || changed {
            let entering = !bin.isVisible
            bin.setFrame(frame, display: true)
            bin.alphaValue = 1
            bin.orderFrontRegardless()
            if entering || changed {
                let entrance: RobotEntrance
                switch target {
                case .corner(let corner): entrance = corner.isRight ? .right : .left
                case .cameraIsland: entrance = .top
                }
                robot.present(from: entrance)
            }
        }
        if focus {
            keyboardHold = true
            focusPoint = NSEvent.mouseLocation
            NSApp.activate(ignoringOtherApps: true)
            bin.makeKeyAndOrderFront(nil)
            bin.makeFirstResponder(robot)
        }
    }

    func focusRobot() {
        guard !isShutDown else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        board.orderOut(nil)
        state.isBoardVisible = false
        let target: RobotRevealTarget = state.robotPlacement.home == .cameraIsland
            && CornerGeometry.cameraIslandRect(on: screen) != nil ? .cameraIsland : .corner(.bottomRight)
        reveal(on: screen, target: target, focus: true)
        lastInteraction = Date()
    }

    func openDaily() { state.openDaily(); showBoard() }
    func openSearch() { state.openSearch(); showBoard() }
    func showBoard() {
        guard !isShutDown else { return }
        guard boardDragStartFrame == nil else { return }
        let screen = boardScreen()
        guard let screen else { return }
        activeScreen = screen
        layoutBoard(on: screen)
        hideRobot()
        NSApp.activate(ignoringOtherApps: true)
        board.makeKeyAndOrderFront(nil)
        updateBoardVisibility()
    }

    private var lastCaptureLayoutRevision: UInt = 0

    private var boardHeight: CGFloat {
        let extra: CGFloat = state.status != nil || state.store.error != nil ? 45 : 0
        switch state.route {
        case .weekly: return 560
        case .daily: return CornerGeometry.dailyPanelHeight(for: state)
        case .search:
            let entries = state.searchGroups.reduce(0) { $0 + $1.entries.count }
            return entries == 0 ? 290 + extra : min(500, 165 + CGFloat(entries) * 140 + extra)
        case .detail: return 500
        case .newTask: return (state.newTaskDraft.reminderEnabled ? 370 : 310) + extra
        case .settings: return 430
        case .reminders:
            let count = state.store.captures.filter { $0.reminderAt != nil && !($0.kind == .task && $0.isCompleted) }.count
            return count == 0 ? 270 + extra : min(500, 120 + CGFloat(count) * 125 + extra)
        }
    }

    private func resizeBoard() {
        guard board.isVisible, boardDragStartFrame == nil, let screen = boardScreen() else { return }
        activeScreen = screen
        layoutBoard(on: screen)
    }

    private func boardScreen() -> NSScreen? {
        if let topLeft = boardTopLeft {
            // A point inside the header avoids ambiguous shared display edges.
            let headerPoint = NSPoint(x: topLeft.x + 20, y: topLeft.y - 20)
            // While a header is being released just beyond a display edge, its
            // remembered point may temporarily belong to no screen. Keep the
            // board on its active display instead of jumping to whichever
            // display macOS currently calls main.
            return NSScreen.screens.first { $0.frame.contains(headerPoint) }
                ?? activeScreen.flatMap { old in NSScreen.screens.first { $0 == old } }
                ?? NSScreen.main
        }
        return activeScreen.flatMap { old in NSScreen.screens.first { $0 == old } } ?? NSScreen.main
    }

    private func compactBoardFrame(on screen: NSScreen) -> NSRect {
        if board.isVisible, lastLayoutRoute == state.route, state.route == .daily || state.route == .search {
            // Reuse the intended endpoint during rapid filter changes. The
            // animation itself always starts from the currently visible frame.
            return CornerGeometry.filterPanelFrame(current: boardAnimationTarget ?? board.frame,
                                                    visible: screen.visibleFrame, preferredHeight: boardHeight)
        }
        if let topLeft = boardTopLeft {
            return CornerGeometry.movedPanelFrame(topLeft: topLeft, visible: screen.visibleFrame, preferredHeight: boardHeight)
        }
        let robotFrame = CornerGeometry.robotFrame(target: activeTarget, on: screen)
        return CornerGeometry.panelFrame(robot: robotFrame, visible: screen.visibleFrame,
                                         target: activeTarget, preferredHeight: boardHeight)
    }

    private func layoutBoard(on screen: NSScreen) {
        let previousRoute = lastLayoutRoute
        let previousFilter = lastLayoutFilter
        let frame: NSRect
        if state.route == .weekly {
            if weeklyDirection == nil || previousRoute == .daily {
                // A rapid re-open uses the intended compact endpoint rather
                // than adopting an intermediate animation frame as placement.
                let compact = boardAnimationTarget ?? (board.isVisible ? board.frame : compactBoardFrame(on: screen))
                // Remember the compact header in memory, without treating a
                // programmatic expansion as a user placement preference.
                boardTopLeft = NSPoint(x: compact.minX, y: compact.maxY)
                weeklyDirection = CornerGeometry.weeklyExpansionDirection(compact: compact, visible: screen.visibleFrame)
            }
            let direction = weeklyDirection ?? .right
            if state.weeklyExpansionDirection != direction { state.weeklyExpansionDirection = direction }
            frame = CornerGeometry.weeklyPanelFrame(compact: compactBoardFrame(on: screen), visible: screen.visibleFrame,
                                                   direction: direction)
        } else {
            frame = compactBoardFrame(on: screen)
            if state.route == .daily {
                let direction = CornerGeometry.weeklyExpansionDirection(compact: frame, visible: screen.visibleFrame)
                if state.weeklyExpansionDirection != direction { state.weeklyExpansionDirection = direction }
            }
        }
        lastLayoutRoute = state.route
        lastLayoutFilter = state.filter
        board.title = state.route == .weekly ? "DaBin Week" : "DaBin Daily"
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let weeklyTransition = CornerGeometry.shouldAnimateWeeklyTransition(from: previousRoute, to: state.route,
            visible: board.isVisible, reduceMotion: reduceMotion)
        let filterTransition = CornerGeometry.shouldAnimateFilterTransition(from: previousRoute, to: state.route,
            previousFilter: previousFilter, filter: state.filter, visible: board.isVisible, reduceMotion: reduceMotion)
        // Preview/status updates arriving during a filter animation may change
        // its target height; continue smoothly instead of snapping to that size.
        let continuingFilterTransition = boardAnimationKind == .filter && !reduceMotion && board.isVisible
            && previousRoute == state.route && (state.route == .daily || state.route == .search)
        let captureResize = state.captureLayoutRevision != lastCaptureLayoutRevision
            && previousRoute == state.route && state.route == .daily
            && board.isVisible && !reduceMotion
        lastCaptureLayoutRevision = state.captureLayoutRevision
        let animation: BoardFrameAnimationKind? = weeklyTransition ? .weekly
            : (filterTransition || continuingFilterTransition || captureResize ? .filter : nil)
        if reduceMotion { stopBoardAnimation() }
        applyBoardFrame(frame, animation: animation)
    }

    private func setBoardFrame(_ frame: NSRect) {
        lastAppliedBoardFrame = frame
        applyingBoardFrame = true
        board.setFrame(frame, display: true)
        applyingBoardFrame = false
    }

    private func applyBoardFrame(_ frame: NSRect, animation: BoardFrameAnimationKind? = nil) {
        if boardFrameAnimation != nil, boardAnimationTarget == frame { return }
        stopBoardAnimation()
        guard let animation, board.frame != frame else { setBoardFrame(frame); return }
        let start = board.frame
        let started = ProcessInfo.processInfo.systemUptime
        let duration = animation == .filter ? Self.filterResizeDuration : 0.28
        boardAnimationTarget = frame
        boardAnimationKind = animation
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
                let eased = CGFloat(progress * progress * (3 - 2 * progress))
                let next = NSRect(x: start.minX + (frame.minX - start.minX) * eased,
                                  y: start.minY + (frame.minY - start.minY) * eased,
                                  width: start.width + (frame.width - start.width) * eased,
                                  height: start.height + (frame.height - start.height) * eased)
                self.setBoardFrame(progress == 1 ? frame : next)
                if progress == 1 { self.stopBoardAnimation() }
            }
        }
        boardFrameAnimation = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBoardAnimation() {
        boardFrameAnimation?.invalidate()
        boardFrameAnimation = nil
        boardAnimationTarget = nil
        boardAnimationKind = nil
    }

    private func beginBoardDrag() {
        stopBoardAnimation()
        boardDragStartFrame = board.frame
        boardDragTimer?.invalidate()
        // Keep layout updates paused until the pointer is released, including
        // a release outside the app's bounds. Poll only for this gesture.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.finishBoardDragIfReleased()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        boardDragTimer = timer
    }

    func finishBoardDragIfReleased(pressedMouseButtons: Int = NSEvent.pressedMouseButtons) {
        guard pressedMouseButtons & 1 == 0 else { return }
        guard let initial = boardDragStartFrame else { return }
        boardDragTimer?.invalidate()
        boardDragTimer = nil
        boardDragStartFrame = nil
        if board.frame.origin != initial.origin { rememberBoardPosition() }
        if state.route == .daily || state.route == .search, let screen = boardScreen() {
            let compactWidth = CornerGeometry.panelFrame(robot: .zero, visible: screen.visibleFrame,
                                                         corner: .bottomLeft).width
            // A user drag can leave the header off screen, or interrupt a
            // weekly fold at an intermediate width. Recover normal geometry
            // before applying fixed-top resizing to subsequent filter changes.
            if !screen.visibleFrame.contains(board.frame) || abs(board.frame.width - compactWidth) > 0.5 {
                lastLayoutRoute = nil
            }
        }
        resizeBoard()
    }

    @objc private func boardMoved() {
        guard board.isVisible, !applyingBoardFrame, boardFrameAnimation == nil,
              board.frame != lastAppliedBoardFrame else { return }
        rememberBoardPosition()
    }

    private func rememberBoardPosition() {
        let point: NSPoint
        if lastLayoutRoute == .weekly, let direction = weeklyDirection {
            let visible = NSScreen.screens.first { $0.frame.contains(NSPoint(x: board.frame.midX, y: board.frame.maxY - 20)) }
                ?? boardScreen()
            let compactWidth = visible.map { CornerGeometry.panelFrame(robot: .zero, visible: $0.visibleFrame,
                corner: .bottomLeft).width } ?? 380
            point = CornerGeometry.compactTopLeft(weeklyFrame: board.frame, compactWidth: compactWidth, direction: direction)
        } else {
            point = NSPoint(x: board.frame.minX, y: board.frame.maxY)
        }
        guard point.x.isFinite, point.y.isFinite else { return }
        boardTopLeft = point
        placementDefaults?.set([Double(point.x), Double(point.y)], forKey: Self.boardPlacementKey)
        if state.route == .daily, let screen = boardScreen() {
            let direction = CornerGeometry.weeklyExpansionDirection(compact: board.frame, visible: screen.visibleFrame)
            if state.weeklyExpansionDirection != direction { state.weeklyExpansionDirection = direction }
        }
    }

    func dismiss() {
        stopBoardAnimation()
        (board.contentView as? DailyCaptureHostingView)?.clearDropTarget()
        message?.close()
        board.orderOut(nil)
        state.isBoardVisible = false
        keyboardHold = false
        suppressUntilExit = true
        hideRobot()
    }

    private func hideRobot() {
        guard !saving && !dragActive else { return }
        hoverFocus = false
        robot.hideCharacter()
        bin.orderOut(nil)
        keyboardHold = false
    }

    private func received(_ captures: [Capture], errors: [String]) {
        keyboardHold = false
        feedbackUntil = Date().addingTimeInterval(errors.isEmpty ? 1.3 : 4)
        robot.digest(success: !captures.isEmpty, partial: !errors.isEmpty)
        state.reportCaptureResult(captures, errors: errors)
        if !errors.isEmpty {
            if let summary = state.status?.text { showMessage(summary) }
        }
    }

    private func receiveOnDaily(_ pasteboard: NSPasteboard) {
        guard state.route == .daily else { return }
        let navigationRevision = state.captureNavigationRevision
        input.receive(pasteboard, completion: { [weak self] captures, _ in
            // Reveal a successful capture on its receipt day, even if the
            // board was showing an older date or an incompatible filter.
            // A slow import must never pull the user out of a later action.
            guard let self, let first = captures.first, self.board.isVisible,
                  self.state.route == .daily,
                  self.state.captureNavigationRevision == navigationRevision else { return }
            self.state.openDaily()
            self.state.selectedDay = first.capturedAt
            self.state.dailyScrollID = self.state.feedID(for: first, on: self.state.selectedDay)
        })
    }

    private func showMessage(_ text: String) {
        guard bin.isVisible else { return }
        message?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            Text(text).font(.system(size: 12)).padding(12).frame(width: 245).fixedSize(horizontal: false, vertical: true)
        )
        let edge: NSRectEdge
        switch activeTarget {
        case .corner(let corner): edge = corner.isRight ? .minX : .maxX
        case .cameraIsland: edge = .minY
        }
        popover.show(relativeTo: robot.bounds, of: robot, preferredEdge: edge)
        message = popover
    }

    @objc private func screensChanged() {
        // A removed/reconfigured display needs normal screen clamping rather
        // than preserving a header position from the old display's coordinates.
        stopBoardAnimation()
        lastLayoutRoute = nil
        if board.isVisible { showBoard() }
        else { hideRobot() }
    }

    private func robotHomeChanged() {
        suppressUntilExit = false
        guard !saving, !dragActive else { return }
        hideRobot()
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        robot.refreshMotionPreference()
    }

    @objc private func updateBoardVisibility() {
        let visible = board.isVisible && !NSApp.isHidden && board.occlusionState.contains(.visible)
        if state.isBoardVisible != visible { state.isBoardVisible = visible }
    }
}
