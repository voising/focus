import AppKit
import Carbon.HIToolbox

/// Registers one system-wide hotkey.
///
/// Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor: it needs no
/// permission of its own, and it *consumes* the keystroke, so the shortcut does not also
/// leak through to whatever app happens to be frontmost.
final class HotKeyCenter {

    /// Arbitrary but stable four-char code identifying our hotkey to Carbon.
    private static let signature: OSType = 0x464F_4353 // 'FOCS'

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var current: Shortcut?

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        unregister()

        guard let shortcut, shortcut.isValid else { return false }

        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        NSLog("Focus: RegisterEventHotKey(%@) -> status %d", shortcut.displayString, status)

        // Fails when another app already owns the combination — the caller surfaces that
        // rather than leaving the user wondering why nothing happens.
        guard status == noErr, let reference else { return false }

        hotKeyRef = reference
        current = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    fileprivate func trigger() {
        onTrigger?()
    }
}

/// Capture-free, as a Carbon `EventHandlerUPP` must be. Carbon dispatches on the main
/// thread, which is where everything downstream expects to run.
private let hotKeyEventHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return noErr }
    Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().trigger()
    return noErr
}
