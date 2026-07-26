import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, stored in the form both AppKit and Carbon need.
///
/// `label` is captured from the originating key event rather than reverse-mapped from the
/// key code: layouts differ, and the character the user actually pressed is the only
/// honest thing to show them.
struct Shortcut: Equatable {

    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let label: String

    static let `default` = Shortcut(
        keyCode: UInt16(kVK_ANSI_F),
        modifierFlags: [.control, .option, .command],
        label: "F"
    )

    /// At least one non-shift modifier, or the shortcut would swallow ordinary typing.
    var isValid: Bool {
        !modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    /// Carbon's modifier mask, which is what `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// Apple's canonical ordering: Control, Option, Shift, Command.
    var displayString: String {
        var text = ""
        if modifierFlags.contains(.control) { text += "⌃" }
        if modifierFlags.contains(.option) { text += "⌥" }
        if modifierFlags.contains(.shift) { text += "⇧" }
        if modifierFlags.contains(.command) { text += "⌘" }
        return text + label
    }

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, label: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.label = label
    }

    /// Builds a shortcut from a key-down event, or `nil` if it is not usable as one.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])

        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let label = Self.specialKeyLabels[event.keyCode]
            ?? (characters.isEmpty ? "" : characters)
        guard !label.isEmpty else { return nil }

        self.init(keyCode: event.keyCode, modifierFlags: flags, label: label)
        guard isValid else { return nil }
    }

    /// Keys whose `charactersIgnoringModifiers` is unprintable or misleading.
    private static let specialKeyLabels: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓"
    ]
}
