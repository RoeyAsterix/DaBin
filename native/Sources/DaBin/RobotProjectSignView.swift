import AppKit
import QuartzCore

/// A native held board. The stage owns placement, while this view keeps the
/// lettering upright and joins both shoulders to visible hands on the board.
/// It owns no window, capture service, timers or mouse destination.
@MainActor
final class RobotProjectSignView: NSView {
    static let preferredSize = CGSize(width: 128, height: 24)
    static var projectFont: NSFont {
        let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: 12) ?? base
    }
    private let board = NSView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let statusDot = CAShapeLayer()
    private let arms = CAShapeLayer()
    private let armHighlights = CAShapeLayer()
    private let hands = CAShapeLayer()
    private(set) var projectName: String?
    private(set) var statusText = ""
    private(set) var boardFrame = CGRect.zero
    private(set) var leftShoulder = CGPoint.zero
    private(set) var rightShoulder = CGPoint.zero
    private(set) var leftGrip = CGPoint.zero
    private(set) var rightGrip = CGPoint.zero
    var fontSize: CGFloat { projectLabel.font?.pointSize ?? 0 }
    var hasArmConnection: Bool { arms.path != nil && hands.path != nil && projectName != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.name = "projectRecording.stage"
        layer?.masksToBounds = false
        for (shape, name) in [(arms, "projectRecording.arms"),
                              (armHighlights, "projectRecording.armHighlights"),
                              (hands, "projectRecording.hands")] {
            shape.name = name
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
            layer?.addSublayer(shape)
        }
        arms.strokeColor = QuietOrbitVisualStyle.color(0x554760)
        armHighlights.strokeColor = QuietOrbitVisualStyle.color(0xCFBEDC)
        hands.fillColor = QuietOrbitVisualStyle.color(0xCFBEDC)
        hands.strokeColor = QuietOrbitVisualStyle.color(0x836495)
        board.wantsLayer = true
        board.layer?.name = "projectRecording.board"
        board.layer?.backgroundColor = QuietOrbitVisualStyle.color(0x342A40)
        board.layer?.cornerRadius = 7
        board.layer?.borderWidth = 1
        board.layer?.masksToBounds = true
        board.setAccessibilityElement(false)
        addSubview(board)
        // Hands overlap the board edge; their drawing must be above its fill.
        hands.zPosition = 1
        statusDot.name = "projectRecording.statusDot"
        board.layer?.addSublayer(statusDot)
        projectLabel.font = Self.projectFont
        projectLabel.textColor = NSColor(cgColor: QuietOrbitVisualStyle.color(0xF5F1F8))
        projectLabel.alignment = .center
        projectLabel.isSelectable = false
        projectLabel.setAccessibilityElement(false)
        board.addSubview(projectLabel)
        projectLabel.maximumNumberOfLines = 1
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.cell?.wraps = false
        projectLabel.cell?.isScrollable = false
        setAccessibilityElement(false)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(projectName: String?, color: NSColor?, isPaused: Bool,
                   statusText: String? = nil) {
        let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectName = isPaused ? nil : name.flatMap { $0.isEmpty ? nil : $0 }
        projectLabel.stringValue = self.projectName ?? ""
        self.statusText = self.projectName == nil ? "" : (statusText ?? "Recording to")
        let accent = (color ?? .systemPurple).usingColorSpace(.sRGB) ?? .systemPurple
        board.layer?.borderColor = accent.cgColor
        statusDot.fillColor = (isPaused ? NSColor.systemOrange : accent).cgColor
        isHidden = self.projectName == nil
        if isPaused { cancelAttachmentMotion() }
        needsLayout = true
    }

    /// Size the plate to the name; only long names need the stage's width cap.
    /// The recording phrase remains available to accessibility without a second row.
    func preferredSize(maximumWidth: CGFloat) -> CGSize {
        // AppKit's cell includes its text insets. NSString alone understates
        // the width and can truncate even an ordinary short project name.
        let textWidth = ceil(projectLabel.cell?.cellSize.width ?? projectLabel.intrinsicContentSize.width)
        return CGSize(width: min(max(0, maximumWidth), textWidth + 20),
                      height: Self.preferredSize.height)
    }

    override func layout() {
        super.layout()
        let width = board.bounds.width
        let height = board.bounds.height
        projectLabel.frame = CGRect(x: 14, y: (height - 17) / 2,
                                    width: max(0, width - 20), height: 17)
        statusDot.path = CGPath(ellipseIn: CGRect(x: 6, y: (height - 4) / 2,
                                                width: 4, height: 4), transform: nil)
    }

    /// Attachment points are in this view's unmirrored, y-up stage coordinates.
    /// One finite native animation moves the board, arm curves and hands together.
    func updateAttachment(boardFrame: CGRect, leftShoulder: CGPoint, rightShoulder: CGPoint,
                          armWidth: CGFloat = 4, duration: TimeInterval = 0) {
        self.boardFrame = boardFrame
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        let gripInset = min(18, boardFrame.width * 0.18)
        leftGrip = CGPoint(x: boardFrame.minX + gripInset, y: boardFrame.maxY - 1)
        rightGrip = CGPoint(x: boardFrame.maxX - gripInset, y: boardFrame.maxY - 1)
        let path = CGMutablePath()
        for (shoulder, grip) in [(leftShoulder, leftGrip), (rightShoulder, rightGrip)] {
            path.move(to: shoulder)
            path.addQuadCurve(to: grip, control: CGPoint(x: shoulder.x + (grip.x - shoulder.x) * 0.7,
                                                        y: min(shoulder.y, grip.y) - 4))
        }
        let handPath = CGMutablePath()
        let handWidth = max(5, armWidth * 2.2)
        for grip in [leftGrip, rightGrip] {
            handPath.addRoundedRect(in: CGRect(x: grip.x - handWidth / 2, y: grip.y - handWidth / 2,
                                               width: handWidth, height: handWidth),
                                    cornerWidth: handWidth * 0.3, cornerHeight: handWidth * 0.3)
        }
        setPath(path, on: arms, duration: duration)
        setPath(path, on: armHighlights, duration: duration)
        setPath(handPath, on: hands, duration: duration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arms.lineWidth = armWidth
        armHighlights.lineWidth = max(1, armWidth * 0.5)
        hands.lineWidth = max(0.8, armWidth * 0.22)
        CATransaction.commit()
        if duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                board.animator().frame = boardFrame
            }
        } else {
            board.layer?.removeAllAnimations()
            board.frame = boardFrame
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func cancelAttachmentMotion() {
        for shape in [arms, armHighlights, hands] { shape.removeAllAnimations() }
        board.layer?.removeAllAnimations()
        layer?.removeAllAnimations()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func setPath(_ path: CGPath, on shape: CAShapeLayer, duration: TimeInterval) {
        let previous = shape.presentation()?.path ?? shape.path
        shape.removeAnimation(forKey: "projectRecording.attachment")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        CATransaction.commit()
        guard duration > 0, let previous else { return }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = previous
        animation.toValue = path
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shape.add(animation, forKey: "projectRecording.attachment")
    }
}
