import AppKit

/// Captures the next key combination the user presses, anywhere on the system.
///
/// No panel and no window: Focus is a menu-bar agent with nothing to focus, so opening a
/// window just to read one keystroke would mean stealing the frontmost app's focus and
/// handing it back. A pair of event monitors does the same job invisibly.
final class ShortcutRecorder {

    /// Long enough to think, short enough that a forgotten recording session ends itself.
    private static let timeout: TimeInterval = 6

    private(set) var isRecording = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var timeoutTimer: Timer?
    private var completion: ((Shortcut?) -> Void)?

    /// Calls back with the captured shortcut, or `nil` if the user pressed Escape or let
    /// it time out. Requires Accessibility, same as the window clamping.
    func record(completion: @escaping (Shortcut?) -> Void) {
        cancel()

        self.completion = completion
        isRecording = true

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        // The local monitor catches the case where Focus itself is frontmost, and swallows
        // the event so it cannot reach anything else.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeout, repeats: false) { [weak self] _ in
            self?.finish(with: nil)
        }
    }

    func cancel() {
        guard isRecording else { return }
        finish(with: nil)
    }

    private func handle(_ event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == 53 { // Escape
            finish(with: nil)
            return
        }

        // Ignore bare modifier presses and unusable combinations; keep listening so the
        // user can simply try again without restarting.
        guard let shortcut = Shortcut(event: event) else { return }
        finish(with: shortcut)
    }

    private func finish(with shortcut: Shortcut?) {
        let completion = self.completion
        self.completion = nil
        isRecording = false

        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil

        timeoutTimer?.invalidate()
        timeoutTimer = nil

        completion?(shortcut)
    }
}
