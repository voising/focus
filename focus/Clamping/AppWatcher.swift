import AppKit
import ApplicationServices

/// Subscribes to window lifecycle notifications for every ordinary running app and
/// forwards them as bare `AXUIElement`s. Knows nothing about geometry.
final class AppWatcher {

    /// Called on the main thread whenever a window appears, moves, resizes, or takes focus.
    var onWindowEvent: ((AXUIElement) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var applications: [pid_t: AXUIElement] = [:]
    private var isRunning = false

    private static let notifications: [String] = [
        kAXWindowCreatedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXFocusedWindowChangedNotification
    ]

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(applicationLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        for application in NSWorkspace.shared.runningApplications {
            observe(application)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)

        for (pid, observer) in observers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
            observers[pid] = nil
        }
        applications.removeAll()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Window enumeration

    /// One element per ordinary running app. Building these is a purely local operation,
    /// so unlike `start()` it costs nothing and can be called before observation begins.
    func applicationElements() -> [AXUIElement] {
        NSWorkspace.shared.runningApplications.compactMap(Self.element(for:))
    }

    /// Every window of one app. Split out from the app list so the initial sweep — no
    /// notification fires for windows that already exist — can fan out over the apps
    /// instead of paying for one round trip after another.
    static func windows(of application: AXUIElement) -> [AXWindow] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &value
        ) == .success,
            let elements = value as? [AXUIElement] else { return [] }
        return elements.map(AXWindow.init(element:))
    }

    // MARK: - Observation

    @objc private func applicationLaunched(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }
        observe(application)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }
        let pid = application.processIdentifier

        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        applications[pid] = nil
    }

    private static func element(for application: NSRunningApplication) -> AXUIElement? {
        guard application.activationPolicy == .regular else { return nil }

        let pid = application.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        let element = AXUIElementCreateApplication(pid)
        // An app that is beachballing will otherwise stall its caller on every attribute
        // read.
        AXUIElementSetMessagingTimeout(element, 1.0)
        return element
    }

    private func observe(_ application: NSRunningApplication) {
        let pid = application.processIdentifier
        guard observers[pid] == nil, let element = Self.element(for: application) else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let observer else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.notifications {
            AXObserverAddNotification(observer, element, notification as CFString, context)
        }

        // Common modes, so events keep arriving while a menu is tracking or a window is
        // being dragged.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        observers[pid] = observer
        applications[pid] = element
    }

    fileprivate func handle(element: AXUIElement) {
        onWindowEvent?(element)
    }
}

/// Must be a capture-free C function to be usable as an `AXObserverCallback`. It fires on
/// the main run loop because that is where the observer's source was added.
private let axObserverCallback: AXObserverCallback = { _, element, _, context in
    guard let context else { return }
    let watcher = Unmanaged<AppWatcher>.fromOpaque(context).takeUnretainedValue()
    watcher.handle(element: element)
}
