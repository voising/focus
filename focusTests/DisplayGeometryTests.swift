import CoreGraphics
import Testing

@testable import Focus

struct DisplayGeometryTests {

    /// The real setup this app was written for: a 32" panel at "looks like 2560x1440".
    private static func lgPanel(target: Double) -> DisplayGeometry {
        DisplayGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1402),
            panelDiagonal: 32,
            targetDiagonal: target
        )
    }

    @Test func scale_isRatioOfDiagonals() {
        #expect(abs(Self.lgPanel(target: 27).scale - 0.84375) < 0.00001)
    }

    @Test func innerRect_at27Inches_is2160By1215() {
        let inner = Self.lgPanel(target: 27).innerRect
        #expect(inner.width == 2160)
        #expect(inner.height == 1215)
    }

    /// A 1215pt-tall working area cannot sit exactly centred on a 1440pt screen — the
    /// odd height puts the midpoint half a point off the grid. Half a point is invisible;
    /// the bars absorb it, so the top and bottom bars differ by one point.
    @Test func innerRect_isCentredOnScreen_withinHalfAPoint() {
        let geometry = Self.lgPanel(target: 27)
        #expect(abs(geometry.innerRect.midX - geometry.screenFrame.midX) <= 0.5)
        #expect(abs(geometry.innerRect.midY - geometry.screenFrame.midY) <= 0.5)
    }

    @Test func barRects_at27Inches_are200And112PointsThick() {
        let bars = Self.lgPanel(target: 27).barRects()
        let (top, bottom, left, right) = (bars[0], bars[1], bars[2], bars[3])
        #expect(top.height == 112)
        #expect(bottom.height == 113)
        #expect(left.width == 200)
        #expect(right.width == 200)
    }

    @Test func barRects_coverEverythingOutsideInnerRect() {
        let geometry = Self.lgPanel(target: 27)
        let covered = geometry.barRects().reduce(0) { $0 + $1.width * $1.height }
        let bounds = geometry.screenFrame.width * geometry.screenFrame.height
        let inner = geometry.innerRect.width * geometry.innerRect.height
        #expect(covered == bounds - inner)
    }

    @Test func scale_isClampedToOne_whenTargetExceedsPanel() {
        #expect(Self.lgPanel(target: 40).scale == 1.0)
        #expect(Self.lgPanel(target: 40).isIdentity)
    }

    @Test func scale_fallsBackToIdentity_whenPanelSizeIsUnknown() {
        let geometry = DisplayGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1402),
            panelDiagonal: 0,
            targetDiagonal: 27
        )
        #expect(geometry.isIdentity)
    }

    /// At 27" the bars swallow the menu bar, so the clamp region is just the inner rect.
    @Test func clampRect_at27Inches_equalsInnerRect() {
        let geometry = Self.lgPanel(target: 27)
        #expect(geometry.clampRect == geometry.innerRect)
    }

    /// Once the bars get thin enough, the menu bar starts eating into the working area
    /// and windows must stop short of it.
    @Test func clampRect_atLargeTarget_staysBelowMenuBar() {
        let geometry = Self.lgPanel(target: 31.9)
        #expect(geometry.clampRect.maxY == geometry.visibleFrame.maxY)
        #expect(geometry.clampRect.maxY < geometry.innerRect.maxY)
    }

    @Test func clamped_returnsNil_whenWindowAlreadyFits() {
        let geometry = Self.lgPanel(target: 27)
        let inside = CGRect(x: 500, y: 400, width: 800, height: 600)
        #expect(geometry.clamped(inside) == nil)
    }

    @Test func clamped_slidesWindowBackInside_whenItStraysIntoBar() {
        let geometry = Self.lgPanel(target: 27)
        let strayed = CGRect(x: 10, y: 400, width: 800, height: 600)
        let result = geometry.clamped(strayed)
        #expect(result?.minX == geometry.clampRect.minX)
        #expect(result?.width == 800)
        #expect(result?.minY == 400)
    }

    @Test func clamped_shrinksWindow_whenItIsLargerThanWorkingArea() {
        let geometry = Self.lgPanel(target: 27)
        let maximized = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let result = geometry.clamped(maximized)
        #expect(result == geometry.clampRect)
    }

    @Test func clamped_isIdempotent() {
        let geometry = Self.lgPanel(target: 27)
        let strayed = CGRect(x: 2400, y: 1300, width: 900, height: 700)
        guard let once = geometry.clamped(strayed) else {
            Issue.record("expected the strayed window to be clamped")
            return
        }
        #expect(geometry.clamped(once) == nil)
    }
}

struct ScreenCoordinatesTests {

    /// AX measures down from the primary display's top edge; AppKit measures up from its
    /// bottom edge. Round-tripping must land back on the original rect.
    @Test func flip_isItsOwnInverse() {
        let rect = CGRect(x: 100, y: 250, width: 800, height: 600)
        let flipped = ScreenCoordinates.flip(rect, referenceHeight: 1440)
        #expect(flipped == CGRect(x: 100, y: 590, width: 800, height: 600))
        #expect(ScreenCoordinates.flip(flipped, referenceHeight: 1440) == rect)
    }

    @Test func flip_movesTopEdgeToBottomEdge() {
        let atTop = CGRect(x: 0, y: 1340, width: 200, height: 100)
        #expect(ScreenCoordinates.flip(atTop, referenceHeight: 1440).minY == 0)
    }
}
