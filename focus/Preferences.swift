import AppKit

/// User-visible state, persisted in `UserDefaults`. Anything that changes the geometry
/// funnels through `onChange` so the overlay and the clamper stay in step.
final class Preferences {

    static let shared = Preferences()

    private enum Key {
        static let isEnabled = "isEnabled"
        static let targetDiagonal = "targetDiagonal"
        static let panelDiagonalOverride = "panelDiagonalOverride"
        static let barsAboveWindows = "barsAboveWindows"
        static let hidesMenuBar = "hidesMenuBar"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutLabel = "shortcutLabel"
        static let shortcutDisabled = "shortcutDisabled"
    }

    static let targetRange: ClosedRange<Double> = 20.0 ... 34.0

    /// Diagonals of monitors people actually own. The picker shows the ones smaller than
    /// the attached panel — anything at or above it would be a no-op.
    static let standardSizes: [Double] = [20, 22, 24, 27, 30, 32, 34]

    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: false,
            Key.targetDiagonal: 27.0
        ])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Key.isEnabled)
            onChange?()
        }
    }

    var targetDiagonal: Double {
        get {
            min(max(defaults.double(forKey: Key.targetDiagonal), Self.targetRange.lowerBound),
                Self.targetRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, Self.targetRange.lowerBound), Self.targetRange.upperBound)
            guard abs(clamped - targetDiagonal) > 0.001 else { return }
            defaults.set(clamped, forKey: Key.targetDiagonal)
            onChange?()
        }
    }

    /// When true the frame is drawn over application windows, so the screen genuinely
    /// looks smaller. When false it sits on the wallpaper and only frames the desktop.
    var barsAboveWindows: Bool {
        get { defaults.object(forKey: Key.barsAboveWindows) as? Bool ?? true }
        set {
            guard newValue != barsAboveWindows else { return }
            defaults.set(newValue, forKey: Key.barsAboveWindows)
            onChange?()
        }
    }

    /// The menu bar cannot be moved into the working area, so the next best thing is to
    /// get it out of the black band entirely while the frame is up.
    var hidesMenuBar: Bool {
        get { defaults.object(forKey: Key.hidesMenuBar) as? Bool ?? true }
        set {
            guard newValue != hidesMenuBar else { return }
            defaults.set(newValue, forKey: Key.hidesMenuBar)
            onChange?()
        }
    }

    /// The system-wide toggle. `nil` means the user turned the shortcut off entirely,
    /// which is distinct from "never set one" — hence the separate disabled flag.
    var toggleShortcut: Shortcut? {
        get {
            guard !defaults.bool(forKey: Key.shortcutDisabled) else { return nil }
            guard let label = defaults.string(forKey: Key.shortcutLabel),
                  defaults.object(forKey: Key.shortcutKeyCode) != nil else {
                return .default
            }
            return Shortcut(
                keyCode: UInt16(defaults.integer(forKey: Key.shortcutKeyCode)),
                modifierFlags: NSEvent.ModifierFlags(
                    rawValue: UInt(defaults.integer(forKey: Key.shortcutModifiers))
                ),
                label: label
            )
        }
        set {
            guard newValue != toggleShortcut else { return }
            if let newValue {
                defaults.set(false, forKey: Key.shortcutDisabled)
                defaults.set(Int(newValue.keyCode), forKey: Key.shortcutKeyCode)
                defaults.set(Int(newValue.modifierFlags.rawValue), forKey: Key.shortcutModifiers)
                defaults.set(newValue.label, forKey: Key.shortcutLabel)
            } else {
                defaults.set(true, forKey: Key.shortcutDisabled)
            }
            onChange?()
        }
    }

    /// Set when the panel's EDID is missing or wrong. `nil` means "trust the display".
    var panelDiagonalOverride: Double? {
        get {
            let value = defaults.double(forKey: Key.panelDiagonalOverride)
            return value > 0 ? value : nil
        }
        set {
            defaults.set(newValue ?? 0, forKey: Key.panelDiagonalOverride)
            onChange?()
        }
    }
}
