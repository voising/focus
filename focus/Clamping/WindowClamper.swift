import AppKit
import ApplicationServices

/// Keeps application windows inside the working area.
///
/// Three details do all the work here:
///
/// * **Reentrancy** — writing a frame makes the app emit more move/resize notifications.
///   Without remembering what we last wrote, that is an infinite loop.
/// * **Live drags** — move notifications arrive continuously while the mouse is down.
///   Clamping mid-drag makes windows feel magnetically stuck, so we wait for the button
///   to come back up.
/// * **Coalescing** — a single resize produces a burst of notifications; one debounced
///   pass over the accumulated set is enough.
final class WindowClamper {

    private static let debounceInterval: TimeInterval = 0.15

    private let watcher: AppWatcher
    private let geometryStore: GeometryStore

    private var isActive = false
    private var pending: Set<AXElementKey> = []
    private var lastWritten: [AXElementKey: CGRect] = [:]
    private var flushTimer: Timer?

    init(watcher: AppWatcher, geometryStore: GeometryStore) {
        self.watcher = watcher
        self.geometryStore = geometryStore
        watcher.onWindowEvent = { [weak self] element in
            self?.enqueue(AXWindow(element: element))
        }
    }

    // MARK: - Permission

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lifecycle

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active

        if active {
            watcher.start()
            clampAllWindows()
        } else {
            watcher.stop()
            flushTimer?.invalidate()
            flushTimer = nil
            pending.removeAll()
            lastWritten.removeAll()
        }
    }

    /// Re-clamps everything, e.g. after the target diagonal changes.
    func refresh() {
        guard isActive else { return }
        lastWritten.removeAll()
        clampAllWindows()
    }

    private func clampAllWindows() {
        for window in watcher.allWindows() {
            clamp(window)
        }
    }

    // MARK: - Debounce

    private func enqueue(_ window: AXWindow) {
        guard isActive else { return }
        pending.insert(AXElementKey(window.element))

        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: Self.debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.flush()
        }
        // Keep firing while a menu is open or a window is mid-drag.
        if let flushTimer {
            RunLoop.main.add(flushTimer, forMode: .common)
        }
    }

    private func flush() {
        flushTimer = nil

        // Still dragging or resizing — try again once the mouse is released rather than
        // fighting the user's cursor.
        guard NSEvent.pressedMouseButtons == 0 else {
            flushTimer = Timer.scheduledTimer(
                withTimeInterval: Self.debounceInterval,
                repeats: false
            ) { [weak self] _ in
                self?.flush()
            }
            if let flushTimer {
                RunLoop.main.add(flushTimer, forMode: .common)
            }
            return
        }

        let windows = pending
        pending.removeAll()
        for key in windows {
            clamp(AXWindow(element: key.element))
        }
    }

    // MARK: - Clamping

    private func clamp(_ window: AXWindow) {
        guard isActive,
              let geometry = geometryStore.primaryGeometry,
              !geometry.isIdentity else { return }

        guard window.isStandard, !window.isMinimized, !window.isFullScreen else { return }
        guard let frame = window.frame else { return }

        let key = AXElementKey(window.element)

        // The app is just echoing back the frame we set a moment ago.
        if let written = lastWritten[key], frame.isNearlyEqual(to: written) { return }

        guard let target = geometry.clamped(frame) else {
            lastWritten[key] = frame
            return
        }

        window.setFrame(target)
        // Record the intent, not a read-back: apps routinely honour a resize only
        // partially, and re-reading here would just invite another round trip.
        lastWritten[key] = target
    }
}
