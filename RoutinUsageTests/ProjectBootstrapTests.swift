import XCTest
@testable import RoutinUsage

final class ProjectBootstrapTests: XCTestCase {
    func test应用标识稳定() {
        XCTAssertEqual(RoutinUsageApp.applicationName, "MyToken")
    }

    func test正式应用使用新的状态栏身份并保留旧偏好迁移() throws {
        let project = try sourceText(at: "project.yml")
        let environment = try sourceText(at: "RoutinUsage/App/AppEnvironment.swift")

        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: cc.idickies.mytoken"))
        XCTAssertTrue(environment.contains("UserDefaultsMigration.migrateCompatiblePreferences()"))
    }

    func test应用提供版本号与官网和GitHub地址() throws {
        XCTAssertFalse(RoutinUsageApp.currentVersion.isEmpty)
        XCTAssertEqual(RoutinUsageApp.websiteURL.absoluteString, "https://mytoken.idickies.cc")
        XCTAssertEqual(
            RoutinUsageApp.githubURL.absoluteString,
            "https://github.com/dick86114/MyToken"
        )
        XCTAssertEqual(
            RoutinUsageApp.releasesURL.absoluteString,
            "https://github.com/dick86114/MyToken/releases"
        )
    }

    func test菜单栏弹窗左侧版本号可点击并链接到Releases() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let app = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(app.contains("nonisolated static var currentVersion"))
        XCTAssertTrue(app.contains("nonisolated static let githubURL"))
        XCTAssertTrue(app.contains("nonisolated static let releasesURL"))
        XCTAssertTrue(popover.contains("Link(destination: RoutinUsageApp.releasesURL)"))
        XCTAssertTrue(popover.contains("RoutinUsageApp.currentVersion"))
        XCTAssertTrue(popover.contains("打开 Releases 页面"))
        XCTAssertFalse(popover.contains(".underline()"))
    }

    func test菜单栏弹窗顶部使用左版本中彩色透明Logo右刷新布局() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let app = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(app.contains("nonisolated static let websiteURL"))
        XCTAssertTrue(popover.contains("Link(destination: RoutinUsageApp.websiteURL)"))
        XCTAssertTrue(popover.contains("Image(nsImage: NSImage(named: \"PopoverColorBrandLogo\")"))
        XCTAssertTrue(popover.contains("frame(width: 32, height: 32)"))
        XCTAssertTrue(popover.contains("strokeBorder("))
        XCTAssertTrue(popover.contains(".shadow(color: .white.opacity(0.16)"))
        XCTAssertTrue(popover.contains("repeatForever"))
        XCTAssertTrue(popover.contains("打开 MyToken 官网"))
        XCTAssertTrue(popover.contains(".overlay(alignment: .center)"))
        XCTAssertTrue(popover.contains("Image(systemName: store.isRefreshing ? \"arrow.triangle.2.circlepath\" : \"arrow.clockwise\")"))
        XCTAssertTrue(popover.contains("刷新全部 Key"))
        XCTAssertFalse(popover.contains("if hasRoutinAccount"))
        XCTAssertFalse(popover.contains("checkInHelpText"))
        XCTAssertFalse(popover.contains("Picker(\"用量周期\""))
    }

    func test应用图标使用已归档的MyToken品牌原图生成完整尺寸集() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let brandLogo = projectRoot
            .appendingPathComponent("docs/brand-assets/mytoken-brand-logo.png")
        let appIconDirectory = projectRoot
            .appendingPathComponent("RoutinUsage/Assets.xcassets/AppIcon.appiconset")
        let expectedIconNames = [
            "icon_16x16.png",
            "icon_16x16@2x.png",
            "icon_32x32.png",
            "icon_32x32@2x.png",
            "icon_128x128.png",
            "icon_128x128@2x.png",
            "icon_256x256.png",
            "icon_256x256@2x.png",
            "icon_512x512.png",
            "icon_512x512@2x.png"
        ]

        XCTAssertTrue(FileManager.default.fileExists(atPath: brandLogo.path))
        for iconName in expectedIconNames {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: appIconDirectory.appendingPathComponent(iconName).path
                )
            )
        }
    }

    func test菜单栏Logo原图使用最新品牌资源() throws {
        let menuBarLogo = try XCTUnwrap(
            Bundle(for: ProjectBootstrapTests.self).url(
                forResource: "routin-menu-bar-logo-source",
                withExtension: "png"
            )
        )
        let image = try XCTUnwrap(NSImage(contentsOf: menuBarLogo))

        XCTAssertEqual(image.size, NSSize(width: 1675, height: 1782))
    }

    func test菜单栏弹窗同屏展示五小时与周用量() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let row = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        XCTAssertFalse(popover.contains("dimension: settings.displayDimension"))
        XCTAssertTrue(row.contains("periodicContent"))
        XCTAssertTrue(row.contains("title: \"5 小时\""))
        XCTAssertTrue(row.contains("title: \"周\""))
    }

    func test菜单栏使用原生状态栏按钮承载左右键交互() throws {
        let source = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(source.contains("StatusBarController(environment: environment)"))
        XCTAssertTrue(source.contains("@State private var statusBarController"))
        XCTAssertFalse(source.contains("MenuBarExtra"))
    }

    func test真实菜单栏和弹窗读取独立展示顺序() throws {
        let controller = try TestSourceReader.read([
            "RoutinUsage", "App", "StatusBarController.swift"
        ])
        let popover = try TestSourceReader.read([
            "RoutinUsage", "Views", "UsagePopoverView.swift"
        ])

        XCTAssertTrue(controller.contains("displayOrder.visible(enabledIDs:"))
        XCTAssertTrue(controller.contains("visibility.menuBarIDs"))
        XCTAssertTrue(popover.contains("displayOrder.visible(enabledIDs:"))
        XCTAssertTrue(popover.contains("visibility.popoverIDs"))
        XCTAssertFalse(popover.contains("LegacyCredentialDisplayOrder.popoverIDs"))
        XCTAssertFalse(popover.contains("settings.availableCredentialIDs"))
    }

    func test凭证管理页复用弹窗卡片并支持详情() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/CredentialManagementView.swift")

        XCTAssertTrue(settings.contains("UsageRowView("))
        XCTAssertTrue(settings.contains("LazyVGrid"))
        XCTAssertTrue(settings.contains("CredentialDetailsView"))
    }

    func test状态栏控制器在应用启动完成后异步安装() throws {
        let source = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(source.contains("applicationDidFinishLaunching"))
        XCTAssertTrue(source.contains("NSApp.setActivationPolicy(.accessory)"))
        XCTAssertTrue(source.contains("SettingsWindowActivationPolicy.refresh()"))
        XCTAssertTrue(source.contains("let controller = StatusBarController(environment: environment)"))
        XCTAssertTrue(source.contains("retainedStatusBarController = controller"))
        XCTAssertTrue(source.contains("controller.start()"))

        let installRange = try XCTUnwrap(
            source.range(of: "controller.start()")
        )
        let refreshRange = try XCTUnwrap(
            source.range(of: "SettingsWindowActivationPolicy.refresh()")
        )
        XCTAssertLessThan(refreshRange.lowerBound, installRange.lowerBound)
    }

    func testDebug使用独立BundleID避免复用系统菜单栏状态() throws {
        let project = try sourceText(at: "project.yml")
        let testScript = try sourceText(at: "scripts/test.sh")

        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: ai.routin.mytoken.debug.v3"))
        XCTAssertTrue(testScript.contains("PRODUCT_BUNDLE_IDENTIFIER=ai.routin.mytoken.tests"))
    }

    func test关闭最后一个设置窗口后应用仍驻留菜单栏() throws {
        let source = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(source.contains("@NSApplicationDelegateAdaptor(RoutinUsageAppDelegate.self)"))
        XCTAssertTrue(source.contains("applicationShouldTerminateAfterLastWindowClosed"))
        XCTAssertTrue(source.contains("return false"))
    }

    func test菜单栏标签提供应用操作菜单但不提供账号选择() throws {
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(statusBarController.contains("button.sendAction(on: [.leftMouseUp, .rightMouseUp])"))
        XCTAssertTrue(statusBarController.contains("button.imagePosition = .imageRight"))
        XCTAssertTrue(statusBarController.contains("NSApp.currentEvent?.type == .rightMouseUp"))
        XCTAssertFalse(statusBarController.contains("切换账号"))
        XCTAssertFalse(statusBarController.contains("environment.store.selectKey(id)"))
        XCTAssertFalse(statusBarController.contains("selectedKeyID"))
        XCTAssertTrue(statusBarController.contains("设置"))
        XCTAssertTrue(statusBarController.contains("Notification.Name.showSettingsWindow"))
        XCTAssertTrue(statusBarController.contains("检查更新"))
        XCTAssertTrue(statusBarController.contains("NSApplication.shared.terminate(nil)"))
    }

    func test菜单栏右键菜单交由系统状态项定位并使用常规展示样式() throws {
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(statusBarController.contains("menu.presentationStyle = .regular"))
        XCTAssertTrue(statusBarController.contains("statusItem.menu = menu"))
        XCTAssertTrue(statusBarController.contains("button.performClick(nil)"))
        XCTAssertTrue(statusBarController.contains("statusItem.menu = nil"))
        XCTAssertFalse(statusBarController.contains("menu.popUp(positioning: nil"))
    }

    func test菜单栏和设置页提供问题提交入口() throws {
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/HelpUpdateView.swift")

        XCTAssertTrue(statusBarController.contains("提交问题"))
        XCTAssertTrue(statusBarController.contains("openIssueReport"))
        XCTAssertTrue(settings.contains("提交问题"))
        XCTAssertTrue(settings.contains("openIssueReport"))
    }

    func test菜单栏弹窗显示时会激活应用并获取焦点() throws {
        let source = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(source.contains("window.makeKeyAndOrderFront(nil)"))
    }

    func test更新完成提示不会阻塞首次启动检查() throws {
        let source = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")
        let start = try XCTUnwrap(source.range(of: "await self.environment.start()"))
        let notice = try XCTUnwrap(source.range(of: "self.environment.presentUpdateCompletionNoticeIfNeeded()"))

        XCTAssertLessThan(start.lowerBound, notice.lowerBound)
    }

    func test弹窗进度条复用共享用量风险呈现() throws {
        let usageRowView = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        XCTAssertTrue(usageRowView.contains("UsageMetricProgressBar(metric: metric)"))
        XCTAssertTrue(usageRowView.contains("UsageMetricPresentation.color(for: metric.percent)"))
    }

    func test菜单栏弹窗不再提供Key选中交互() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let row = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        XCTAssertTrue(popover.contains("usageListHeader"))
        XCTAssertTrue(popover.contains("账户用量"))
        XCTAssertFalse(popover.contains("当前账户"))
        XCTAssertFalse(popover.contains("isSelectedRoutin"))
        XCTAssertFalse(row.contains("store.selectedKeyID"))
        XCTAssertFalse(row.contains("store.selectKey"))
        XCTAssertFalse(row.contains("当前账户"))
    }

    func test设置使用独立可缩放窗口场景而不是系统固定设置场景() throws {
        let source = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(source.contains("Window(\"设置\", id: \"settings\")"))
        XCTAssertFalse(source.contains("Settings {"))
        XCTAssertTrue(source.contains(".windowResizability(.contentMinSize)"))
    }

    func test引导页统一使用五小时产品文案且设置页不再硬编码维度() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/GeneralSettingsView.swift")
        let onboarding = try sourceText(at: "RoutinUsage/Views/OnboardingView.swift")

        XCTAssertFalse(settings.contains("五小时"))
        XCTAssertFalse(onboarding.contains("五小时"))
        XCTAssertTrue(onboarding.contains("5 小时"))
    }

    func test设置窗口使用窗口代理且编辑器保留查看状态() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/SettingsWindowView.swift")
        let keyEditor = try sourceText(at: "RoutinUsage/Views/KeyEditorView.swift")

        XCTAssertTrue(settings.contains("WindowFramePersistence"))
        XCTAssertFalse(settings.contains("@State private var revealedKeyIDs"))
        XCTAssertTrue(keyEditor.contains("@State private var isSecretVisible"))
        XCTAssertTrue(keyEditor.contains("TextField(\"plan-…\""))
        XCTAssertTrue(keyEditor.contains("CredentialVisibility.iconName(isVisible: isSecretVisible)"))
    }

    func test设置页查看状态不从UserDefaults读取() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/SettingsWindowView.swift")
        let credentials = try sourceText(at: "RoutinUsage/Views/Settings/CredentialManagementView.swift")

        XCTAssertFalse(settings.contains("UserDefaults"))
        XCTAssertFalse(credentials.contains("UserDefaults"))
    }

    func test首次引导使用MyToken品牌图并聚焦添加首个Key() throws {
        let onboarding = try sourceText(at: "RoutinUsage/Views/OnboardingView.swift")

        XCTAssertTrue(onboarding.contains("PopoverColorBrandLogo"))
        XCTAssertTrue(onboarding.contains("欢迎使用 MyToken"))
        XCTAssertFalse(onboarding.contains("chart.bar.xaxis"))
        XCTAssertTrue(onboarding.contains("添加第一个 Key"))
    }

    func test菜单栏视图真实接入每凭证指标解析() throws {
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(statusBarController.contains("usagePreferences(for: id)"))
        XCTAssertTrue(statusBarController.contains("MenuBarMetricResolver.resolve"))
        XCTAssertTrue(statusBarController.contains("metric: resolution.metric"))
        XCTAssertFalse(statusBarController.contains("settings.displayDimension"))
    }

    func test弹窗详情保留两个周期并显示完整重置时间() throws {
        let row = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")
        let metricGrid = try sourceText(at: "RoutinUsage/Views/NormalizedUsageMetricGrid.swift")

        XCTAssertTrue(row.contains("title: \"5 小时\""))
        XCTAssertTrue(row.contains("title: \"周\""))
        XCTAssertTrue(metricGrid.contains("UsageFormatter.fullDateTime(windowEnd)"))
    }

    func test统一玻璃辅助层使用系统玻璃并保留旧系统材质回退() throws {
        guard let surface = try optionalSourceText(at: "RoutinUsage/Views/LiquidGlassSurface.swift") else {
            XCTFail("缺少统一玻璃辅助层")
            return
        }
        let projectSpec = try sourceText(at: "project.yml")

        XCTAssertTrue(surface.contains("if #available(macOS 26.0, *)"))
        XCTAssertTrue(surface.contains(".glassEffect(.regular.tint(.white.opacity("))
        XCTAssertTrue(surface.contains(".buttonStyle(.glass)"))
        XCTAssertTrue(surface.contains(".buttonStyle(.glassProminent)"))
        XCTAssertTrue(surface.contains(".regularMaterial"))
        XCTAssertTrue(surface.contains("shape.stroke(.white.opacity("))
        XCTAssertTrue(surface.contains(".shadow("))
        XCTAssertTrue(surface.contains("func liquidGlassSurface(cornerRadius: CGFloat = 16)"))
        XCTAssertTrue(surface.contains("func liquidGlassWindowBackground()"))
        XCTAssertTrue(projectSpec.contains("macOS: \"14.0\""))
    }

    func test设置页和用量弹窗使用统一玻璃窗口背景() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/SettingsWindowView.swift")
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")

        XCTAssertTrue(settings.contains(".liquidGlassWindowBackground()"))
        XCTAssertTrue(popover.contains(".liquidGlassWindowBackground()"))
    }

    func test设置页使用原生侧栏并避免嵌套玻璃容器() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/SettingsWindowView.swift")
        let credentials = try sourceText(at: "RoutinUsage/Views/Settings/CredentialManagementView.swift")

        XCTAssertTrue(settings.contains("NavigationSplitView"))
        XCTAssertTrue(settings.contains("SettingsSection"))
        XCTAssertTrue(settings.contains(".liquidGlassWindowBackground()"))
        XCTAssertTrue(settings.contains("List(SettingsSection.allCases"))
        XCTAssertFalse(settings.contains(".liquidGlassSurface(cornerRadius:"))
        XCTAssertTrue(credentials.contains("UsageRowView("))
        XCTAssertTrue(credentials.contains("LazyVGrid"))
    }

    func test弹窗简化为单层窗口玻璃并保留固定底栏() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let row = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")
        let onboarding = try sourceText(at: "RoutinUsage/Views/OnboardingView.swift")

        XCTAssertTrue(popover.contains("ScrollView(.vertical, showsIndicators: false)"))
        XCTAssertTrue(popover.contains("ThinVerticalScrollIndicator"))
        XCTAssertTrue(popover.contains("账户用量"))
        XCTAssertTrue(popover.contains("WrappingFilterChips"))
        XCTAssertTrue(popover.contains("visibleProviderIDs"))
        XCTAssertTrue(popover.contains("updateReleaseOverlay"))
        XCTAssertTrue(popover.contains("UpdateReleaseDetailView"))
        XCTAssertTrue(popover.contains("var bottomBar: some View"))
        XCTAssertFalse(popover.contains(".liquidGlassButton()"))
        XCTAssertTrue(popover.contains(".liquidGlassWindowBackground()"))
        XCTAssertFalse(popover.contains(".liquidGlassSurface(cornerRadius:"))
        XCTAssertFalse(popover.contains(".liquidGlassControlSurface()"))
        XCTAssertFalse(popover.contains(".liquidGlassProgressSurface()"))
        XCTAssertFalse(row.contains(".liquidGlassSurface(cornerRadius:"))
        XCTAssertFalse(row.contains(".liquidGlassProgressSurface()"))
        XCTAssertTrue(onboarding.contains(".liquidGlassSurface(cornerRadius: 24)"))
        XCTAssertTrue(onboarding.contains(".liquidGlassButton(prominent: true)"))
        XCTAssertTrue(onboarding.contains(".liquidGlassWindowBackground()"))
    }

    func test菜单栏真实图标保留辅助功能描述() throws {
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(statusBarController.contains("MenuBarMultiUsageIcon.image("))
        XCTAssertTrue(statusBarController.contains("appearance: button.effectiveAppearance"))
        XCTAssertTrue(statusBarController.contains("button.setAccessibilityLabel"))
    }

    func test弹窗倒计时每分钟刷新并将分组倍率合并为一行() throws {
        let usageRowView = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        XCTAssertTrue(usageRowView.contains("TimelineView(.periodic(from: .now, by: 60))"))
        XCTAssertTrue(usageRowView.contains("now: timeline.date"))
        XCTAssertTrue(usageRowView.contains("UsageFormatter.groupMultiplierText"))
        XCTAssertFalse(usageRowView.contains("ForEach(Array(groupMultipliers.enumerated())"))
    }

    func test弹窗将分组倍率置于百分比下方并右对齐() throws {
        let usageRowView = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        let headerStart = try XCTUnwrap(
            usageRowView.range(of: "func headerView(now: Date) -> some View")
        )
        let progressStart = try XCTUnwrap(usageRowView.range(of: "UsageMetricProgressBar"))
        let header = usageRowView[headerStart.lowerBound..<progressStart.lowerBound]

        XCTAssertTrue(header.contains("VStack(alignment: .trailing"))
        XCTAssertTrue(header.contains("groupMultiplierText(currentGroupMultiplier)"))
        XCTAssertTrue(header.contains("hasGroupMultipliers"))
        XCTAssertTrue(header.contains("Spacer(minLength: 8)"))
        XCTAssertFalse(usageRowView.contains("HStack {\n                    Spacer()\n                    Text(UsageFormatter.groupMultiplierText(groupMultipliers))"))
    }

    func test本地Key相关文案不再声称使用系统钥匙串() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/CredentialManagementView.swift")
        let onboarding = try sourceText(at: "RoutinUsage/Views/OnboardingView.swift")

        XCTAssertFalse(settings.contains("将同时删除系统钥匙串中的 Key"))
        XCTAssertFalse(onboarding.contains("Key 仅保存在这台 Mac 的系统钥匙串中"))
    }

    func test工程规格锁定为Xcode15兼容格式() throws {
        let projectSpec = try sourceText(at: "project.yml")

        XCTAssertTrue(projectSpec.contains("projectFormat: xcode15_3"))
    }

    func test工程锁定Xcode15兼容的Swift版本() throws {
        let projectSpec = try sourceText(at: "project.yml")

        XCTAssertTrue(projectSpec.contains("SWIFT_VERSION: \"5.0\""))
    }

    func test发布工作流使用MyToken作为版本展示名称() throws {
        let releaseWorkflow = try sourceText(at: ".github/workflows/release-macos.yml")

        XCTAssertTrue(releaseWorkflow.contains("name: MyToken macOS v${{ inputs.version }}"))
        XCTAssertTrue(releaseWorkflow.contains("RELEASE_VERSION: ${{ inputs.version }}"))
        XCTAssertTrue(releaseWorkflow.contains("cp \"build/dist/MyToken.dmg\" \"build/dist/${dmg_name}\""))
        XCTAssertTrue(releaseWorkflow.contains("uname -m"))
        XCTAssertTrue(releaseWorkflow.contains("tag_name: macos-v${{ inputs.version }}"))
        XCTAssertFalse(releaseWorkflow.contains("MyRoutin.dmg"))
        XCTAssertFalse(releaseWorkflow.contains("Routin Usage"))
    }

    func test发布工作流要求手动Markdown更新日志() throws {
        let workflow = try sourceText(at: ".github/workflows/release-macos.yml")
        let releaseNotesInput = """
              release_notes:
                description: 'macOS 发布说明（Markdown）'
                required: true
                type: string
        """

        XCTAssertTrue(workflow.contains(releaseNotesInput))
        XCTAssertTrue(workflow.contains("release_notes:"))
        XCTAssertTrue(workflow.contains("body: ${{ inputs.release_notes }}"))
        XCTAssertTrue(workflow.contains("generate_release_notes: false"))
    }

    func test发布工作流显式选择并校验Xcode26() throws {
        let workflow = try sourceText(at: ".github/workflows/release-macos.yml")

        XCTAssertTrue(
            workflow.contains("DEVELOPER_DIR: /Applications/Xcode_26.3.app/Contents/Developer")
        )
        XCTAssertTrue(workflow.contains("scripts/verify-xcode-26.sh"))
    }

    func test持续集成显式选择并校验Xcode26() throws {
        let workflow = try sourceText(at: ".github/workflows/ci.yml")

        XCTAssertTrue(
            workflow.contains("DEVELOPER_DIR: /Applications/Xcode_26.3.app/Contents/Developer")
        )
        XCTAssertTrue(workflow.contains("scripts/verify-xcode-26.sh"))
    }

    func test单元测试运行时不初始化菜单栏控制器() throws {
        let app = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")

        XCTAssertTrue(app.contains("XCTestConfigurationFilePath"))
        XCTAssertTrue(app.contains("guard !Self.isRunningUnitTests"))
        XCTAssertTrue(app.contains("@State private var statusBarController: StatusBarController?"))
    }

    func test弹窗详情显示剩余时长与配对分组倍率且不显示允许模型() throws {
        let usageRowView = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        XCTAssertTrue(usageRowView.contains("title: \"5 小时\""))
        XCTAssertTrue(usageRowView.contains("title: \"周\""))
        XCTAssertTrue(usageRowView.contains("UsageFormatter.remainingDurationText"))
        XCTAssertTrue(usageRowView.contains("groupMultipliers"))
        XCTAssertFalse(usageRowView.contains("allowedModels"))
        XCTAssertFalse(usageRowView.contains("允许模型"))
    }

    func test菜单栏弹窗失焦关闭并保持状态栏层级() throws {
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(statusBarController.contains("NSWindow.didResignKeyNotification"))
        XCTAssertTrue(statusBarController.contains("popover.performClose(nil)"))
        XCTAssertTrue(statusBarController.contains("window.level = .statusBar"))
    }

    func test弹窗详情显示全部按Key配对的分组倍率() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")

        XCTAssertTrue(settings.contains("UsageFormatter.groupMultiplierText(snapshot.groupMultipliers)"))
    }

    func test凭证行不切换菜单栏当前Key并提供启用开关() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/CredentialManagementView.swift")

        XCTAssertTrue(settings.contains("Toggle"))
        XCTAssertTrue(settings.contains("model.setEnabled"))
        XCTAssertTrue(settings.contains("isEnabled"))
        XCTAssertFalse(settings.contains("store.selectKey"))
        XCTAssertFalse(settings.contains("store.selectedKeyID"))
    }

    func test菜单栏弹窗只使用启用Key() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")

        XCTAssertTrue(popover.contains("store.visibleKeyIDs"))
        XCTAssertTrue(popover.contains("displayOrder.visible(enabledIDs:"))
    }

    func test菜单栏管理页提供常驻拖拽和无障碍动作() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/MenuBarManagementView.swift")

        XCTAssertFalse(settings.contains("isReorderingMenuBarIndicators"))
        XCTAssertFalse(settings.contains("private struct CredentialSortInteraction"))
        XCTAssertTrue(settings.contains("ReorderableCredentialCardList"))
        XCTAssertTrue(settings.contains("movingDisplay"))
        XCTAssertTrue(settings.contains("accessibilityAction"))
    }

    func test设置页显示当前版本与完整更新日志() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/HelpUpdateView.swift")
        let updateNotes = try sourceText(at: "RoutinUsage/Views/UpdateNotesView.swift")

        XCTAssertTrue(settings.contains("当前版本"))
        XCTAssertTrue(settings.contains("UpdateNotesView(notes: update.notes)"))
        XCTAssertFalse(updateNotes.contains(".lineLimit("))
    }

    func test更新日志视图使用Markdown并为无日志版本提供提示() throws {
        let updateNotes = try sourceText(at: "RoutinUsage/Views/UpdateNotesView.swift")

        XCTAssertTrue(updateNotes.contains("AttributedString(markdown:"))
        XCTAssertTrue(updateNotes.contains("此版本未提供更新日志"))
    }

    func test更新流程展示下载进度和完成提示并自动重启() throws {
        let environment = try sourceText(at: "RoutinUsage/App/AppEnvironment.swift")
        let service = try sourceText(at: "RoutinUsage/Updates/GitHubUpdateService.swift")
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/HelpUpdateView.swift")

        XCTAssertTrue(environment.contains("case downloading(progress: Double?)"))
        XCTAssertTrue(environment.contains("case completed(String)"))
        XCTAssertTrue(service.contains("createsNewApplicationInstance"))
        XCTAssertTrue(service.contains("UpdateCompletionNotice"))
        XCTAssertTrue(service.contains("if error == nil"))
        XCTAssertTrue(service.contains("新版本已安装到“应用程序”文件夹"))
        XCTAssertTrue(popover.contains("ProgressView(value: progress"))
        XCTAssertTrue(popover.contains("更新完成"))
        XCTAssertTrue(settings.contains("ProgressView(value: progress"))
        XCTAssertTrue(settings.contains("更新完成"))
    }

    func test弹窗设置入口复用右键菜单设置逻辑() throws {
        let usagePopoverView = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(usagePopoverView.contains("openSettings()"))
        XCTAssertFalse(usagePopoverView.contains("NSApp.setActivationPolicy(.regular)"))
        XCTAssertTrue(statusBarController.contains("openSettings: { [weak self] in"))
        XCTAssertTrue(statusBarController.contains("self?.openSettingsWindow()"))
        XCTAssertTrue(usagePopoverView.contains("设置"))
        XCTAssertFalse(usagePopoverView.contains("SettingsLink"))
    }

    func test保留受控签到登录流程但设置和弹窗不展示签到状态() throws {
        let app = try sourceText(at: "RoutinUsage/App/RoutinUsageApp.swift")
        let environment = try sourceText(at: "RoutinUsage/App/AppEnvironment.swift")
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/HelpUpdateView.swift")

        XCTAssertTrue(app.contains("Window(\"Routin 签到\", id: \"routin-check-in\")"))
        XCTAssertTrue(app.contains("RoutinCheckInWindow"))
        XCTAssertTrue(environment.contains("let routinCheckIn: RoutinCheckInService"))
        XCTAssertTrue(environment.contains("func startRoutinCheckIn() async"))
        XCTAssertTrue(environment.contains("func beginRoutinLogin() async"))
        XCTAssertTrue(environment.contains("func signOutRoutin() async"))
        XCTAssertTrue(statusBarController.contains("environment.routinCheckIn.state"))
        XCTAssertFalse(popover.contains("startRoutinCheckIn"))
        XCTAssertFalse(popover.contains("Routin 签到："))
        XCTAssertFalse(settings.contains("Routin 签到"))
    }

    func testCodex分组检测可打开Routin登录窗口() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let environment = try sourceText(at: "RoutinUsage/App/AppEnvironment.swift")
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(popover.contains("openWindow(id: \"routin-check-in\")"))
        XCTAssertFalse(environment.contains("showRoutinCheckInWindow"))
        XCTAssertFalse(statusBarController.contains("showRoutinCheckInWindow"))
    }

    func test新设置页面不保存Routin账号密码或Cookie() throws {
        let settings = try sourceText(at: "RoutinUsage/Views/Settings/SettingsWindowView.swift")
        let credentials = try sourceText(at: "RoutinUsage/Views/Settings/CredentialManagementView.swift")
        let help = try sourceText(at: "RoutinUsage/Views/Settings/HelpUpdateView.swift")

        XCTAssertFalse(settings.contains("SecureField(\"Routin"))
        XCTAssertFalse(settings.contains("TextField(\"账号"))
        XCTAssertFalse(settings.contains("TextField(\"密码"))
        XCTAssertFalse(settings.contains("Cookie"))
        XCTAssertFalse(credentials.contains("SecureField(\"Routin"))
        XCTAssertFalse(credentials.contains("TextField(\"账号"))
        XCTAssertFalse(credentials.contains("TextField(\"密码"))
        XCTAssertFalse(credentials.contains("Cookie"))
        XCTAssertFalse(help.contains("SecureField(\"Routin"))
        XCTAssertFalse(help.contains("TextField(\"账号"))
        XCTAssertFalse(help.contains("TextField(\"密码"))
        XCTAssertFalse(help.contains("Cookie"))
    }

    func test菜单栏弹窗不提供签到状态但保留分组检测状态() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")

        XCTAssertFalse(popover.contains("openWindow(id: \"routin-check-in\")\n                    Task { await startRoutinCheckIn() }"))
        XCTAssertFalse(popover.contains("if hasRoutinAccount"))
        XCTAssertFalse(popover.contains("checkInHelpText"))
        XCTAssertFalse(popover.contains("checkInState.statusText"))
        XCTAssertFalse(popover.contains("Routin 签到："))
        XCTAssertTrue(popover.contains("codexGroupDetectionStatus"))
    }

    func testCodex当前分组检测已接入真实展示层和Key生命周期() throws {
        let popover = try sourceText(at: "RoutinUsage/Views/UsagePopoverView.swift")
        let row = try sourceText(at: "RoutinUsage/Views/UsageRowView.swift")
        let environment = try sourceText(at: "RoutinUsage/App/AppEnvironment.swift")
        let statusBarController = try sourceText(at: "RoutinUsage/App/StatusBarController.swift")

        XCTAssertTrue(popover.contains("获取 Codex 当前分组？"))
        XCTAssertTrue(popover.contains("真实 Codex 请求"))
        XCTAssertTrue(popover.contains("openWindow(id: \"routin-check-in\")"))
        XCTAssertTrue(popover.contains("codexGroupDetectionStatus"))
        XCTAssertTrue(popover.contains("ProgressView()"))
        XCTAssertTrue(row.contains("location.magnifyingglass"))
        XCTAssertTrue(row.contains("Color.green"))
        XCTAssertTrue(row.contains("Codex 分组检测"))
        XCTAssertFalse(row.contains(".isButton"))
        XCTAssertTrue(environment.contains("previousSecret != input.secret"))
        XCTAssertTrue(environment.contains("func deleteKey(_ keyID: UUID)"))
        XCTAssertTrue(statusBarController.contains("codexGroupDetection: environment.codexGroupDetection"))
    }

    func testCodex账号关联只依赖邮箱摘要而不要求昵称() throws {
        let webSession = try sourceText(at: "RoutinUsage/GroupDetection/RoutinGroupDetectionWebSession.swift")

        XCTAssertTrue(webSession.contains("displayName: String?"))
        XCTAssertTrue(webSession.contains("displayName: displayName?.isEmpty == false ? displayName! : \"Routin 账号\""))
        XCTAssertTrue(webSession.contains("window.localStorage.getItem('meteor_user')"))
        XCTAssertFalse(webSession.contains("window.localStorage.getItem('meteor_access_token')"))
        XCTAssertFalse(webSession.contains("window.localStorage.getItem('meteor_refresh_token')"))
        XCTAssertTrue(webSession.contains("for _ in 0..<20"))
    }

    private func sourceText(at relativePath: String) throws -> String {
        guard let source = try optionalSourceText(at: relativePath) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return source
    }

    private func optionalSourceText(at relativePath: String) throws -> String? {
        let resource: (name: String, extension: String?)
        switch relativePath {
        case "project.yml":
            resource = ("project", "yml")
        case "scripts/test.sh":
            resource = ("test", "sh")
        case ".github/workflows/release-macos.yml":
            resource = ("release-macos", "yml")
        case ".github/workflows/ci.yml":
            resource = ("ci", "yml")
        case "RoutinUsage/App/RoutinUsageApp.swift":
            resource = ("RoutinUsageApp.swift", "txt")
        case "RoutinUsage/App/StatusBarController.swift":
            resource = ("StatusBarController.swift", "txt")
        case "RoutinUsage/App/AppEnvironment.swift":
            resource = ("AppEnvironment.swift", "txt")
        case "RoutinUsage/Updates/GitHubUpdateService.swift":
            resource = ("GitHubUpdateService.swift", "txt")
        case "RoutinUsage/Views/Settings/SettingsWindowView.swift":
            resource = ("SettingsWindowView.swift", "txt")
        case "RoutinUsage/Views/Settings/CredentialManagementView.swift":
            resource = ("CredentialManagementView.swift", "txt")
        case "RoutinUsage/Views/Settings/MenuBarManagementView.swift":
            resource = ("MenuBarManagementView.swift", "txt")
        case "RoutinUsage/Views/Settings/GeneralSettingsView.swift":
            resource = ("GeneralSettingsView.swift", "txt")
        case "RoutinUsage/Views/Settings/HelpUpdateView.swift":
            resource = ("HelpUpdateView.swift", "txt")
        case "RoutinUsage/Views/UpdateNotesView.swift":
            resource = ("UpdateNotesView.swift", "txt")
        case "RoutinUsage/Views/KeyEditorView.swift":
            resource = ("KeyEditorView.swift", "txt")
        case "RoutinUsage/Views/OnboardingView.swift":
            resource = ("OnboardingView.swift", "txt")
        case "RoutinUsage/Views/UsageRowView.swift":
            resource = ("UsageRowView.swift", "txt")
        case "RoutinUsage/Views/NormalizedUsageMetricGrid.swift":
            resource = ("NormalizedUsageMetricGrid.swift", "txt")
        case "RoutinUsage/Models/MenuBarStyle.swift":
            resource = ("MenuBarStyle.swift", "txt")
        case "RoutinUsage/Views/UsagePopoverView.swift":
            resource = ("UsagePopoverView.swift", "txt")
        case "RoutinUsage/Views/LiquidGlassSurface.swift":
            resource = ("LiquidGlassSurface.swift", "txt")
        case "RoutinUsage/GroupDetection/RoutinGroupDetectionWebSession.swift":
            resource = ("RoutinGroupDetectionWebSession.swift", "txt")
        default:
            throw CocoaError(.fileNoSuchFile)
        }
        guard let sourceURL = Bundle(for: ProjectBootstrapTests.self)
            .url(forResource: resource.name, withExtension: resource.extension) else { return nil }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
