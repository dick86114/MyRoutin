import AppKit
import SwiftUI

/// 新设置窗口存在时临时显示 Dock 图标，关闭后恢复菜单栏应用形态。
struct SettingsWindowDockIconAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowDockIconView {
        SettingsWindowDockIconView()
    }

    func updateNSView(_ nsView: SettingsWindowDockIconView, context: Context) {}
}

final class SettingsWindowDockIconView: NSView {
    private weak var observedWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        closeObserver.map(NotificationCenter.default.removeObserver)
        closeObserver = nil
        if let observedWindow {
            SettingsWindowActivationPolicy.unregister(observedWindow)
            self.observedWindow = nil
        }

        guard let window else {
            if let observedWindow {
                SettingsWindowActivationPolicy.unregister(observedWindow)
                self.observedWindow = nil
            }
            return
        }
        SettingsWindowActivationPolicy.register(window)
        observedWindow = window
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else {
                return
            }
            MainActor.assumeIsolated {
                SettingsWindowActivationPolicy.unregister(window)
            }
        }
    }
}
