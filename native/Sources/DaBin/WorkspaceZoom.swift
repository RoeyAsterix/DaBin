import AppKit
import Combine

/// One local workspace preference. Document magnification and navigation
/// snapshots deliberately have no connection to this model.
@MainActor final class WorkspaceZoomSettings: ObservableObject {
    static let factorKey = "DaBin.workspaceZoom.factor.v1"
    static let trackpadKey = "DaBin.workspaceZoom.trackpadNavigation.v1"
    static let couplingKey = "DaBin.workspaceZoom.resizeWindow.v1"
    static let range: ClosedRange<CGFloat> = 0.75...2
    static let steps: [CGFloat] = [0.75, 0.90, 1, 1.10, 1.25, 1.50, 1.75, 2]

    @Published private(set) var factor: CGFloat
    @Published private(set) var isInteracting = false
    @Published var trackpadNavigationEnabled: Bool {
        didSet {
            guard oldValue != trackpadNavigationEnabled else { return }
            defaults?.set(trackpadNavigationEnabled, forKey: Self.trackpadKey)
        }
    }
    @Published var resizeWindowWithZoom: Bool {
        didSet {
            guard oldValue != resizeWindowWithZoom else { return }
            finishInteraction()
            defaults?.set(resizeWindowWithZoom, forKey: Self.couplingKey)
            onCouplingChanged?()
        }
    }

    // The content host owns anchoring; the native window controller owns
    // geometry. Keeping distinct hooks guarantees their ordering.
    var onInteractionBegan: (() -> Bool)?
    var onWillChangeFactor: ((CGFloat) -> Void)?
    var onFactorChanged: ((CGFloat) -> Void)?
    var onFactorApplied: ((CGFloat) -> Void)?
    var onInteractionEnded: (() -> Void)?
    var onCouplingChanged: (() -> Void)?
    /// Native input sets this at gesture start; keyboard/menu commands use nil.
    var anchorInWindow: CGPoint?
    private let defaults: UserDefaults?
    private var changedDuringInteraction = false
    private(set) var persistenceCount = 0

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let saved = defaults?.object(forKey: Self.factorKey) as? NSNumber
        factor = saved.map { CGFloat($0.doubleValue) }.flatMap(Self.validated) ?? 1
        trackpadNavigationEnabled = (defaults?.object(forKey: Self.trackpadKey) as? Bool) ?? true
        resizeWindowWithZoom = (defaults?.object(forKey: Self.couplingKey) as? Bool) ?? true
    }

    var percentage: Int { Int((factor * 100).rounded()) }
    var canZoomIn: Bool { factor < Self.range.upperBound }
    var canZoomOut: Bool { factor > Self.range.lowerBound }

    static func validated(_ value: CGFloat) -> CGFloat? {
        guard value.isFinite, value > 0 else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    @discardableResult func beginInteraction() -> Bool {
        if isInteracting { return true }
        guard onInteractionBegan?() != false else { return false }
        changedDuringInteraction = false
        isInteracting = true
        return true
    }

    /// Ignore nonfinite input rather than allowing a malformed event to reset
    /// the user's scale. Preferences are written only once on completion.
    func update(to proposed: CGFloat) {
        guard isInteracting, let next = Self.validated(proposed), next != factor else { return }
        onWillChangeFactor?(next)
        factor = next
        changedDuringInteraction = true
        onFactorChanged?(next)
        onFactorApplied?(next)
    }

    func finishInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        if changedDuringInteraction {
            defaults?.set(Double(factor), forKey: Self.factorKey)
            persistenceCount += 1
        }
        changedDuringInteraction = false
        onInteractionEnded?()
    }

    func stepIn() { setFactor(Self.steps.first { $0 > factor + 0.000_001 } ?? Self.range.upperBound) }
    func stepOut() { setFactor(Self.steps.last { $0 < factor - 0.000_001 } ?? Self.range.lowerBound) }
    func reset() { setFactor(1) }

    func setFactor(_ proposed: CGFloat) {
        guard let next = Self.validated(proposed), next != factor else { return }
        finishInteraction()
        anchorInWindow = nil
        guard beginInteraction() else { return }
        update(to: next)
        finishInteraction()
    }
}

/// A stable content-size reference prevents cumulative drift when either end
/// of a zoom encounters a display edge or minimum size. Robot chrome is added
/// after scaling, so its controls and artwork never magnify with the content.
@MainActor struct WorkspaceZoomGeometry {
    private(set) var referenceContentSize: CGSize
    private(set) var referenceFactor: CGFloat
    private(set) var referenceTopLeft: CGPoint

    init?(frame: CGRect, factor: CGFloat) {
        guard Self.valid(frame), let factor = WorkspaceZoomSettings.validated(factor) else { return nil }
        referenceContentSize = RobotAppFrameView.contentRect(in: frame).size
        referenceFactor = factor
        referenceTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }

    mutating func rebase(frame: CGRect, factor: CGFloat) {
        if let replacement = Self(frame: frame, factor: factor) { self = replacement }
    }

    mutating func move(to topLeft: CGPoint) {
        guard topLeft.x.isFinite, topLeft.y.isFinite else { return }
        referenceTopLeft = topLeft
    }

    func frame(at factor: CGFloat, visible: CGRect) -> CGRect? {
        guard let factor = WorkspaceZoomSettings.validated(factor), Self.valid(visible) else { return nil }
        let ratio = factor / referenceFactor
        let size = RobotAppFrameView.outerSize(forContentSize: CGSize(
            width: referenceContentSize.width * ratio, height: referenceContentSize.height * ratio))
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let desired = CGRect(x: referenceTopLeft.x, y: referenceTopLeft.y - size.height,
                             width: size.width, height: size.height)
        guard Self.valid(desired) else { return nil }
        return BoardResizeGeometry.fitted(desired, visible: visible)
    }

    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
            && frame.maxX.isFinite && frame.maxY.isFinite
    }
}
