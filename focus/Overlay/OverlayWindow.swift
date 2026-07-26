import AppKit

/// A borderless, click-through window covering one screen, drawing the black frame.
///
/// Two stacking positions, chosen by the user:
///
/// * **Above windows** (`floatingWindow`) — the frame masks application windows, so the
///   display genuinely looks smaller. Deliberately below the Dock and the menu bar, both
///   of which stay visible and usable.
/// * **Below windows** (`desktopIconWindow`) — the frame only dresses the wallpaper.
///   Nothing can ever be clipped; a window dragged into the border just covers the bar.
final class OverlayWindow: NSWindow {

    private let barsView = BarsView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        contentView = barsView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ geometry: DisplayGeometry, aboveWindows: Bool, coversMenuBar: Bool) {
        setFrame(geometry.screenFrame, display: false)
        barsView.apply(barRects: geometry.barRects())
        updateLevel(aboveWindows: aboveWindows, coversMenuBar: coversMenuBar)
    }

    /// Split out from `apply` because the menu bar reveal changes the level many times a
    /// second and must not touch layout.
    func updateLevel(aboveWindows: Bool, coversMenuBar: Bool) {
        let raw: Int
        if coversMenuBar {
            // One above the status-item level, so the black band hides the menu bar and
            // its icons. Ordinary menus open at a far higher level and stay usable.
            raw = Int(CGWindowLevelForKey(.statusWindow)) + 1
        } else if aboveWindows {
            raw = Int(CGWindowLevelForKey(.floatingWindow))
        } else {
            raw = Int(CGWindowLevelForKey(.desktopIconWindow))
        }
        guard level.rawValue != raw else { return }
        level = NSWindow.Level(rawValue: raw)
    }

    func fade(to alpha: CGFloat, duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }
}

/// Four opaque black rectangles. Cheaper and more obviously correct than masking a single
/// layer with an even-odd path, and hit-testing is irrelevant since the window ignores
/// mouse events outright.
private final class BarsView: NSView {

    private let bars: [NSView] = (0 ..< 4).map { _ in
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bars.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(barRects: [CGRect]) {
        for (view, rect) in zip(bars, barRects) {
            view.frame = rect
            view.isHidden = rect.isEmpty
        }
    }
}
