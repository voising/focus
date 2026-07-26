import CoreGraphics
import Foundation

/// The letterbox maths, expressed as a pure value so it can be unit-tested without a
/// display attached. Everything downstream — the black bars and the window clamper —
/// derives its rectangles from here.
struct DisplayGeometry: Equatable {

    /// Full logical bounds of the screen, AppKit coordinates (bottom-left origin).
    let screenFrame: CGRect

    /// Screen bounds minus the menu bar and the Dock.
    let visibleFrame: CGRect

    /// Physical panel diagonal, in inches.
    let panelDiagonal: Double

    /// Desired working-area diagonal, in inches.
    let targetDiagonal: Double

    static let minimumScale: Double = 0.4
    static let maximumScale: Double = 1.0

    init(screenFrame: CGRect, visibleFrame: CGRect, panelDiagonal: Double, targetDiagonal: Double) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.panelDiagonal = panelDiagonal
        self.targetDiagonal = targetDiagonal
    }

    /// Linear shrink factor. 27" on a 32" panel is 0.84375.
    var scale: Double {
        guard panelDiagonal > 0, targetDiagonal > 0 else { return Self.maximumScale }
        return min(max(targetDiagonal / panelDiagonal, Self.minimumScale), Self.maximumScale)
    }

    /// The centred region left uncovered by the black bars, in AppKit screen coordinates.
    var innerRect: CGRect {
        let width = (screenFrame.width * scale).rounded()
        let height = (screenFrame.height * scale).rounded()
        return CGRect(
            x: (screenFrame.midX - width / 2).rounded(),
            y: (screenFrame.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    /// `innerRect` relative to the overlay window's own coordinate space, which is
    /// anchored at the screen's bottom-left corner rather than the desktop origin.
    var innerRectInWindowSpace: CGRect {
        innerRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    /// Where windows are allowed to live. Intersecting with `visibleFrame` matters once
    /// the target diagonal grows large enough that the bars no longer swallow the menu
    /// bar and the Dock.
    var clampRect: CGRect {
        let rect = innerRect.intersection(visibleFrame)
        return rect.isNull || rect.isEmpty ? visibleFrame : rect
    }

    /// Whether the effect is a no-op, i.e. the working area already fills the panel.
    var isIdentity: Bool {
        scale >= Self.maximumScale
    }

    /// The four black bars, in the overlay window's coordinate space.
    func barRects() -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: screenFrame.size)
        let inner = innerRectInWindowSpace
        return [
            // top
            CGRect(x: 0, y: inner.maxY, width: bounds.width, height: max(0, bounds.maxY - inner.maxY)),
            // bottom
            CGRect(x: 0, y: 0, width: bounds.width, height: max(0, inner.minY)),
            // left
            CGRect(x: 0, y: inner.minY, width: max(0, inner.minX), height: inner.height),
            // right
            CGRect(x: inner.maxX, y: inner.minY, width: max(0, bounds.maxX - inner.maxX), height: inner.height)
        ]
    }

    /// Fit `rect` entirely inside `clampRect`, shrinking it first if it is too large and
    /// then sliding it in by the shortest distance. Returns `nil` when `rect` already
    /// fits, so callers can skip a pointless Accessibility write.
    func clamped(_ rect: CGRect) -> CGRect? {
        let target = clampRect
        var result = rect

        result.size.width = min(result.width, target.width)
        result.size.height = min(result.height, target.height)

        if result.minX < target.minX { result.origin.x = target.minX }
        if result.maxX > target.maxX { result.origin.x = target.maxX - result.width }
        if result.minY < target.minY { result.origin.y = target.minY }
        if result.maxY > target.maxY { result.origin.y = target.maxY - result.height }

        return result.isNearlyEqual(to: rect) ? nil : result
    }
}

extension CGRect {
    /// Accessibility and AppKit disagree about fractional pixels often enough that exact
    /// equality causes clamp/notify feedback loops. One point of slack is plenty.
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
