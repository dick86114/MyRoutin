import AppKit
import XCTest
@testable import RoutinUsage

final class AppSettingsTests: XCTestCase {
    @MainActor
    func test设置窗口尺寸默认值并可持久化重载() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        XCTAssertEqual(
            WindowFramePersistence.loadSize(defaults: context.defaults),
            WindowFramePersistence.defaultSize
        )

        WindowFramePersistence.saveSize(
            CGSize(width: 720, height: 640),
            defaults: context.defaults
        )

        XCTAssertEqual(
            WindowFramePersistence.loadSize(defaults: context.defaults),
            CGSize(width: 760, height: 640)
        )
    }

    func test全新设置使用产品默认值() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let settings = AppSettings(defaults: context.defaults)

        XCTAssertEqual(settings.refreshMinutes, 5)
        XCTAssertEqual(settings.displayDimension, .fiveHour)
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertEqual(settings.thresholds, AlertThresholds(low: 80, high: 95))
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.menuBarStyle, .aliasLogoProgress)
    }

    func test菜单栏样式可持久化并重新载入() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)

        settings.menuBarStyle = .aliasVerticalBar
        XCTAssertEqual(AppSettings(defaults: context.defaults).menuBarStyle, .aliasVerticalBar)

        settings.menuBarStyle = .aliasLogoProgress
        XCTAssertEqual(AppSettings(defaults: context.defaults).menuBarStyle, .aliasLogoProgress)

        settings.menuBarStyle = .logoProgress
        XCTAssertEqual(AppSettings(defaults: context.defaults).menuBarStyle, .logoProgress)

        settings.menuBarStyle = .aliasPercent
        XCTAssertEqual(AppSettings(defaults: context.defaults).menuBarStyle, .aliasPercent)
    }

    func test缺失或未知菜单栏样式回退为别名加Logo进度() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        XCTAssertEqual(AppSettings(defaults: context.defaults).menuBarStyle, .aliasLogoProgress)

        context.defaults.set("broken", forKey: "menuBarStyle")
        XCTAssertEqual(AppSettings(defaults: context.defaults).menuBarStyle, .aliasLogoProgress)
    }

    @MainActor
    func test设置窗口明确允许拖动边角改变大小() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let coordinator = WindowFramePersistence(defaults: context.defaults).makeCoordinator()

        coordinator.attach(to: window)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize, WindowFramePersistence.minimumSize)
    }

    func test刷新间隔只接受固定选项并可重新载入() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)

        for minutes in [1, 5, 15, 30] {
            settings.refreshMinutes = minutes
            XCTAssertEqual(settings.refreshMinutes, minutes)
            XCTAssertEqual(
                AppSettings(defaults: context.defaults).refreshMinutes,
                minutes
            )
        }

        settings.refreshMinutes = 7

        XCTAssertEqual(settings.refreshMinutes, 30)
        XCTAssertEqual(AppSettings(defaults: context.defaults).refreshMinutes, 30)
    }

    func test损坏的持久化值恢复为安全默认值() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set(7, forKey: "refreshMinutes")
        context.defaults.set("token", forKey: "displayDimension")
        context.defaults.set(0, forKey: "notificationLowThreshold")
        context.defaults.set(101, forKey: "notificationHighThreshold")

        let settings = AppSettings(defaults: context.defaults)

        XCTAssertEqual(settings.refreshMinutes, 5)
        XCTAssertEqual(settings.displayDimension, .fiveHour)
        XCTAssertEqual(settings.thresholds, AlertThresholds(low: 80, high: 95))
    }

    func test用户设置以基础值持久化并可重新载入() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)

        settings.displayDimension = .weekly
        settings.notificationsEnabled = false
        settings.thresholds = AlertThresholds(low: 70, high: 90)
        settings.launchAtLogin = true

        let reloaded = AppSettings(defaults: context.defaults)
        XCTAssertEqual(reloaded.displayDimension, .weekly)
        XCTAssertFalse(reloaded.notificationsEnabled)
        XCTAssertEqual(reloaded.thresholds, AlertThresholds(low: 70, high: 90))
        XCTAssertTrue(reloaded.launchAtLogin)
    }

    func test菜单栏指标排序只重排已选择的凭证且可持久化() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)
        let ids = [UUID(), UUID(), UUID()]
        settings.selectedCredentialIDs = ids

        settings.moveSelectedCredential(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(settings.selectedCredentialIDs, [ids[2], ids[0], ids[1]])
        XCTAssertEqual(
            AppSettings(defaults: context.defaults).selectedCredentialIDs,
            [ids[2], ids[0], ids[1]]
        )
    }

    func test可添加指标排序可持久化() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)
        let ids = [UUID(), UUID(), UUID()]
        settings.availableCredentialIDs = ids

        settings.moveAvailableCredential(
            fromOffsets: IndexSet(integer: 2),
            toOffset: 0
        )

        XCTAssertEqual(settings.availableCredentialIDs, [ids[2], ids[0], ids[1]])
        XCTAssertEqual(
            AppSettings(defaults: context.defaults).availableCredentialIDs,
            [ids[2], ids[0], ids[1]]
        )
    }

    func test菜单栏弹窗先按已选顺序再按可添加顺序显示() {
        let selected = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        ]
        let available = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        ]
        let leftover = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
        let visible = [available[2], leftover, selected[1], selected[0], available[0]]

        XCTAssertEqual(
            LegacyCredentialDisplayOrder.popoverIDs(
                selected: selected,
                available: available,
                visible: visible
            ),
            [selected[0], selected[1], available[0], available[2], leftover]
        )
    }

    func test独立展示顺序可持久化并迁移旧配置() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let selected = [UUID(), UUID()]
        let available = [UUID()]
        let all = selected + available + [UUID()]
        context.defaults.set(selected.map(\.uuidString), forKey: "selectedCredentialIDs")
        context.defaults.set(available.map(\.uuidString), forKey: "availableCredentialIDs")

        let settings = AppSettings(defaults: context.defaults)
        settings.importLegacyDisplayOrder(allIDs: all)

        XCTAssertEqual(settings.displayOrder.menuBarCredentialIDs, selected)
        XCTAssertEqual(settings.displayOrder.popoverCredentialIDs, all)
        XCTAssertEqual(
            AppSettings(defaults: context.defaults).displayOrder,
            settings.displayOrder
        )
    }

    func test卡片拖拽向下放置到目标卡片之后() throws {
        let suiteName = "card-drag-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let ids = [UUID(), UUID(), UUID(), UUID()]
        settings.selectedCredentialIDs = ids

        settings.moveSelectedCredential(fromOffsets: IndexSet(integer: 0), toOffset: 4)

        XCTAssertEqual(settings.selectedCredentialIDs, [ids[1], ids[2], ids[3], ids[0]])
    }

    func test菜单栏弹窗先展示已选择凭证的排序再展示其余凭证() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            LegacyCredentialDisplayOrder.popoverIDs(
                selected: [second, first],
                available: [],
                visible: [first, second, third]
            ),
            [second, first, third]
        )
    }
}

final class LoginItemManagerTests: XCTestCase {
    func test重复设置当前登录启动状态不会调用系统服务() throws {
        let enabledService = LoginItemServiceSpy(status: .enabled)
        let disabledService = LoginItemServiceSpy(status: .notRegistered)

        try LoginItemManager(service: enabledService).setEnabled(true)
        try LoginItemManager(service: disabledService).setEnabled(false)

        XCTAssertEqual(enabledService.registerCount, 0)
        XCTAssertEqual(enabledService.unregisterCount, 0)
        XCTAssertEqual(disabledService.registerCount, 0)
        XCTAssertEqual(disabledService.unregisterCount, 0)
    }

    func test登录启动状态变化时调用对应系统操作() throws {
        let disabledService = LoginItemServiceSpy(status: .notRegistered)
        let enabledService = LoginItemServiceSpy(status: .enabled)

        try LoginItemManager(service: disabledService).setEnabled(true)
        try LoginItemManager(service: enabledService).setEnabled(false)

        XCTAssertEqual(disabledService.registerCount, 1)
        XCTAssertEqual(disabledService.unregisterCount, 0)
        XCTAssertEqual(enabledService.registerCount, 0)
        XCTAssertEqual(enabledService.unregisterCount, 1)
    }

    @MainActor
    func test登录启动设置同步系统外部变更与待批准状态() throws {
        let context = try AppSettingsTests().makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)
        settings.launchAtLogin = true
        let manager = LoginItemManagerFake(isEnabled: false)

        LoginItemSettingSynchronizer.synchronize(settings: settings, manager: manager)
        XCTAssertFalse(settings.launchAtLogin)

        manager.isEnabled = true
        LoginItemSettingSynchronizer.synchronize(settings: settings, manager: manager)
        XCTAssertTrue(settings.launchAtLogin)
    }

    @MainActor
    func test注册后系统仍待批准时设置保持关闭() throws {
        let context = try AppSettingsTests().makeContext()
        defer { context.cleanUp() }
        let settings = AppSettings(defaults: context.defaults)
        let manager = LoginItemManagerFake(isEnabled: false, remainsDisabledAfterSet: true)

        try LoginItemSettingSynchronizer.setEnabled(
            true,
            settings: settings,
            manager: manager
        )

        XCTAssertEqual(manager.requestedValues, [true])
        XCTAssertFalse(settings.launchAtLogin)
    }
}

private extension AppSettingsTests {
    struct Context {
        let suiteName: String
        let defaults: UserDefaults

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    func makeContext() throws -> Context {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return Context(suiteName: suiteName, defaults: defaults)
    }
}

private final class LoginItemServiceSpy: LoginItemServicing, @unchecked Sendable {
    private let lock = NSLock()
    let status: LoginItemStatus
    private var storedRegisterCount = 0
    private var storedUnregisterCount = 0

    var registerCount: Int {
        lock.withLock { storedRegisterCount }
    }

    var unregisterCount: Int {
        lock.withLock { storedUnregisterCount }
    }

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        lock.withLock {
            storedRegisterCount += 1
        }
    }

    func unregister() throws {
        lock.withLock {
            storedUnregisterCount += 1
        }
    }
}

private final class LoginItemManagerFake: LoginItemManaging, @unchecked Sendable {
    var isEnabled: Bool
    let remainsDisabledAfterSet: Bool
    private(set) var requestedValues: [Bool] = []

    init(isEnabled: Bool, remainsDisabledAfterSet: Bool = false) {
        self.isEnabled = isEnabled
        self.remainsDisabledAfterSet = remainsDisabledAfterSet
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if !remainsDisabledAfterSet {
            isEnabled = enabled
        }
    }
}
