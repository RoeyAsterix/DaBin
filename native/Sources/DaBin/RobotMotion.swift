import CoreGraphics
import Foundation

enum RobotManualEntranceTiming {
    /// Pointer-triggered island reveals are intentionally quicker than the
    /// automatic saved-capture performance, which retains its own timing.
    static let islandDuration: TimeInterval = 0.55
    static let reducedDuration: TimeInterval = 0.10
}

/// The edge the robot travels through when it appears or retreats.
/// `top` is used by the optional position below a MacBook camera housing.
enum RobotEntrance: String, CaseIterable, Equatable {
    case left
    case right
    case top

    var hiddenTranslation: CGPoint {
        switch self {
        case .left: return CGPoint(x: -22, y: 0)
        case .right: return CGPoint(x: 22, y: 0)
        case .top: return CGPoint(x: 0, y: -22)
        }
    }

    var revealRotationDegrees: CGFloat {
        switch self {
        case .left: return -7
        case .right: return 7
        case .top: return 0
        }
    }
}

/// A visual mood is deliberately independent of storage and window state.
/// The associated pointer is normalized to -1...1 on both axes.
enum RobotMood: Equatable {
    case hidden
    case idle
    case curious(pointer: CGPoint)
    case hungry
    case digesting
    case delighted
    case partialSuccess
    case puzzled
}

enum RobotCaptureResult: Equatable {
    case success
    case partialSuccess
    case failure
}

enum RobotMotionEvent: Equatable {
    case reveal(RobotEntrance)
    case hover(Bool, pointer: CGPoint? = nil)
    case acceptedDrag(Bool)
    case saving(Bool)
    case result(RobotCaptureResult)
    case feedbackExpired
    case hide
}

/// Pure interaction reducer. Its explicit ordering is:
/// feedback > saving > accepted drag > hover > idle, with hidden overriding all.
/// Starting a new accepted drag or save clears stale result feedback.
struct RobotMotionState: Equatable {
    private(set) var isVisible = false
    private(set) var entrance: RobotEntrance = .right
    private(set) var isHovered = false
    private(set) var pointer = CGPoint.zero
    private(set) var isAcceptingDrag = false
    private(set) var isSaving = false
    private(set) var result: RobotCaptureResult?

    var mood: RobotMood {
        guard isVisible else { return .hidden }
        if let result {
            switch result {
            case .success: return .delighted
            case .partialSuccess: return .partialSuccess
            case .failure: return .puzzled
            }
        }
        if isSaving { return .digesting }
        if isAcceptingDrag { return .hungry }
        if isHovered { return .curious(pointer: pointer) }
        return .idle
    }

    mutating func send(_ event: RobotMotionEvent) {
        switch event {
        case .reveal(let entrance):
            self.entrance = entrance
            isVisible = true
        case .hover(let hovering, let pointer):
            isHovered = hovering
            if let pointer { self.pointer = Self.normalized(pointer) }
            if !hovering { self.pointer = .zero }
        case .acceptedDrag(let accepted):
            isAcceptingDrag = accepted
            if accepted {
                isVisible = true
                result = nil
            }
        case .saving(let saving):
            isSaving = saving
            if saving {
                isVisible = true
                isAcceptingDrag = false
                result = nil
            }
        case .result(let result):
            self.result = result
            isSaving = false
            isAcceptingDrag = false
            isVisible = true
        case .feedbackExpired:
            result = nil
        case .hide:
            isVisible = false
            isHovered = false
            pointer = .zero
            isAcceptingDrag = false
            isSaving = false
            result = nil
        }
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(-1, point.x)), y: min(1, max(-1, point.y)))
    }
}

enum RobotMotionTransition: Equatable {
    case reveal(RobotEntrance)
    case hide(RobotEntrance)
    case mood(RobotMood)
}

struct RobotPartTransform: Equatable {
    var translation = CGPoint.zero
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotationDegrees: CGFloat = 0

    static let identity = RobotPartTransform()
}

/// A pointer encounter changes the artwork inside a fixed interaction target.
/// Hands live in stage space: one keeps its purchase on the edge while the
/// shoulders carry the character's weight and the other reaches for the cursor.
struct RobotCompanionPose: Equatable {
    var body = RobotPartTransform.identity
    var head = RobotPartTransform.identity
    var feet = RobotPartTransform.identity
    var gaze = CGPoint.zero
    var peekEyesOffset = CGPoint.zero
    var leftHand = CGPoint.zero
    var rightHand = CGPoint.zero
    var grippingHandIndex = 0
    var headOpacity: Float = 0
    var torsoOpacity: Float = 0
    var handOpacity: Float = 0
    var peekEyeOpacity: Float = 0
    var eyeBrightness: CGFloat = 1
    var isExpressionOnly = false

    static func make(revealProgress: CGFloat, pointer: CGPoint, entrance: RobotEntrance,
                     expressionOnly: Bool, gripPoint: CGPoint? = nil) -> RobotCompanionPose {
        func finite(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
            value.isFinite ? value : fallback
        }
        func unit(_ value: CGFloat) -> CGFloat { min(1, max(0, finite(value))) }
        func smooth(_ value: CGFloat) -> CGFloat {
            let clamped = unit(value)
            return clamped * clamped * (3 - 2 * clamped)
        }
        let progress = unit(revealProgress)
        let pointer = CGPoint(x: min(1, max(-1, finite(pointer.x))),
                              y: min(1, max(-1, finite(pointer.y))))
        var pose = RobotCompanionPose()
        pose.isExpressionOnly = expressionOnly
        pose.grippingHandIndex = entrance == .right ? 1 : 0
        let defaultGrip: CGPoint
        switch entrance {
        case .top: defaultGrip = CGPoint(x: 12, y: 20)
        case .left: defaultGrip = CGPoint(x: 7, y: 31)
        case .right: defaultGrip = CGPoint(x: 57, y: 31)
        }
        let grip = gripPoint.map { CGPoint(x: finite($0.x, fallback: defaultGrip.x),
                                          y: finite($0.y, fallback: defaultGrip.y)) } ?? defaultGrip
        pose.leftHand = grip
        pose.rightHand = grip
        // The first eyes appear immediately outside the contact edge, rather
        // than floating at the full body's eventual face position.
        let peekCenter: CGPoint
        switch entrance {
        case .top: peekCenter = CGPoint(x: 32, y: grip.y + 7)
        case .left: peekCenter = CGPoint(x: grip.x + 14, y: grip.y - 6)
        case .right: peekCenter = CGPoint(x: grip.x - 14, y: grip.y - 6)
        }
        pose.peekEyesOffset = CGPoint(x: peekCenter.x - 32, y: peekCenter.y - 36.17)
        guard progress > 0 else { return pose }

        pose.gaze = CGPoint(x: pointer.x * 2.1, y: pointer.y * 1.4)
        pose.eyeBrightness = 1.12
        if expressionOnly {
            // Quiet Mode and Reduce Motion use one still, curious expression.
            // Their approach threshold changes visibility, never body geometry.
            pose.headOpacity = 1
            pose.torsoOpacity = 1
            pose.handOpacity = 0
            return pose
        }

        let climb = smooth((progress - 0.30) / 0.70)
        let anticipation = sin(min(1, max(0, (progress - 0.25) / 0.36)) * .pi)
        let settle = sin(min(1, max(0, (progress - 0.65) / 0.35)) * .pi)
        let hidden = entrance.hiddenTranslation
        pose.body.translation = CGPoint(x: hidden.x * (1 - climb),
                                        y: hidden.y * (1 - climb) + anticipation * 1.8 - settle * 1.2)
        pose.body.scaleX = 1 + anticipation * 0.035
        pose.body.scaleY = 1 - anticipation * 0.055
        pose.body.rotationDegrees = entrance.revealRotationDegrees * (1 - climb) + pointer.x * 3.4 * climb
        pose.head.translation = CGPoint(x: pointer.x * 1.1 * climb, y: pointer.y * 0.6 * climb)
        pose.head.rotationDegrees = pointer.x * 4.5 * climb
        pose.feet.translation.y = anticipation * 0.6 - settle * 1.8
        pose.feet.rotationDegrees = -pointer.x * 4 * climb + settle * (entrance == .left ? -5 : 5)
        pose.headOpacity = Float(smooth((progress - 0.25) / 0.34))
        pose.torsoOpacity = Float(smooth((progress - 0.43) / 0.42))
        pose.handOpacity = Float(smooth((progress - 0.32) / 0.25))
        pose.peekEyeOpacity = Float(smooth(progress / 0.16) * (1 - smooth((progress - 0.25) / 0.34)))

        let side: CGFloat = pose.grippingHandIndex == 0 ? 1 : -1
        let shoulder = CGPoint(x: pose.grippingHandIndex == 0 ? 51.74 : 12.26, y: 40.58)
        // A reach stays inside the fixed renderer stage, including its palm.
        // Extending the native window would move the user's click destination.
        let reach = CGPoint(x: min(60, max(4, shoulder.x + side * (8 + climb * 9) + pointer.x * 9 * climb)),
                            y: shoulder.y + pointer.y * 11 * climb - 3 * climb)
        if pose.grippingHandIndex == 0 { pose.rightHand = reach }
        else { pose.leftHand = reach }
        return pose
    }
}

/// A value-only description of the target pose. It lets tests validate motion
/// policy without creating an AppKit view or relying on animation timing.
struct RobotMotionDescriptor: Equatable {
    var transition: RobotMotionTransition
    var duration: TimeInterval
    var initialBody = RobotPartTransform.identity
    var body = RobotPartTransform.identity
    var face = RobotPartTransform.identity
    var pupilOffset = CGPoint.zero
    var lid = RobotPartTransform.identity
    var leftArm = RobotPartTransform.identity
    var rightArm = RobotPartTransform.identity
    var intakeProgress: CGFloat = 0
    var shadowScale: CGFloat = 1
    var shadowOpacity: CGFloat = 0.18
    var allowsAmbientMotion = false
    var usesKeyframes = false
    var isAnimated = true

    static func make(for transition: RobotMotionTransition, reduceMotion: Bool) -> RobotMotionDescriptor {
        var descriptor = RobotMotionDescriptor(transition: transition, duration: 0.22)
        switch transition {
        case .reveal(let entrance):
            descriptor.duration = 0.30
            descriptor.initialBody.translation = entrance.hiddenTranslation
            descriptor.initialBody.scaleX = 0.88
            descriptor.initialBody.scaleY = 0.88
            descriptor.initialBody.rotationDegrees = entrance.revealRotationDegrees
            descriptor.usesKeyframes = true
            descriptor.allowsAmbientMotion = true
        case .hide(let entrance):
            descriptor.duration = 0.18
            descriptor.body.translation = entrance.hiddenTranslation
            descriptor.body.scaleX = 0.94
            descriptor.body.scaleY = 0.94
            descriptor.body.rotationDegrees = entrance.revealRotationDegrees * 0.65
        case .mood(let mood):
            apply(mood, to: &descriptor)
        }

        guard reduceMotion else { return descriptor }
        // Expressions may change instantly, while positional, scaling, rotating,
        // repeated and keyframed movement is removed.
        descriptor.duration = 0
        descriptor.initialBody = .identity
        descriptor.body = .identity
        descriptor.face = .identity
        descriptor.pupilOffset = .zero
        descriptor.leftArm = .identity
        descriptor.rightArm = .identity
        descriptor.shadowScale = 1
        descriptor.shadowOpacity = 0.18
        descriptor.allowsAmbientMotion = false
        descriptor.usesKeyframes = false
        descriptor.isAnimated = false
        return descriptor
    }

    private static func apply(_ mood: RobotMood, to descriptor: inout RobotMotionDescriptor) {
        switch mood {
        case .hidden:
            descriptor.duration = 0
            descriptor.isAnimated = false
        case .idle:
            descriptor.duration = 0.20
            descriptor.allowsAmbientMotion = true
        case .curious(let pointer):
            let normalized = CGPoint(x: min(1, max(-1, pointer.x)), y: min(1, max(-1, pointer.y)))
            descriptor.duration = 0.16
            descriptor.body.translation.y = -1.5
            descriptor.body.rotationDegrees = normalized.x * 2.8
            descriptor.face.translation.x = normalized.x * 0.7
            descriptor.pupilOffset = CGPoint(x: normalized.x * 2.1, y: normalized.y * 1.1)
            descriptor.leftArm.rotationDegrees = -8
            descriptor.rightArm.rotationDegrees = 11
            descriptor.shadowScale = 0.94
            descriptor.allowsAmbientMotion = true
        case .hungry:
            descriptor.duration = 0.20
            descriptor.body.translation.y = 0.8
            descriptor.body.scaleX = 1.025
            descriptor.body.scaleY = 0.975
            descriptor.lid.translation.y = -5.5
            descriptor.lid.rotationDegrees = -6
            descriptor.leftArm.rotationDegrees = -13
            descriptor.rightArm.rotationDegrees = 13
            descriptor.pupilOffset.y = -1.5
            descriptor.shadowScale = 1.06
            descriptor.shadowOpacity = 0.25
        case .digesting:
            descriptor.duration = 0.66
            descriptor.intakeProgress = 1
            descriptor.usesKeyframes = true
        case .delighted:
            descriptor.duration = 0.64
            descriptor.body.translation.y = -2.5
            descriptor.body.scaleX = 1.03
            descriptor.body.scaleY = 1.03
            descriptor.leftArm.rotationDegrees = -10
            descriptor.rightArm.rotationDegrees = 22
            descriptor.shadowScale = 0.86
            descriptor.usesKeyframes = true
        case .partialSuccess:
            descriptor.duration = 0.48
            descriptor.body.rotationDegrees = -3
            descriptor.leftArm.rotationDegrees = -12
            descriptor.rightArm.rotationDegrees = 12
            descriptor.usesKeyframes = true
        case .puzzled:
            descriptor.duration = 0.42
            descriptor.body.rotationDegrees = 5
            descriptor.face.translation.x = 0.7
            descriptor.leftArm.rotationDegrees = 8
            descriptor.rightArm.rotationDegrees = -8
            descriptor.usesKeyframes = true
        }
    }
}
