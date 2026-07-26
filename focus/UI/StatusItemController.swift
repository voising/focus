import AppKit
import ServiceManagement

/// The menu-bar UI. Owns no state of its own — it reads `Preferences` on every open and
/// writes back through it, so the rest of the app only ever hears about changes once.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let preferences: Preferences
    private let geometryStore: GeometryStore

    /// Set by the delegate after each registration attempt, so the menu can say so when
    /// another app already owns the combination.
    var shortcutUnavailable = false

    private let recorder = ShortcutRecorder()
    private let menu = NSMenu()
    private var sizePickerView: SizePickerMenuItemView?

    private var enableItem: NSMenuItem?
    private var panelItem: NSMenuItem?
    private var workingAreaItem: NSMenuItem?
    private var coverItem: NSMenuItem?
    private var hideMenuBarItem: NSMenuItem?
    private var shortcutItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    private static let panelPresets: [Double] = [24, 27, 32, 34, 38, 42]

    init(preferences: Preferences, geometryStore: GeometryStore) {
        self.preferences = preferences
        self.geometryStore = geometryStore
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.inset.filled",
            accessibilityDescription: "Focus"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = menu
        menu.delegate = self

        buildMenu()
    }

    // MARK: - Construction

    private func buildMenu() {
        let enable = NSMenuItem(
            title: "Shrink Display",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enable.target = self
        menu.addItem(enable)
        enableItem = enable

        menu.addItem(.separator())

        let picker = SizePickerMenuItemView(title: "Make my screen feel like") { [weak self] size in
            self?.preferences.targetDiagonal = size
        }
        let pickerItem = NSMenuItem()
        pickerItem.view = picker
        menu.addItem(pickerItem)
        sizePickerView = picker

        let workingArea = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        workingArea.isEnabled = false
        menu.addItem(workingArea)
        workingAreaItem = workingArea

        let panel = NSMenuItem(title: "Panel size", action: nil, keyEquivalent: "")
        panel.submenu = buildPanelSubmenu()
        menu.addItem(panel)
        panelItem = panel

        menu.addItem(.separator())

        let cover = NSMenuItem(
            title: "Frame Covers Windows",
            action: #selector(toggleBarsAboveWindows),
            keyEquivalent: ""
        )
        cover.target = self
        menu.addItem(cover)
        coverItem = cover

        let hideMenuBar = NSMenuItem(
            title: "Hide Menu Bar While Shrunk",
            action: #selector(toggleHidesMenuBar),
            keyEquivalent: ""
        )
        hideMenuBar.target = self
        menu.addItem(hideMenuBar)
        hideMenuBarItem = hideMenuBar

        menu.addItem(.separator())

        let accessibility = NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(grantAccessibility),
            keyEquivalent: ""
        )
        accessibility.target = self
        menu.addItem(accessibility)
        accessibilityItem = accessibility

        let shortcut = NSMenuItem(
            title: "Change Shortcut…",
            action: #selector(changeShortcut),
            keyEquivalent: ""
        )
        shortcut.target = self
        menu.addItem(shortcut)
        shortcutItem = shortcut

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        let debug = NSMenuItem(
            title: "Copy Debug Info",
            action: #selector(copyDebugInfo),
            keyEquivalent: ""
        )
        debug.target = self
        menu.addItem(debug)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Focus", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func buildPanelSubmenu() -> NSMenu {
        let submenu = NSMenu()

        // Spelled out because this submenu is easy to mistake for the target size, and
        // setting it equal to the target silently turns the whole effect off.
        let header = NSMenuItem(
            title: "How big your monitor actually is —",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        submenu.addItem(header)
        let subheader = NSMenuItem(title: "only change this if it is wrong", action: nil, keyEquivalent: "")
        subheader.isEnabled = false
        submenu.addItem(subheader)
        submenu.addItem(.separator())

        let detected = NSMenuItem(
            title: "Use detected size",
            action: #selector(useDetectedPanelSize),
            keyEquivalent: ""
        )
        detected.target = self
        submenu.addItem(detected)
        submenu.addItem(.separator())

        for preset in Self.panelPresets {
            let item = NSMenuItem(
                title: String(format: "My monitor is %.0f\"", preset),
                action: #selector(selectPanelSize(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            submenu.addItem(item)
        }

        return submenu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        refreshState()
    }

    private func refreshState() {
        let isEnabled = preferences.isEnabled
        enableItem?.state = isEnabled ? .on : .off

        // Showing it as the item's key equivalent both documents the shortcut and makes
        // it work while the menu itself is open.
        if let shortcut = preferences.toggleShortcut {
            enableItem?.keyEquivalent = shortcut.label.lowercased()
            enableItem?.keyEquivalentModifierMask = shortcut.modifierFlags
            shortcutItem?.title = shortcutUnavailable
                ? "Shortcut \(shortcut.displayString) is taken — change…"
                : "Change Shortcut (\(shortcut.displayString))…"
        } else {
            enableItem?.keyEquivalent = ""
            enableItem?.keyEquivalentModifierMask = []
            shortcutItem?.title = "Set Shortcut…"
        }

        let detected = geometryStore.detectedPanelDiagonal
        let effective = geometryStore.effectivePanelDiagonal

        // Only sizes actually smaller than the attached panel: picking the panel's own
        // size would silently turn the whole effect off.
        let available = Preferences.standardSizes.filter { $0 < effective - 0.5 }
        sizePickerView?.configure(sizes: available, selected: preferences.targetDiagonal)
        sizePickerView?.isEnabled = isEnabled

        // A stored value from an older build, or from a bigger monitor, would otherwise
        // leave every button looking unselected.
        if let index = SizePickerMenuItemView.nearestIndex(to: preferences.targetDiagonal, in: available),
           abs(available[index] - preferences.targetDiagonal) > 0.01 {
            preferences.targetDiagonal = available[index]
        }

        coverItem?.state = preferences.barsAboveWindows ? .on : .off
        hideMenuBarItem?.state = preferences.hidesMenuBar ? .on : .off

        if let geometry = geometryStore.primaryGeometry {
            workingAreaItem?.title = geometry.isIdentity
                ? "No effect — working area matches the display"
                : String(
                    format: "Working area: %.0f × %.0f pt",
                    geometry.innerRect.width,
                    geometry.innerRect.height
                )
        }
        let source = preferences.panelDiagonalOverride == nil
            ? (detected == nil ? "assumed" : "detected")
            : "manual"
        panelItem?.title = String(format: "Panel size: %.1f\" (%@)", effective, source)

        for item in panelItem?.submenu?.items ?? [] {
            if let preset = item.representedObject as? Double {
                item.state = preferences.panelDiagonalOverride == preset ? .on : .off
            } else {
                item.state = preferences.panelDiagonalOverride == nil ? .on : .off
                item.isEnabled = detected != nil
            }
        }

        // Only worth showing while the permission is actually missing.
        accessibilityItem?.isHidden = WindowClamper.isTrusted
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        preferences.isEnabled.toggle()
        if preferences.isEnabled {
            WindowClamper.requestTrust()
        }
    }

    /// The menu closes the moment this is clicked, so the status item itself becomes the
    /// prompt — there is nowhere else to put one in a menu-bar-only app.
    @objc private func changeShortcut() {
        let button = statusItem.button
        let restoreImage = button?.image
        button?.image = nil
        button?.title = "Press keys…"

        recorder.record { [weak self] shortcut in
            button?.title = ""
            button?.image = restoreImage
            guard let shortcut else { return }
            self?.preferences.toggleShortcut = shortcut
        }
    }

    @objc private func toggleHidesMenuBar() {
        preferences.hidesMenuBar.toggle()
    }

    @objc private func toggleBarsAboveWindows() {
        preferences.barsAboveWindows.toggle()
    }

    @objc private func useDetectedPanelSize() {
        preferences.panelDiagonalOverride = nil
    }

    @objc private func selectPanelSize(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? Double else { return }
        preferences.panelDiagonalOverride = preset
    }

    @objc private func grantAccessibility() {
        WindowClamper.requestTrust()
        WindowClamper.openAccessibilitySettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Focus: could not change login item: \(error.localizedDescription)")
        }
    }

    /// Everything needed to diagnose a wrong-looking frame in one paste: the screen the
    /// maths was done against, the panel size it believed, and the rectangles it produced.
    @objc private func copyDebugInfo() {
        guard let geometry = geometryStore.primaryGeometry else { return }
        let text = """
        Focus debug info
        screen.frame      \(NSStringFromRect(geometry.screenFrame))
        screen.visible    \(NSStringFromRect(geometry.visibleFrame))
        panel diagonal    \(String(format: "%.2f\"", geometry.panelDiagonal)) \
        (detected: \(geometryStore.detectedPanelDiagonal.map { String(format: "%.2f\"", $0) } ?? "none"))
        target diagonal   \(String(format: "%.2f\"", geometry.targetDiagonal))
        scale             \(String(format: "%.5f", geometry.scale))
        innerRect         \(NSStringFromRect(geometry.innerRect))
        clampRect         \(NSStringFromRect(geometry.clampRect))
        accessibility     \(WindowClamper.isTrusted ? "granted" : "NOT granted")
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
