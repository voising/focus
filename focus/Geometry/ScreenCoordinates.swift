import AppKit
import CoreGraphics

/// The Accessibility API reports window frames with a top-left origin anchored to the
/// primary display; AppKit uses a bottom-left origin. Every conversion between the two
/// goes through here — doing the flip inline is how window managers end up moving
/// windows by exactly one screen height.
enum ScreenCoordinates {

    /// The flip axis is the *primary* display's top edge, not the current screen's.
    static var referenceHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// The conversion is an involution, so both directions share one implementation.
    static func flip(_ rect: CGRect, referenceHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: referenceHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        flip(rect, referenceHeight: referenceHeight)
    }

    static func axRect(fromAppKit rect: CGRect) -> CGRect {
        flip(rect, referenceHeight: referenceHeight)
    }
}

extension NSScreen {

    /// The display carrying the menu bar. `NSScreen.main` tracks the key window instead,
    /// which is not what we want when the app has no windows of its own.
    static var primary: NSScreen? {
        NSScreen.screens.first
    }

    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Physical diagonal in inches, read from the display's EDID. Returns `nil` when the
    /// panel reports nothing usable — projectors, some KVMs and virtual displays all do —
    /// so the caller can fall back to a user-supplied value.
    var physicalDiagonalInches: Double? {
        let millimetres = CGDisplayScreenSize(displayID)
        guard millimetres.width > 0, millimetres.height > 0 else { return nil }
        let diagonal = sqrt(millimetres.width * millimetres.width
            + millimetres.height * millimetres.height) / 25.4
        return (10.0 ... 60.0).contains(diagonal) ? diagonal : nil
    }
}
