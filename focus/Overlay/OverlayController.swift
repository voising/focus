import AppKit

/// Owns the black-frame windows and keeps them matched to the current screen layout.
///
/// Only the primary display is letterboxed in this version, but the controller is keyed
/// by display so covering every screen is a change of one collection, not a rewrite.
final class OverlayController {

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var isActive = false
    private var coversMenuBar = false

    private let geometryProvider: () -> [CGDirectDisplayID: DisplayGeometry]
    private let aboveWindowsProvider: () -> Bool

    init(
        geometryProvider: @escaping () -> [CGDirectDisplayID: DisplayGeometry],
        aboveWindowsProvider: @escaping () -> Bool
    ) {
        self.geometryProvider = geometryProvider
        self.aboveWindowsProvider = aboveWindowsProvider

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        active ? show() : hide()
    }

    /// Raises the frame over the menu bar, or drops it back. Called on every pointer
    /// transition, so it only touches window levels — never layout.
    func setCoversMenuBar(_ covers: Bool) {
        guard covers != coversMenuBar else { return }
        coversMenuBar = covers

        let aboveWindows = aboveWindowsProvider()
        for window in windows.values {
            window.updateLevel(aboveWindows: aboveWindows, coversMenuBar: covers)
        }
    }

    /// Re-reads geometry and reflows the bars. Safe to call while hidden.
    func refresh() {
        guard isActive else { return }
        show()
    }

    @objc private func screenParametersChanged() {
        // Displays that vanished must take their overlay with them, otherwise a stale
        // black rectangle is left stranded on the remaining screen.
        let geometries = geometryProvider()
        for (displayID, window) in windows where geometries[displayID] == nil {
            window.orderOut(nil)
            windows[displayID] = nil
        }
        refresh()
    }

    private func show() {
        let geometries = geometryProvider()
        let aboveWindows = aboveWindowsProvider()

        for (displayID, geometry) in geometries {
            guard !geometry.isIdentity else {
                windows[displayID]?.orderOut(nil)
                windows[displayID] = nil
                continue
            }

            let window: OverlayWindow
            if let existing = windows[displayID] {
                window = existing
            } else {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { continue }
                window = OverlayWindow(screen: screen)
                window.alphaValue = 0
                windows[displayID] = window
            }

            window.apply(geometry, aboveWindows: aboveWindows, coversMenuBar: coversMenuBar)
            window.orderFront(nil)
            window.fade(to: 1)
        }
    }

    private func hide() {
        for window in windows.values {
            window.fade(to: 0) { [weak window] in
                window?.orderOut(nil)
            }
        }
    }
}
