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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }
        SettingsWindowActivationPolicy.register(window)
    }
}
