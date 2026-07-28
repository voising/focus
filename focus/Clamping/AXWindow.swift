import ApplicationServices
import CoreGraphics
import Foundation

/// `AXFullScreen` is a real attribute but has no public constant.
private let kAXFullScreenAttributeName = "AXFullScreen"

/// A thin, non-throwing wrapper over a window's `AXUIElement`. Every accessor returns
/// `nil` rather than an error: apps die, go unresponsive, or simply refuse to answer, and
/// none of that is worth propagating up to a window manager.
struct AXWindow {

    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    // MARK: - Attributes

    private func copyAttribute(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyAXValue(_ attribute: String) -> AXValue? {
        guard let raw = copyAttribute(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
            return nil
        }
        // Safe: the type ID was just checked.
        return (raw as! AXValue)
    }

    var role: String? {
        copyAttribute(kAXRoleAttribute) as? String
    }

    var subrole: String? {
        copyAttribute(kAXSubroleAttribute) as? String
    }

    var isMinimized: Bool {
        copyAttribute(kAXMinimizedAttribute) as? Bool ?? false
    }

    var isFullScreen: Bool {
        copyAttribute(kAXFullScreenAttributeName) as? Bool ?? false
    }

    /// Only ordinary document/app windows get repositioned. Sheets, popovers, palettes
    /// and system dialogs report other subroles and are left exactly where their app put
    /// them — moving those is what makes window managers feel broken.
    var isStandard: Bool {
        role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    // MARK: - Frame

    /// Window frame in AppKit coordinates (bottom-left origin).
    var frame: CGRect? {
        frame(referenceHeight: ScreenCoordinates.referenceHeight)
    }

    /// As `frame`, with the flip axis supplied. `NSScreen` is main-thread only, so a
    /// caller working off the main thread reads it once up front and passes it here.
    func frame(referenceHeight: CGFloat) -> CGRect? {
        guard let positionValue = copyAXValue(kAXPositionAttribute),
              let sizeValue = copyAXValue(kAXSizeAttribute) else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }

        return ScreenCoordinates.flip(
            CGRect(origin: position, size: size),
            referenceHeight: referenceHeight
        )
    }

    /// Writes an AppKit-coordinate frame back to the window.
    ///
    /// Position is written twice, on either side of the size: an app whose window is
    /// currently near a screen edge may refuse to grow until it has been moved, and may
    /// refuse to move until it has shrunk. Bracketing the resize handles both orders.
    @discardableResult
    func setFrame(_ appKitRect: CGRect) -> Bool {
        setFrame(appKitRect, referenceHeight: ScreenCoordinates.referenceHeight)
    }

    /// As `setFrame`, with the flip axis supplied — see `frame(referenceHeight:)`.
    @discardableResult
    func setFrame(_ appKitRect: CGRect, referenceHeight: CGFloat) -> Bool {
        let axRect = ScreenCoordinates.flip(appKitRect, referenceHeight: referenceHeight)
        var position = axRect.origin
        var size = axRect.size

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)

        return result == .success
    }
}

/// `AXUIElement` is a CoreFoundation type and gets no Swift `Hashable` conformance for
/// free, so bookkeeping dictionaries key off this instead.
struct AXElementKey: Hashable {

    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func == (lhs: AXElementKey, rhs: AXElementKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
