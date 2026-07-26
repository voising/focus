import AppKit

/// Plain AppKit entry point rather than a SwiftUI `App`: Focus is `LSUIElement`, owns no
/// scenes, and its only interface is an `NSStatusItem`.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
