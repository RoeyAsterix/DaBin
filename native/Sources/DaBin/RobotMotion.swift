import CoreGraphics
import Foundation

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
