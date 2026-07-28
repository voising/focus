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

    /// Returns whether the active state actually changed, so a caller that also calls
    /// `refresh` can skip it rather than sweeping every window twice in a row.
    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        guard active != isActive else { return false }
        isActive = active

        if active {
            // Clamp first: subscribing talks to every app in turn, and doing that up
            // front only delays the windows moving.
            clampAllWindows()
            watcher.start()
        } else {
            watcher.stop()
            flushTimer?.invalidate()
            flushTimer = nil
            pending.removeAll()
            lastWritten.removeAll()
        }

        return true
    }

    /// Re-clamps everything, e.g. after the target diagonal changes.
    func refresh() {
        guard isActive else { return }
        lastWritten.removeAll()
        clampAllWindows()
    }

    private func clampAllWindows() {
        guard let geometry = geometryStore.primaryGeometry, !geometry.isIdentity else { return }

        let applications = watcher.applicationElements()
        guard !applications.isEmpty else { return }

        // Every read and write below is a synchronous round trip into another process.
        // Walking the apps one after another takes long enough to see: the windows shuffle
        // into place a group at a time instead of snapping together with the bars. Fanning
        // out costs the slowest app rather than the sum of all of them.
        //
        // `NSScreen` is main-thread only, so the coordinate flip axis is read here and
        // carried into the workers.
        let referenceHeight = ScreenCoordinates.referenceHeight
        let lock = NSLock()
        var written: [AXElementKey: CGRect] = [:]

        DispatchQueue.concurrentPerform(iterations: applications.count) { index in
            var local: [AXElementKey: CGRect] = [:]
            for window in AppWatcher.windows(of: applications[index]) {
                guard let frame = Self.clamp(
                    window, to: geometry, referenceHeight: referenceHeight
                ) else { continue }
                local[AXElementKey(window.element)] = frame
            }

            guard !local.isEmpty else { return }
            lock.lock()
            written.merge(local) { _, new in new }
            lock.unlock()
        }

        lastWritten.merge(written) { _, new in new }
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

        let key = AXElementKey(window.element)
        guard let frame = Self.clamp(
            window,
            to: geometry,
            referenceHeight: ScreenCoordinates.referenceHeight,
            lastWritten: lastWritten[key]
        ) else { return }

        lastWritten[key] = frame
    }

    /// The clamp for a single window, touching nothing but its own arguments so the sweep
    /// can run it on any thread. Returns the frame to remember for that window, or `nil`
    /// when there is nothing to record.
    private static func clamp(
        _ window: AXWindow,
        to geometry: DisplayGeometry,
        referenceHeight: CGFloat,
        lastWritten: CGRect? = nil
    ) -> CGRect? {
        guard window.isStandard, !window.isMinimized, !window.isFullScreen else { return nil }
        guard let frame = window.frame(referenceHeight: referenceHeight) else { return nil }

        // The app is just echoing back the frame we set a moment ago.
        if let lastWritten, frame.isNearlyEqual(to: lastWritten) { return nil }

        guard let target = geometry.clamped(frame) else { return frame }

        window.setFrame(target, referenceHeight: referenceHeight)
        // Record the intent, not a read-back: apps routinely honour a resize only
        // partially, and re-reading here would just invite another round trip.
        return target
    }
}
