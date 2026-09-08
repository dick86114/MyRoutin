import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    static let showSettingsWindow = Notification.Name("showSettingsWindow")
}

@MainActor
final class StatusBarController: NSObject {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var refreshMinutes: Int
    private var notificationsEnabled: Bool
    private var appearanceObservation: NSKeyValueObservation?
    private var appearanceUpdateScheduled = false
    /// 上一次绘制时菜单栏按钮的深浅状态；nil 表示还没画过。
    /// 相邻状态项频繁刷新会让 AppKit 反复重设按钮 appearance 并触发 KVO，
    /// 深浅没变时必须跳过重绘，否则高频文字测量会撞上 CoreText 的 nil-insert 竞态。
    private var lastDrawnMenuBarDark: Bool?
    private var popoverWindowResignObserver: NSObjectProtocol?
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?

    init(environment: AppEnvironment) {
        self.environment = environment
        refreshMinutes = environment.settings.refreshMinutes
        notificationsEnabled = environment.settings.notificationsEnabled
        super.init()

    }

    func start() {
        guard statusItem == nil else { return }
        registerStatusItem()
        observeEnvironment()
        applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreStatusItemIfNeeded()
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // 应用升级后旧进程可能暂时占用旧状态项位置，下一轮主循环再确认一次。
            try? await Task.sleep(for: .milliseconds(500))
            self.restoreStatusItemIfNeeded()
            await self.environment.start()
            self.environment.presentUpdateCompletionNoticeIfNeeded()
        }
    }

    private func registerStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        lastDrawnMenuBarDark = nil
        logStatusItem("创建")
        configurePopover()
        configureStatusButton()
        observeStatusBarAppearance()
        updateStatusButton()
    }

    private func restoreStatusItemIfNeeded() {
        guard let statusItem else {
            logStatusItem("恢复时为空")
            registerStatusItem()
            return
        }
        logStatusItem("恢复前")
        guard let window = statusItem.button?.window, isUsableStatusItemWindow(window) else {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            registerStatusItem()
            return
        }
        statusItem.isVisible = true
        updateStatusButton()
    }

    private func isUsableStatusItemWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.frame.width > 0, window.frame.height > 0 else {
            return false
        }
        return NSScreen.screens.contains { screen in
            screen.frame.intersects(window.frame)
        }
    }

    private func logStatusItem(_ stage: String) {
        let button = statusItem?.button
        let title = button?.title ?? ""
        let window = button?.window
        let message = "[MyToken 状态栏] \(stage) item=\(statusItem != nil) button=\(button != nil) window=\(window != nil) windowVisible=\(window?.isVisible ?? false) frame=\(window?.frame ?? .zero) buttonFrame=\(button?.frame ?? .zero) visible=\(statusItem?.isVisible ?? false) length=\(statusItem?.length ?? -1) title=\(title) image=\(button?.image != nil) policy=\(NSApp.activationPolicy().rawValue)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private func configurePopover() {
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: StatusPopoverContent(
                environment: environment,
                openSettings: { [weak self] in
                    self?.openSettingsWindow()
                }
            )
        )
        // 让窗口尺寸始终跟随 SwiftUI 内容的理想高度，
        // 避免后台数据变化后重新打开时窗口尺寸过期（内容居中、上下留白）。
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func configureStatusButton() {
        guard let statusItem, let button = statusItem.button else {
            return
        }
        statusItem.isVisible = true
        statusItem.length = 24
        button.target = self
        button.action = #selector(handleStatusButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageRight
        button.imageScaling = .scaleProportionallyDown
    }

    private func observeStatusBarAppearance() {
        guard let button = statusItem?.button else {
            appearanceObservation = NSApp.observe(\NSApplication.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusButton()
                }
            }
            return
        }
        // 监听状态栏按钮的 appearance（由系统根据壁纸实时调整），
        // 而不是 NSApp.effectiveAppearance（跟随系统设置），确保反色和其他 app 一致。
        // 注意：外观切换传播期间直接重画图标会让 CoreText 抛异常（SIGABRT），
        // 必须推迟到下一个 runloop，等 AppKit 完成传播后再绘制。
        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let button = self.statusItem?.button else { return }
                let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                guard isDark != self.lastDrawnMenuBarDark else { return }
                self.scheduleStatusButtonUpdate()
            }
        }
    }

    private func scheduleStatusButtonUpdate() {
        guard !appearanceUpdateScheduled else { return }
        appearanceUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.statusItem != nil else { return }
            self.appearanceUpdateScheduled = false
            self.updateStatusButton()
        }
    }

    private func observeEnvironment() {
        withObservationTracking {
            _ = environment.settings.menuBarStyle
            _ = environment.settings.refreshMinutes
            _ = environment.settings.notificationsEnabled
            _ = environment.settings.displayOrder
            for id in environment.store.orderedKeyIDs {
                _ = environment.settings.usagePreferences(for: id)
            }
            _ = environment.store.states
            _ = environment.updateStatus
            _ = environment.routinCheckIn.state
            _ = environment.codexGroupDetection.states
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.synchronizeEnvironmentChanges()
                self?.observeEnvironment()
            }
        }
    }

    private func synchronizeEnvironmentChanges() {
        let settings = environment.settings
        if refreshMinutes != settings.refreshMinutes {
            refreshMinutes = settings.refreshMinutes
            environment.refreshIntervalDidChange(to: refreshMinutes)
        }
        if notificationsEnabled != settings.notificationsEnabled {
            notificationsEnabled = settings.notificationsEnabled
            Task { await environment.notificationsDidChange(enabled: notificationsEnabled) }
        }
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let statusItem, let button = statusItem.button else {
            return
        }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let enabledIDs = Set(environment.store.visibleKeyIDs)
        let visibility = environment.settings.displayOrder.visible(enabledIDs: enabledIDs)
        let selectedIndicators = visibility.menuBarIDs.compactMap { id -> MenuBarIndicatorModel? in
            guard let state = environment.store.state(for: id),
                  let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == state.configuration.providerID })
            else { return nil }
            let preferences = environment.settings.usagePreferences(for: id)
            let capabilities = environment.providerRegistry?.metricCapabilities(for: state.configuration) ?? []
            let resolution = MenuBarMetricResolver.resolve(
                selectedMetricID: preferences.menuBarMetricID,
                metrics: state.snapshot?.normalizedMetrics ?? [],
                capabilities: capabilities
            )
            return MenuBarIndicatorModel.make(
                state: state,
                descriptor: descriptor,
                metric: resolution.metric
            )
        }
        if !selectedIndicators.isEmpty {
            let displayedCount = min(selectedIndicators.count, MenuBarMultiUsageIcon.maximumCount)
            let imageWidth = MenuBarMultiUsageIcon.imageWidth(for: displayedCount)
            statusItem.length = imageWidth + 8
            button.title = ""
            button.image = MenuBarMultiUsageIcon.image(
                indicators: selectedIndicators,
                appearance: button.effectiveAppearance
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            let hoverSummary = MenuBarIndicatorModel.hoverSummary(for: selectedIndicators)
            button.setAccessibilityLabel(hoverSummary)
            button.toolTip = hoverSummary
            lastDrawnMenuBarDark = isDark
            return
        }
        let state: KeyUsageState? = nil
        let text = "尚未配置 Key"
        statusItem.length = 24
        button.title = ""
        button.image = NSImage(named: "MenuBarLogoMask")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        lastDrawnMenuBarDark = isDark
        button.setAccessibilityLabel(text)
        button.toolTip = helpText(for: state)
    }

    private func helpText(for state: KeyUsageState?) -> String {
        guard let state else {
            return "尚未配置 Key"
        }
        var parts = [state.configuration.displayName]
        if let lastSuccessAt = state.lastSuccessAt {
            parts.append("最后更新 \(lastSuccessAt.formatted(date: .omitted, time: .shortened))")
        } else {
            parts.append("尚未更新")
        }
        if state.isRefreshing || state.isStale || state.error != nil {
            parts.append(UsageFormatter.statusText(state: state))
        }
        return parts.joined(separator: " · ")
    }

    @objc private func handleStatusButtonClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let contentSize = popoverContentSize(for: button)
            popover.contentSize = contentSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            configurePopoverWindow(contentSize: contentSize, anchoredTo: button)
        }
    }

    private func configurePopoverWindow(contentSize: NSSize, anchoredTo button: NSStatusBarButton) {
        guard let window = popover.contentViewController?.view.window else {
            return
        }
        window.contentViewController?.preferredContentSize = contentSize
        window.setContentSize(contentSize)
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        positionPopoverWindow(window, anchoredTo: button)

        // 打开瞬间 SwiftUI 可能还没用最新数据完成布局，fittingSize 会过期。
        // 下一轮 runloop 再校准一次窗口尺寸和位置。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            let refreshedSize = self.popoverContentSize(for: button)
            guard window.frame.size != refreshedSize else { return }
            window.contentViewController?.preferredContentSize = refreshedSize
            window.setContentSize(refreshedSize)
            self.positionPopoverWindow(window, anchoredTo: button)
        }

        if let popoverWindowResignObserver {
            NotificationCenter.default.removeObserver(popoverWindowResignObserver)
        }
        popoverWindowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    private func positionPopoverWindow(_ popoverWindow: NSWindow, anchoredTo button: NSStatusBarButton) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? button.window?.screen
            ?? popoverWindow.screen
            ?? NSScreen.main
        guard let screen else { return }

        let anchorRect = button.window?.convertToScreen(button.bounds) ?? .zero
        let origin = PopoverWindowPlacement.origin(
            popoverSize: popoverWindow.frame.size,
            anchorRect: anchorRect,
            visibleFrame: screen.visibleFrame
        )
        popoverWindow.setFrameOrigin(origin)
    }

    private func popoverContentSize(for button: NSStatusBarButton) -> NSSize {
        let screenHeight = button.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 800
        let maximumHeight = screenHeight * 0.9
        let idealSize = popover.contentViewController?.view.fittingSize
            ?? NSSize(width: 440, height: 0)

        return NSSize(
            width: idealSize.width == 0 ? 440 : idealSize.width,
            height: min(max(idealSize.height, 1), maximumHeight)
        )
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let statusItem else { return }
        popover.performClose(nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.presentationStyle = .regular

        let settingsItem = NSMenuItem(
            title: "设置",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: "检查更新",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        checkForUpdatesItem.isEnabled = environment.updateStatus != .checking
            && !isDownloadingUpdate
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())

        let issueItem = NSMenuItem(
            title: "提交问题",
            action: #selector(submitIssueReport),
            keyEquivalent: ""
        )
        issueItem.target = self
        menu.addItem(issueItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MyToken",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        defer { statusItem.menu = nil }
        button.performClick(nil)
    }

    @objc private func checkForUpdates() {
        Task { await environment.checkForUpdates() }
    }

    @objc private func submitIssueReport() {
        Task { await environment.openIssueReport() }
    }

    private var isDownloadingUpdate: Bool {
        if case .downloading = environment.updateStatus {
            return true
        }
        return false
    }

    @objc private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Notification.Name.showSettingsWindow, object: nil)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

enum PopoverWindowPlacement {
    /// NSPopover 在设置窗口跨屏后可能跟随主屏；这里根据被点击的状态按钮重新落位。
    static func origin(
        popoverSize: NSSize,
        anchorRect: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        let preferredX = anchorRect.midX - popoverSize.width / 2
        let minimumX = visibleFrame.minX
        let maximumX = max(minimumX, visibleFrame.maxX - popoverSize.width)
        let x = min(max(preferredX, minimumX), maximumX)
        let y = visibleFrame.maxY - popoverSize.height
        return NSPoint(x: x, y: y)
    }
}

@MainActor
private struct StatusPopoverContent: View {
    @Bindable var environment: AppEnvironment
    let openSettings: @MainActor () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        UsagePopoverView(
            store: environment.store,
            settings: environment.settings,
            codexGroupDetection: environment.codexGroupDetection,
            updateStatus: environment.updateStatus,
            installAvailableUpdate: environment.installAvailableUpdate,
            startCodexGroupDetection: environment.startCodexGroupDetection(for:),
            openSettings: openSettings
        )
        .sheet(isPresented: $environment.showsOnboarding) {
            OnboardingView(store: environment.store) {
                environment.dismissOnboarding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.showSettingsWindow)) { _ in
            openWindow(id: "settings")
        }
    }
}
