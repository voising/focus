import AppKit

/// Watches the pointer so the frame can uncover the menu bar on demand.
///
/// macOS 26 ignores `_HIHideMenuBar` for *rendering* — setting it drops the 31 pt layout
/// reservation from `visibleFrame`, but the WindowServer still draws the menu bar at full
/// opacity, verified with the pointer parked mid-screen and after a Dock restart. So Focus
/// hides it the only way left: painting over it, and implementing the auto-hide itself.
///
/// Polling at 10 Hz is free and, unlike a global event monitor, needs no permission of
/// its own — which matters because this has to work before Accessibility is granted.
final class MenuBarHoverMonitor {

    /// Reveal the instant the pointer touches the top edge, but keep it revealed until the
    /// pointer has cleared the whole menu bar. The gap between the two stops the frame
    /// flickering while the pointer rests on the boundary.
    private static let revealThreshold: CGFloat = 2
    private static let concealThreshold: CGFloat = 36
    private static let interval: TimeInterval = 0.1

    /// Fires only on transitions, with `true` meaning "pointer is at the menu bar".
    var onChange: ((Bool) -> Void)?

    private var timer: Timer?
    private(set) var isPointerAtMenuBar = false

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Common modes, so the reveal still works while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isPointerAtMenuBar else { return }
        isPointerAtMenuBar = false
        onChange?(false)
    }

    private func poll() {
        guard let screen = NSScreen.primary else { return }
        let distanceFromTop = screen.frame.maxY - NSEvent.mouseLocation.y

        let atMenuBar = isPointerAtMenuBar
            ? distanceFromTop < Self.concealThreshold
            : distanceFromTop <= Self.revealThreshold

        guard atMenuBar != isPointerAtMenuBar else { return }
        isPointerAtMenuBar = atMenuBar
        onChange?(atMenuBar)
    }
}
