import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferences = Preferences.shared
    private lazy var geometryStore = GeometryStore(preferences: preferences)
    private lazy var overlayController = OverlayController(
        geometryProvider: { [geometryStore] in geometryStore.geometries() },
        aboveWindowsProvider: { [preferences] in preferences.barsAboveWindows }
    )
    private let menuBarHover = MenuBarHoverMonitor()
    private let hotKeyCenter = HotKeyCenter()
    private let watcher = AppWatcher()
    private lazy var clamper = WindowClamper(watcher: watcher, geometryStore: geometryStore)
    private var statusItemController: StatusItemController?

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests use this app as their host, so a plain `xcodebuild test` would
        // otherwise hide the menu bar and start shoving windows around on whatever machine
        // is running them — and the test runner kills the host without ever calling
        // applicationWillTerminate, so none of it gets undone.
        guard !Self.isRunningTests else { return }

        statusItemController = StatusItemController(
            preferences: preferences,
            geometryStore: geometryStore
        )

        preferences.onChange = { [weak self] in
            self?.applyPreferences()
        }

        menuBarHover.onChange = { [weak self] _ in
            self?.updateMenuBarMasking()
        }

        hotKeyCenter.onTrigger = { [weak self] in
            guard let self else { return }
            preferences.isEnabled.toggle()
        }

        applyPreferences()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController.setActive(false)
        clamper.setActive(false)
        menuBarHover.stop()
    }

    /// True when the stored shortcut could not be claimed, usually because another app
    /// already owns the combination.
    private(set) var isShortcutUnavailable = false

    private func applyPreferences() {
        let isEnabled = preferences.isEnabled

        let shortcut = preferences.toggleShortcut
        if shortcut != hotKeyCenter.current {
            let registered = hotKeyCenter.register(shortcut)
            isShortcutUnavailable = shortcut != nil && !registered
        }

        // Without this the clamper silently does nothing on a launch that was already
        // enabled, since the prompt would otherwise only appear when toggling the menu.
        if isEnabled, !WindowClamper.isTrusted {
            WindowClamper.requestTrust()
        }

        overlayController.setActive(isEnabled)
        overlayController.refresh()

        clamper.setActive(isEnabled)
        clamper.refresh()

        updateMenuBarMasking()

        statusItemController?.shortcutUnavailable = isShortcutUnavailable
    }

    /// The frame can only sensibly swallow the menu bar when it is already drawing over
    /// windows — otherwise it would jump from behind everything to in front of everything.
    private func updateMenuBarMasking() {
        let masksMenuBar = preferences.isEnabled
            && preferences.barsAboveWindows
            && preferences.hidesMenuBar

        if masksMenuBar {
            menuBarHover.start()
        } else {
            menuBarHover.stop()
        }

        overlayController.setCoversMenuBar(masksMenuBar && !menuBarHover.isPointerAtMenuBar)
    }
}
