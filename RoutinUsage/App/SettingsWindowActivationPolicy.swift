import AppKit

@MainActor
enum SettingsWindowActivationPolicy {
    private static let trackedWindows = NSHashTable<NSWindow>.weakObjects()

    static var hasSettingsWindow: Bool {
        trackedWindows.allObjects.contains { window in
            window.isVisible && window.contentView != nil
        }
    }

    static func register(_ window: NSWindow) {
        trackedWindows.add(window)
        refresh()
    }

    static func unregister(_ window: NSWindow) {
        trackedWindows.remove(window)
        refresh()
    }

    static func refresh() {
        apply(hasSettingsWindow: hasSettingsWindow)
    }

    static func apply(
        hasSettingsWindow: Bool,
        setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Bool = { NSApp.setActivationPolicy($0) },
        activate: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        let policy: NSApplication.ActivationPolicy = hasSettingsWindow ? .regular : .accessory
        if setActivationPolicy(policy), hasSettingsWindow {
            activate()
        }
    }
}
