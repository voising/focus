import AppKit
import CoreGraphics

/// Turns the current screen layout plus the user's preferences into `DisplayGeometry`.
/// Single source of truth for both the overlay and the clamper, so they can never
/// disagree about where the working area is.
final class GeometryStore {

    /// Used when a display reports no usable EDID and the user has not overridden it.
    /// Equal to the default target, so the effect is a harmless no-op rather than a
    /// wildly wrong crop.
    static let fallbackPanelDiagonal: Double = 27.0

    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var detectedPanelDiagonal: Double? {
        NSScreen.primary?.physicalDiagonalInches
    }

    var effectivePanelDiagonal: Double {
        preferences.panelDiagonalOverride ?? detectedPanelDiagonal ?? Self.fallbackPanelDiagonal
    }

    /// Only the primary display — the one carrying the menu bar — is letterboxed.
    /// Keyed by display so extending to every screen is a change of one loop.
    func geometries() -> [CGDirectDisplayID: DisplayGeometry] {
        guard let screen = NSScreen.primary else { return [:] }
        return [screen.displayID: geometry(for: screen)]
    }

    var primaryGeometry: DisplayGeometry? {
        NSScreen.primary.map(geometry(for:))
    }

    private func geometry(for screen: NSScreen) -> DisplayGeometry {
        DisplayGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            panelDiagonal: effectivePanelDiagonal,
            targetDiagonal: preferences.targetDiagonal
        )
    }
}
