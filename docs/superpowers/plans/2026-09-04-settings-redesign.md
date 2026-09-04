# 设置界面重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用独立且可迁移的菜单栏 / 弹窗顺序模型，替换当前耦合的设置实现，并重建为现代 macOS 液态玻璃设置界面。

**Architecture:** 先建立纯函数排序模型和旧配置迁移，再切换真实菜单栏与真实弹窗的数据源，最后按五个导航分类拆分设置视图。所有排序变更都先经过 `CredentialDisplayOrder`，SwiftUI 拖拽层只负责采集 UUID 和目标位置。

**Tech Stack:** Swift 5、SwiftUI、AppKit、Observation、UserDefaults、XCTest、XcodeGen。

**Spec:** `docs/superpowers/specs/2026-09-04-settings-redesign-design.md`

## Global Constraints

- macOS 部署目标保持 `14.0`；macOS 26 才可使用 `glassEffect`，旧系统必须走 `.regularMaterial` 降级。
- 所有新源码放在 `RoutinUsage`，新测试放在 `RoutinUsageTests`；新增文件后运行 `xcodegen generate`。
- 全部注释、UI 文案、测试名和提交说明使用中文。
- 菜单栏展示上限固定为 `5`。
- 真实菜单栏读取 `menuBarCredentialIDs`，真实弹窗读取 `popoverCredentialIDs`；不得继续用旧字段推导弹窗顺序。
- 液态玻璃实现只允许使用 `RoutinUsage/Views/LiquidGlassSurface.swift` 中的现有扩展，不在页面里散落实现。
- 每个任务完成前运行指定测试；提交前不得留下编译错误。
- 工作区必须干净或只包含本任务变更后才能提交；不得还原无关文件。

---

### Task 1: 独立排序模型

**Files:**
- Create: `RoutinUsage/Models/CredentialDisplayOrder.swift`
- Modify: `RoutinUsage/Models/AppSettings.swift`
- Modify: `RoutinUsage/Views/UsagePopoverView.swift`
- Test: `RoutinUsageTests/CredentialDisplayOrderTests.swift`
- Test: `RoutinUsageTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `UUID`、现有 `AppSettings.selectedCredentialIDs`、`AppSettings.availableCredentialIDs`。
- Produces:
  - `struct CredentialDisplayOrder`
  - `enum CredentialDisplaySequence`
  - `struct CredentialDisplayVisibility`
  - `CredentialDisplayOrder.visible(enabledIDs:)`
  - `CredentialDisplayOrder.moving(_:id:toIndex:)`
  - `CredentialDisplayOrder.addingToMenuBar(_:toIndex:)`
  - `CredentialDisplayOrder.removingFromMenuBar(_:)`
  - `CredentialDisplayOrder.removingCredential(_:)`
  - `CredentialDisplayOrder.migrated(selected:available:allIDs:)`

旧代码中的 `enum CredentialDisplayOrder` 与新模型重名。本任务先把它改名为 `LegacyCredentialDisplayOrder`，并同步更新当前引用，保证编译连续。

- [ ] **Step 1: 写排序模型失败测试**

创建 `RoutinUsageTests/CredentialDisplayOrderTests.swift`：

```swift
import XCTest
@testable import RoutinUsage

final class CredentialDisplayOrderTests: XCTestCase {
    private let one = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let two = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let three = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let four = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    private var order: CredentialDisplayOrder {
        CredentialDisplayOrder(
            menuBarCredentialIDs: [two, one],
            popoverCredentialIDs: [two, three, one, four]
        )
    }

    func test可见序列过滤停用凭证并派生菜单栏待选区() {
        let visibility = order.visible(enabledIDs: [one, two, four])

        XCTAssertEqual(visibility.menuBarIDs, [two, one])
        XCTAssertEqual(visibility.popoverIDs, [two, one, four])
        XCTAssertEqual(visibility.menuBarCandidateIDs, [four])
    }

    func test菜单栏排序不影响弹窗排序() {
        let result = order.moving(.menuBar, id: one, toIndex: 0)

        XCTAssertEqual(result.menuBarCredentialIDs, [one, two])
        XCTAssertEqual(result.popoverCredentialIDs, order.popoverCredentialIDs)
    }

    func test弹窗排序不影响菜单栏排序() {
        let result = order.moving(.popover, id: four, toIndex: 0)

        XCTAssertEqual(result.menuBarCredentialIDs, order.menuBarCredentialIDs)
        XCTAssertEqual(result.popoverCredentialIDs, [four, two, three, one])
    }

    func test待选凭证加入菜单栏且上限为五() {
        let base = CredentialDisplayOrder(
            menuBarCredentialIDs: [one, two, three, four],
            popoverCredentialIDs: [one, two, three, four]
        )
        let candidate = UUID()
        let rejected = base.addingToMenuBar(candidate, toIndex: 0)
        XCTAssertEqual(rejected, base)

        let removable = base.removingFromMenuBar(four)
        let accepted = removable.addingToMenuBar(candidate, toIndex: 0)
        XCTAssertEqual(accepted.menuBarCredentialIDs, [candidate, one, two, three])
        XCTAssertEqual(accepted.popoverCredentialIDs, base.popoverCredentialIDs)
    }

    func test删除凭证同步清理两个独立序列() {
        let result = order.removingCredential(one)

        XCTAssertEqual(result.menuBarCredentialIDs, [two])
        XCTAssertEqual(result.popoverCredentialIDs, [two, three, four])
    }

    func test旧配置迁移保留菜单栏和弹窗稳定顺序() {
        let disabled = UUID()
        let result = CredentialDisplayOrder.migrated(
            selected: [two, one],
            available: [three],
            allIDs: [one, two, three, disabled]
        )

        XCTAssertEqual(result.menuBarCredentialIDs, [two, one])
        XCTAssertEqual(result.popoverCredentialIDs, [two, one, three, disabled])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/CredentialDisplayOrderTests
```

预期：编译失败，提示 `CredentialDisplayOrder` 类型或方法不存在。

- [ ] **Step 3: 实现排序模型**

创建 `RoutinUsage/Models/CredentialDisplayOrder.swift`：

```swift
import Foundation

enum CredentialDisplaySequence: Equatable, Sendable {
    case menuBar
    case popover
}

struct CredentialDisplayVisibility: Equatable, Sendable {
    let menuBarIDs: [UUID]
    let popoverIDs: [UUID]
    let menuBarCandidateIDs: [UUID]
}

struct CredentialDisplayOrder: Codable, Equatable, Sendable {
    static let maximumMenuBarCount = 5

    var menuBarCredentialIDs: [UUID]
    var popoverCredentialIDs: [UUID]

    init(
        menuBarCredentialIDs: [UUID] = [],
        popoverCredentialIDs: [UUID] = []
    ) {
        self.menuBarCredentialIDs = Self.uniqued(menuBarCredentialIDs)
        self.popoverCredentialIDs = Self.uniqued(popoverCredentialIDs)
    }

    static func migrated(
        selected: [UUID],
        available: [UUID],
        allIDs: [UUID]
    ) -> Self {
        let menuBar = selected.filter { allIDs.contains($0) }
        let popover = selected + available + allIDs
        return Self(
            menuBarCredentialIDs: menuBar,
            popoverCredentialIDs: popover
        )
    }

    func visible(enabledIDs: Set<UUID>) -> CredentialDisplayVisibility {
        let menuBar = menuBarCredentialIDs.filter { enabledIDs.contains($0) }
        let popover = popoverCredentialIDs.filter { enabledIDs.contains($0) }
        let candidates = popover.filter { !menuBar.contains($0) }
        return CredentialDisplayVisibility(
            menuBarIDs: menuBar,
            popoverIDs: popover,
            menuBarCandidateIDs: candidates
        )
    }

    func moving(
        _ sequence: CredentialDisplaySequence,
        id: UUID,
        toIndex target: Int
    ) -> Self {
        var result = self
        let keyPath: WritableKeyPath<CredentialDisplayOrder, [UUID]> = switch sequence {
        case .menuBar: \.menuBarCredentialIDs
        case .popover: \.popoverCredentialIDs
        }
        result[keyPath: keyPath] = Self.moved(
            result[keyPath: keyPath],
            id: id,
            toIndex: target
        )
        return result
    }

    func addingToMenuBar(_ id: UUID, toIndex target: Int) -> Self {
        guard menuBarCredentialIDs.contains(id) else {
            guard menuBarCredentialIDs.count < Self.maximumMenuBarCount else {
                return self
            }
            var result = self
            let index = max(0, min(target, result.menuBarCredentialIDs.count))
            result.menuBarCredentialIDs.insert(id, at: index)
            return result
        }
        return moving(.menuBar, id: id, toIndex: target)
    }

    func removingFromMenuBar(_ id: UUID) -> Self {
        var result = self
        result.menuBarCredentialIDs.removeAll { $0 == id }
        return result
    }

    func removingCredential(_ id: UUID) -> Self {
        var result = removingFromMenuBar(id)
        result.popoverCredentialIDs.removeAll { $0 == id }
        return result
    }

    private static func moved(
        _ ids: [UUID],
        id: UUID,
        toIndex target: Int
    ) -> [UUID] {
        guard let source = ids.firstIndex(of: id) else {
            return ids
        }

        var result = ids
        result.remove(at: source)
        let destination = target > source ? target - 1 : target
        let boundedIndex = max(0, min(destination, result.count))
        result.insert(id, at: boundedIndex)
        return result
    }

    private static func uniqued(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
```

在 `RoutinUsage/Models/AppSettings.swift` 中，把旧 `enum CredentialDisplayOrder` 整体重命名为 `enum LegacyCredentialDisplayOrder`。在 `RoutinUsage/Views/UsagePopoverView.swift` 中，把唯一调用点改为：

```swift
LegacyCredentialDisplayOrder.popoverIDs(
    selected: settings.selectedCredentialIDs,
    available: settings.availableCredentialIDs,
    visible: store.visibleKeyIDs
)
```

把 `RoutinUsageTests/AppSettingsTests.swift` 中旧 `CredentialDisplayOrder.popoverIDs` 的三处引用改为 `LegacyCredentialDisplayOrder.popoverIDs`。

- [ ] **Step 4: 运行排序测试和既有设置测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/CredentialDisplayOrderTests -only-testing:RoutinUsageTests/AppSettingsTests
```

预期：全部通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Models/CredentialDisplayOrder.swift RoutinUsage/Models/AppSettings.swift RoutinUsage/Views/UsagePopoverView.swift RoutinUsageTests/CredentialDisplayOrderTests.swift RoutinUsageTests/AppSettingsTests.swift
git commit -m "feat: 新增独立凭证展示顺序模型"
```

---

### Task 2: 设置持久化并切换真实展示面

**Files:**
- Modify: `RoutinUsage/Models/AppSettings.swift`
- Modify: `RoutinUsage/App/AppEnvironment.swift`
- Modify: `RoutinUsage/App/StatusBarController.swift`
- Modify: `RoutinUsage/Views/UsagePopoverView.swift`
- Test: `RoutinUsageTests/AppSettingsTests.swift`
- Test: `RoutinUsageTests/ProjectBootstrapTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `CredentialDisplayOrder`。
- Produces:
  - `AppSettings.displayOrder: CredentialDisplayOrder`
  - `AppSettings.importLegacyDisplayOrder(allIDs:)`
  - `AppSettings.appendCredential(_:)`
  - `AppSettings.removeCredential(_:)`

- [ ] **Step 1: 写持久化和真实数据源失败测试**

在 `AppSettingsTests.swift` 中新增：

```swift
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
```

在 `ProjectBootstrapTests.swift` 中新增：

```swift
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/AppSettingsTests -only-testing:RoutinUsageTests/ProjectBootstrapTests
```

预期：新增两个测试失败。

- [ ] **Step 3: 实现持久化**

在 `AppSettings` 中加入：

```swift
private static let displayOrderKey = "displayOrder.v1"

var displayOrder: CredentialDisplayOrder {
    didSet { persistDisplayOrder() }
}

var hasPersistedDisplayOrder: Bool {
    defaults.data(forKey: Self.displayOrderKey) != nil
}

func importLegacyDisplayOrder(allIDs: [UUID]) {
    guard !hasPersistedDisplayOrder else { return }
    displayOrder = CredentialDisplayOrder.migrated(
        selected: selectedCredentialIDs,
        available: availableCredentialIDs,
        allIDs: allIDs
    )
}

func appendCredential(_ id: UUID) {
    var order = displayOrder
    order.popoverCredentialIDs.append(id)
    displayOrder = order
}

func removeCredential(_ id: UUID) {
    displayOrder = displayOrder.removingCredential(id)
}

private func persistDisplayOrder() {
    if let data = try? JSONEncoder().encode(displayOrder) {
        defaults.set(data, forKey: Self.displayOrderKey)
    }
}
```

`init` 中解码旧值：

```swift
if let data = defaults.data(forKey: Self.displayOrderKey),
   let decoded = try? JSONDecoder().decode(CredentialDisplayOrder.self, from: data) {
    displayOrder = decoded
} else {
    displayOrder = CredentialDisplayOrder()
}
```

`AppEnvironment.init` 在 `self.store = store` 完成后调用，确保状态栏首次渲染前已完成迁移：

```swift
settings.importLegacyDisplayOrder(allIDs: store.orderedKeyIDs)
```

`StatusBarController.updateStatusButton()` 的菜单栏数据源改为：

```swift
let enabledIDs = Set(environment.store.visibleKeyIDs)
let visibility = environment.settings.displayOrder.visible(enabledIDs: enabledIDs)
let selectedIndicators = visibility.menuBarIDs.compactMap { id -> MenuBarIndicatorModel? in
    guard let state = environment.store.state(for: id),
          let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == state.configuration.providerID })
    else { return nil }
    return MenuBarIndicatorModel.make(
        state: state,
        descriptor: descriptor,
        dimension: environment.settings.displayDimension
    )
}
```

同时把 `observeEnvironment()` 中的 `_ = environment.settings.selectedCredentialIDs` 替换为 `_ = environment.settings.displayOrder`。

`UsagePopoverView` 的弹窗顺序改为：

```swift
var popoverKeyIDs: [UUID] {
    let enabledIDs = Set(store.visibleKeyIDs)
    return settings.displayOrder
        .visible(enabledIDs: enabledIDs)
        .popoverIDs
}
```

供应商筛选继续对 `popoverKeyIDs` 做交集，不改写 `displayOrder`。删除本地变量 `LegacyCredentialDisplayOrder` 相关调用。

- [ ] **Step 4: 全量编译并运行相关测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/AppSettingsTests -only-testing:RoutinUsageTests/ProjectBootstrapTests -only-testing:RoutinUsageTests/CredentialDisplayOrderTests
```

预期：通过；旧弹窗推导只在迁移代码中作为入参出现，不再作为展示数据源。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Models/AppSettings.swift RoutinUsage/App/AppEnvironment.swift RoutinUsage/App/StatusBarController.swift RoutinUsage/Views/UsagePopoverView.swift RoutinUsageTests/AppSettingsTests.swift RoutinUsageTests/ProjectBootstrapTests.swift
git commit -m "feat: 真实菜单栏和弹窗使用独立展示顺序"
```

---

### Task 3: 凭证生命周期同步排序

**Files:**
- Create: `RoutinUsage/App/CredentialOrderingController.swift`
- Modify: `RoutinUsage/App/AppEnvironment.swift`
- Test: `RoutinUsageTests/CredentialOrderingControllerTests.swift`

**Interfaces:**
- Consumes: `AppEnvironment`、`ValidatedCredentialInput`、`CredentialDisplayOrder`。
- Produces:
  - `CredentialOrderingController(settings:addCredential:setKeyEnabled:delete:)`
  - `struct CredentialAddOutcome`
  - `addValidatedCredential(_:)`
  - `setEnabled(_:enabled:)`
  - `delete(_:)`
  - `move(_:id:toIndex:)`

- [ ] **Step 1: 写生命周期失败测试**

创建 `RoutinUsageTests/CredentialOrderingControllerTests.swift`：

```swift
import XCTest
@testable import RoutinUsage

@MainActor
final class CredentialOrderingControllerTests: XCTestCase {
    func test删除凭证时同步清理独立顺序() throws {
        let suiteName = "credential-order-controller.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        var deletedIDs: [UUID] = []
        let id = UUID()
        settings.appendCredential(id)
        settings.displayOrder.menuBarCredentialIDs = [id]
        let controller = CredentialOrderingController(
            settings: settings,
            addCredential: { _ in
                CredentialAddOutcome(saveResult: .saved, addedCredentialID: nil)
            },
            setKeyEnabled: { _, _ in },
            delete: { id in
                deletedIDs.append(id)
            }
        )

        try controller.delete(id)

        XCTAssertFalse(settings.displayOrder.menuBarCredentialIDs.contains(id))
        XCTAssertFalse(settings.displayOrder.popoverCredentialIDs.contains(id))
        XCTAssertEqual(deletedIDs, [id])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/CredentialOrderingControllerTests
```

预期：编译失败，`CredentialOrderingController` 不存在。

- [ ] **Step 3: 实现生命周期控制器**

创建 `RoutinUsage/App/CredentialOrderingController.swift`：

```swift
import Foundation
import Observation

struct CredentialAddOutcome: Sendable, Equatable {
    let saveResult: KeyEditorSaveResult
    let addedCredentialID: UUID?
}

@MainActor
final class CredentialOrderingController {
    private let settings: AppSettings
    private let addCredential: @MainActor (ValidatedCredentialInput) async throws -> CredentialAddOutcome
    private let setKeyEnabled: @MainActor (UUID, Bool) throws -> Void
    private let deleteCredential: @MainActor (UUID) throws -> Void

    init(
        settings: AppSettings,
        addCredential: @escaping @MainActor (ValidatedCredentialInput) async throws -> CredentialAddOutcome,
        setKeyEnabled: @escaping @MainActor (UUID, Bool) throws -> Void,
        delete: @escaping @MainActor (UUID) throws -> Void
    ) {
        self.settings = settings
        self.addCredential = addCredential
        self.setKeyEnabled = setKeyEnabled
        self.deleteCredential = delete
    }

    func addValidatedCredential(
        _ input: ValidatedCredentialInput
    ) async throws -> KeyEditorSaveResult {
        let previousIDs = Set(settings.displayOrder.popoverCredentialIDs)
        let outcome = try await addCredential(input)
        if let addedID = outcome.addedCredentialID,
           !previousIDs.contains(addedID) {
            settings.appendCredential(addedID)
        }
        return outcome.saveResult
    }

    func setEnabled(_ id: UUID, enabled: Bool) throws {
        try setKeyEnabled(id, enabled)
    }

    func delete(_ id: UUID) throws {
        try deleteCredential(id)
        settings.removeCredential(id)
    }

    func move(
        _ sequence: CredentialDisplaySequence,
        id: UUID,
        toIndex: Int
    ) {
        settings.displayOrder = settings.displayOrder.moving(
            sequence,
            id: id,
            toIndex: toIndex
        )
    }

    func addToMenuBar(_ id: UUID, toIndex: Int) {
        settings.displayOrder = settings.displayOrder.addingToMenuBar(
            id,
            toIndex: toIndex
        )
    }

    func removeFromMenuBar(_ id: UUID) {
        settings.displayOrder = settings.displayOrder.removingFromMenuBar(id)
    }
}
```

- [ ] **Step 4: 运行测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/CredentialOrderingControllerTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/App/CredentialOrderingController.swift RoutinUsage/App/AppEnvironment.swift RoutinUsageTests/CredentialOrderingControllerTests.swift
git commit -m "feat: 凭证生命周期同步展示顺序"
```

---

### Task 4: 新设置壳与导航

**Files:**
- Create: `RoutinUsage/Views/Settings/SettingsWindowView.swift`
- Create: `RoutinUsage/Views/Settings/Components/SettingsPageHeader.swift`
- Create: `RoutinUsage/Views/Settings/SettingsWindowDockIconAnchor.swift`
- Create: `RoutinUsage/Views/Settings/CredentialManagementView.swift`
- Create: `RoutinUsage/Views/Settings/MenuBarOrderingView.swift`
- Create: `RoutinUsage/Views/Settings/PopoverOrderingView.swift`
- Create: `RoutinUsage/Views/Settings/GeneralSettingsView.swift`
- Create: `RoutinUsage/Views/Settings/HelpUpdateView.swift`
- Modify: `RoutinUsage/App/RoutinUsageApp.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `AppEnvironment`、`CredentialOrderingController`。
- Produces:
  - `enum SettingsSection: String, CaseIterable, Identifiable`
  - `struct SettingsWindowView: View`
  - `struct SettingsPageHeader: View`
  - `struct SettingsWindowDockIconAnchor: NSViewRepresentable`

- [ ] **Step 1: 添加导航静态测试**

创建或更新 `RoutinUsageTests/SettingsWindowShellTests.swift`：

```swift
import XCTest

final class SettingsWindowShellTests: XCTestCase {
    func test新设置窗口包含五个现代导航分类() throws {
        let shell = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "SettingsWindowView.swift"
        ])
        let credentialPage = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(shell.contains("enum SettingsSection"))
        XCTAssertTrue(shell.contains("case credentials"))
        XCTAssertTrue(shell.contains("case menuBar"))
        XCTAssertTrue(shell.contains("case popover"))
        XCTAssertTrue(shell.contains("case general"))
        XCTAssertTrue(shell.contains("case help"))
        XCTAssertTrue(shell.contains("liquidGlassWindowBackground()"))
        XCTAssertTrue(credentialPage.contains("SettingsPageHeader"))
        XCTAssertFalse(shell.contains("Routin 签到"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/SettingsWindowShellTests
```

预期：文件不存在导致失败。

- [ ] **Step 3: 实现设置壳**

创建 `SettingsWindowView.swift`：

```swift
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case credentials
    case menuBar
    case popover
    case general
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credentials: "凭证管理"
        case .menuBar: "菜单栏显示"
        case .popover: "弹窗显示"
        case .general: "通用"
        case .help: "帮助与更新"
        }
    }

    var symbol: String {
        switch self {
        case .credentials: "key.horizontal"
        case .menuBar: "menubar.rectangle"
        case .popover: "rectangle.bottomthird.inset.filled"
        case .general: "switch.2"
        case .help: "questionmark.circle"
        }
    }
}

struct SettingsWindowView: View {
    @Bindable var environment: AppEnvironment
    @State private var ordering: CredentialOrderingController
    @State private var selectedSection: SettingsSection = .credentials

    init(environment: AppEnvironment) {
        self.environment = environment
        _ordering = State(initialValue: CredentialOrderingController(
            settings: environment.settings,
            addCredential: { input in
                let previousIDs = Set(environment.store.orderedKeyIDs)
                let saveResult = try await environment.addValidatedCredential(input)
                let addedID = environment.store.orderedKeyIDs.first { !previousIDs.contains($0) }
                return CredentialAddOutcome(saveResult: saveResult, addedCredentialID: addedID)
            },
            setKeyEnabled: { try environment.setKeyEnabled($0, enabled: $1) },
            delete: { try environment.deleteKey($0) }
        ))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("MyToken")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .liquidGlassWindowBackground()
                .background(WindowFramePersistence())
                .background(SettingsWindowDockIconAnchor())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, idealWidth: 880, minHeight: 560, idealHeight: 640)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .credentials:
            CredentialManagementView(environment: environment, ordering: ordering)
        case .menuBar:
            MenuBarOrderingView(environment: environment, ordering: ordering)
        case .popover:
            PopoverOrderingView(environment: environment, ordering: ordering)
        case .general:
            GeneralSettingsView(environment: environment)
        case .help:
            HelpUpdateView(environment: environment)
        }
    }
}
```

创建 `SettingsPageHeader.swift`：

```swift
import SwiftUI

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.bottom, 18)
    }
}
```

复制 `RoutinUsage/Views/SettingsView.swift` 中 `SettingsDockIconAnchor` 和 `SettingsDockIconView` 的完整实现到 `SettingsWindowDockIconAnchor.swift`，并把两个类型和构造调用改名为 `SettingsWindowDockIconAnchor` / `SettingsWindowDockIconView`。旧设置文件保持原状，Task 11 删除时一并清理。

创建五个可编译的功能壳。它们都不是占位 `TODO`，而是每页先显示真实标题、副标题和当前统计；后续任务在同一文件中扩展内容。模板如下：

```swift
import SwiftUI

struct CredentialManagementView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController

    var body: some View {
        ScrollView {
            SettingsPageHeader(
                title: "凭证管理",
                subtitle: "\(environment.store.orderedKeyIDs.count) 个凭证"
            )
            .padding(24)
        }
    }
}
```

其余四页使用同样的结构，标题和副标题分别为：

```text
MenuBarOrderingView：菜单栏显示 / 菜单栏图标排序
PopoverOrderingView：弹窗显示 / 弹窗凭证排序
GeneralSettingsView：通用 / 刷新、启动与提醒
HelpUpdateView：帮助与更新 / 版本维护与反馈
```

`RoutinUsageApp` 的设置场景改为：

```swift
SettingsWindowView(environment: environment)
```

在 `project.yml` 的测试资源复制脚本中，删除 `SettingsView.swift` 复制行，新增：

```bash
cp "$PROJECT_DIR/RoutinUsage/Views/Settings/SettingsWindowView.swift" "$resource_dir/SettingsWindowView.swift.txt"
cp "$PROJECT_DIR/RoutinUsage/Views/Settings/Components/SettingsPageHeader.swift" "$resource_dir/SettingsPageHeader.swift.txt"
```

运行 `xcodegen generate`。

- [ ] **Step 4: 构建并运行壳测试**

```bash
xcodegen generate
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/SettingsWindowShellTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Views/Settings project.yml RoutinUsage.xcodeproj RoutinUsage/App/RoutinUsageApp.swift RoutinUsageTests/SettingsWindowShellTests.swift
git commit -m "feat: 新增设置窗口导航壳"
```

---

### Task 5: 共享凭证行和拖拽组件

**Files:**
- Create: `RoutinUsage/Views/Settings/Components/CredentialSummaryRow.swift`
- Create: `RoutinUsage/Views/Settings/Components/MenuBarIndicatorPreview.swift`
- Create: `RoutinUsage/Views/Settings/Components/CredentialDropDelegate.swift`
- Create: `RoutinUsage/Views/Settings/Components/ProviderFilterChips.swift`
- Test: `RoutinUsageTests/SettingsComponentTests.swift`

**Interfaces:**
- Consumes: `KeyUsageState`、`ProviderDescriptor`、`MenuBarIndicatorModel`、`MenuBarMultiUsageIcon`。
- Produces:
  - `CredentialSummaryRow`
  - `MenuBarIndicatorPreview`
  - `CredentialDropDelegate`
  - `ProviderFilterChips`
  - `extension UTType { static let credentialID }`

- [ ] **Step 1: 写组件静态和渲染测试**

创建 `RoutinUsageTests/SettingsComponentTests.swift`：

```swift
import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import RoutinUsage

final class SettingsComponentTests: XCTestCase {
    func test菜单栏预览复用真实图标渲染器() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "MenuBarIndicatorPreview.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarIndicatorModel.make("))
        XCTAssertTrue(source.contains("MenuBarMultiUsageIcon.image("))
    }

    func test拖拽使用专属凭证类型() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "Components", "CredentialDropDelegate.swift"
        ])

        XCTAssertTrue(source.contains("static let credentialID"))
        XCTAssertTrue(source.contains("ai.routin.mytoken.credential"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/SettingsComponentTests
```

预期：文件不存在导致失败。

- [ ] **Step 3: 实现共享组件**

`CredentialDropDelegate.swift` 必须包含：

```swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let credentialID = UTType("ai.routin.mytoken.credential") ?? .plainText
}

struct CredentialDropDelegate: DropDelegate {
    let targetID: UUID
    let draggedID: UUID?
    let canAccept: (UUID) -> Bool
    let move: (UUID) -> Void
    let finish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != targetID,
              canAccept(draggedID)
        else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            move(draggedID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        finish()
        return draggedID != nil
    }
}
```

`MenuBarIndicatorPreview.swift` 使用：

```swift
let indicator = MenuBarIndicatorModel.make(
    state: state,
    descriptor: descriptor,
    dimension: environment.settings.displayDimension
)
let image = MenuBarMultiUsageIcon.image(
    indicators: [indicator],
    appearance: NSApp.effectiveAppearance
)
Image(nsImage: image)
    .interpolation(.high)
    .scaledToFit()
    .frame(height: 26)
```

`CredentialSummaryRow` 的布局固定为：

```swift
HStack(spacing: 12) {
    leading
    VStack(alignment: .leading, spacing: 3) {
        Text(alias).font(.body.weight(.medium))
        Text("\(provider) · \(planType)").font(.caption).foregroundStyle(.secondary)
    }
    Spacer(minLength: 12)
    trailing
}
```

`ProviderFilterChips` 使用胶囊按钮渲染“全部”和供应商名，选中项使用 `Color.accentColor.opacity(0.14)` 和 hairline 边框。

- [ ] **Step 4: 构建并运行组件测试**

```bash
xcodegen generate
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/SettingsComponentTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Views/Settings/Components RoutinUsageTests/SettingsComponentTests.swift RoutinUsage.xcodeproj
git commit -m "feat: 新增设置共享凭证组件"
```

---

### Task 6: 凭证管理页

**Files:**
- Modify: `RoutinUsage/Views/Settings/CredentialManagementView.swift`
- Modify: `RoutinUsage/Views/Settings/SettingsWindowView.swift`
- Modify: `RoutinUsage/Views/Settings/Components/CredentialSummaryRow.swift`
- Test: `RoutinUsageTests/CredentialManagementViewTests.swift`

**Interfaces:**
- Consumes: `CredentialOrderingController.addValidatedCredential`、`setEnabled`、`delete`、`CredentialSummaryRow`。
- Produces:
  - `CredentialFilter: Equatable`
  - `CredentialManagementView(environment:ordering:)`

- [ ] **Step 1: 写分组和过滤失败测试**

创建 `RoutinUsageTests/CredentialManagementViewTests.swift`：

```swift
import XCTest

final class CredentialManagementViewTests: XCTestCase {
    func test凭证管理页包含分组筛选搜索和危险删除确认() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(source.contains("struct CredentialFilter"))
        XCTAssertTrue(source.contains("ProviderID.allCases"))
        XCTAssertTrue(source.contains("searchText"))
        XCTAssertTrue(source.contains("confirmationDialog"))
        XCTAssertTrue(source.contains("将同时删除本地保存的密钥和用量缓存"))
        XCTAssertTrue(source.contains("CredentialSummaryRow"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/CredentialManagementViewTests
```

预期：断言失败。

- [ ] **Step 3: 实现凭证页**

`CredentialFilter` 定义为：

```swift
struct CredentialFilter: Equatable {
    var status: CredentialStatusFilter = .all
    var provider: ProviderID?
    var searchText = ""
}

enum CredentialStatusFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled
    var id: String { rawValue }
    var title: String { switch self { case .all: "全部"; case .enabled: "启用"; case .disabled: "停用" } }
}
```

页面结构：

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(
            title: "凭证管理",
            subtitle: "\(store.orderedKeyIDs.count) 个凭证",
            trailing: AnyView(addButton)
        )
        filterBar
        providerGroups
    }
    .padding(24)
}
.sheet(item: $editor) { presentation in credentialEditor(presentation) }
.confirmationDialog(
    "确定删除这个凭证？",
    isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
    ),
    titleVisibility: .visible
) {
    Button("删除", role: .destructive) { deletePending() }
    Button("取消", role: .cancel) { pendingDeletion = nil }
} message: {
    Text("将同时删除本地保存的密钥和用量缓存，此操作无法撤销。")
}
```

分组计算：

```swift
private var groups: [(provider: ProviderDescriptor, states: [KeyUsageState])] {
    ProviderID.allCases.compactMap { providerID in
        let states = visibleStates.filter { $0.configuration.providerID == providerID }
        guard let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == providerID }),
              !states.isEmpty
        else { return nil }
        return (descriptor, states)
    }
}
```

添加成功后不自动加入菜单栏。添加和编辑继续使用 `CredentialEditorView`，保存闭包调用 `ordering.addValidatedCredential(input)`。

- [ ] **Step 4: 运行页面测试和构建**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/CredentialManagementViewTests
```

预期：通过。

- [ ] **Step 5: 手工检查添加、停用、删除**

启动 Debug 应用，验证添加凭证后出现在弹窗末尾与菜单栏待选区；停用后两个真实展示面隐藏；删除后凭证、Keychain 对应项、缓存和两个顺序数组都清理。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Views/Settings RoutinUsageTests/CredentialManagementViewTests.swift
git commit -m "feat: 重建凭证管理设置页"
```

---

### Task 7: 菜单栏排序页

**Files:**
- Modify: `RoutinUsage/Views/Settings/MenuBarOrderingView.swift`
- Test: `RoutinUsageTests/MenuBarOrderingViewTests.swift`

**Interfaces:**
- Consumes: `CredentialDisplayOrder.moving`、`addingToMenuBar`、`removingFromMenuBar`、`MenuBarIndicatorPreview`、`CredentialDropDelegate`。
- Produces: `MenuBarOrderingView(environment:ordering:)`

- [ ] **Step 1: 写排序约束失败测试**

创建 `RoutinUsageTests/MenuBarOrderingViewTests.swift`：

```swift
import XCTest

final class MenuBarOrderingViewTests: XCTestCase {
    func test菜单栏页包含模拟条展示区待选区和上限提示() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarOrderingView.swift"
        ])

        XCTAssertTrue(source.contains("MenuBarIndicatorPreview"))
        XCTAssertTrue(source.contains("展示区"))
        XCTAssertTrue(source.contains("待选区"))
        XCTAssertTrue(source.contains("maximumMenuBarCount"))
        XCTAssertTrue(source.contains("addingToMenuBar"))
        XCTAssertTrue(source.contains("removingFromMenuBar"))
        XCTAssertTrue(source.contains("UTType.credentialID"))
        XCTAssertTrue(source.contains("chevron.up"))
        XCTAssertTrue(source.contains("chevron.down"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/MenuBarOrderingViewTests
```

预期：断言失败。

- [ ] **Step 3: 实现菜单栏排序**

视图常驻派生：

```swift
private var enabledIDs: Set<UUID> { Set(environment.store.visibleKeyIDs) }
private var visibility: CredentialDisplayVisibility {
    environment.settings.displayOrder.visible(enabledIDs: enabledIDs)
}
```

顶部 `menuBarSimulation` 使用 `HStack` 渲染 `visibility.menuBarIDs` 对应的真实图标序列。下方在宽窗口使用 `HStack(alignment: .top, spacing: 20)` 放展示区和待选区，窗口宽度低于 760 时使用 `VStack`。

拖拽行模板：

```swift
row
    .onDrag {
        draggedID = state.configuration.id
        let provider = NSItemProvider(object: state.configuration.id.uuidString as NSString)
        provider.registerObject(state.configuration.id.uuidString as NSString, visibility: .all)
        return provider
    }
    .onDrop(
        of: [UTType.credentialID],
        delegate: CredentialDropDelegate(
            targetID: state.configuration.id,
            draggedID: draggedID,
            canAccept: canAccept,
            move: { dragged in move(dragged, before: state.configuration.id) },
            finish: { draggedID = nil }
        )
    )
```

`move(_:before:)` 先把目标 ID 在当前序列中的 index 作为 `toIndex`，再调用 `ordering.move(.menuBar, id:toIndex:)`。从待选区拖入展示区时调用 `ordering.addToMenuBar(_:toIndex:)`；展示区满 5 个时 `canAccept` 返回 false。每行保留上移、下移、添加、移除按钮，并使用 `.accessibilityAction` 暴露相同动作。

- [ ] **Step 4: 运行页面测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/MenuBarOrderingViewTests
```

预期：通过。

- [ ] **Step 5: 手工验证实时同步和上限**

用至少 7 个启用凭证验证：展示区内部拖动、待选区内部拖动、跨区拖动、第 6 个拒绝进入、真实菜单栏立即更新、弹窗顺序不变。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Views/Settings/MenuBarOrderingView.swift RoutinUsageTests/MenuBarOrderingViewTests.swift
git commit -m "feat: 重建菜单栏显示排序页"
```

---

### Task 8: 弹窗排序页

**Files:**
- Modify: `RoutinUsage/Views/Settings/PopoverOrderingView.swift`
- Test: `RoutinUsageTests/PopoverOrderingViewTests.swift`

**Interfaces:**
- Consumes: `CredentialDisplayOrder.moving(.popover:id:toIndex:)`、`CredentialSummaryRow`。
- Produces: `PopoverOrderingView(environment:ordering:)`

- [ ] **Step 1: 写独立排序失败测试**

创建 `RoutinUsageTests/PopoverOrderingViewTests.swift`：

```swift
import XCTest

final class PopoverOrderingViewTests: XCTestCase {
    func test弹窗排序页只调用弹窗序列并显示基本信息() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "PopoverOrderingView.swift"
        ])

        XCTAssertTrue(source.contains("moving(.popover"))
        XCTAssertTrue(source.contains("visiblePopoverIDs"))
        XCTAssertTrue(source.contains("供应商"))
        XCTAssertTrue(source.contains("套餐"))
        XCTAssertTrue(source.contains("实时同步到菜单栏弹窗"))
        XCTAssertFalse(source.contains("addingToMenuBar"))
        XCTAssertFalse(source.contains("removingFromMenuBar"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/PopoverOrderingViewTests
```

预期：断言失败。

- [ ] **Step 3: 实现弹窗模拟排序**

页面顶部放 `SettingsPageHeader(title: "弹窗显示", subtitle: "已启用凭证的弹窗顺序")`。主内容是一个 440 点宽的玻璃模拟弹窗：

```swift
VStack(spacing: 8) {
    ForEach(visiblePopoverIDs, id: \.self) { id in
        if let state = environment.store.state(for: id) {
            CredentialSummaryRow(
                alias: state.configuration.displayName,
                provider: providerName(state.configuration.providerID),
                planType: planName(state),
                leading: providerIcon(state),
                trailing: Image(systemName: "line.3.horizontal")
            )
            .liquidGlassSurface(cornerRadius: 12)
            .onDrag { dragProvider(id) }
            .onDrop(of: [UTType.credentialID], delegate: popoverDropDelegate(for: id))
        }
    }
}
.frame(width: 440)
.padding(16)
.liquidGlassSurface(cornerRadius: 18)
```

排序只调用：

```swift
ordering.move(.popover, id: draggedID, toIndex: targetIndex)
```

页面底部显示 `Text("实时同步到菜单栏弹窗")`。不出现菜单栏添加或移除按钮。

- [ ] **Step 4: 运行页面测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/PopoverOrderingViewTests
```

预期：通过。

- [ ] **Step 5: 手工验证与菜单栏互不影响**

调整弹窗顺序后检查真实弹窗；再打开菜单栏页，确认菜单栏顺序保持不变。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Views/Settings/PopoverOrderingView.swift RoutinUsageTests/PopoverOrderingViewTests.swift
git commit -m "feat: 重建弹窗显示排序页"
```

---

### Task 9: 通用设置页

**Files:**
- Modify: `RoutinUsage/Views/Settings/GeneralSettingsView.swift`
- Test: `RoutinUsageTests/GeneralSettingsViewTests.swift`

**Interfaces:**
- Consumes: `AppSettings.refreshMinutes`、`launchAtLogin`、`displayDimension`、`notificationsEnabled`、`thresholds`。
- Produces: `GeneralSettingsView(environment:)`

- [ ] **Step 1: 写页面覆盖失败测试**

创建 `RoutinUsageTests/GeneralSettingsViewTests.swift`：

```swift
import XCTest

final class GeneralSettingsViewTests: XCTestCase {
    func test通用页保留刷新启动显示和通知设置() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "GeneralSettingsView.swift"
        ])

        XCTAssertTrue(source.contains("刷新"))
        XCTAssertTrue(source.contains("登录时启动"))
        XCTAssertTrue(source.contains("displayDimension"))
        XCTAssertTrue(source.contains("notificationsEnabled"))
        XCTAssertTrue(source.contains("thresholds"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/GeneralSettingsViewTests
```

预期：断言失败。

- [ ] **Step 3: 实现通用页**

使用四个分组表单：

```swift
struct GeneralSettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var operationError: String?
}
```

```swift
Form {
    Section("刷新") {
        Picker("刷新间隔", selection: $environment.settings.refreshMinutes) {
            ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                Text("每 \(minutes) 分钟").tag(minutes)
            }
        }
    }
    Section("启动") {
        Toggle("登录时启动", isOn: launchAtLoginBinding)
    }
    Section("显示") {
        Picker("用量维度", selection: $environment.settings.displayDimension) {
            ForEach(DisplayDimension.allCases) { dimension in
                Text(dimension.title).tag(dimension)
            }
        }
    }
    Section("通知") {
        Toggle("启用通知", isOn: $environment.settings.notificationsEnabled)
        Stepper(value: $environment.settings.thresholds.low, in: 0...100) {
            Text("低阈值 \(environment.settings.thresholds.low)%")
        }
        Stepper(value: $environment.settings.thresholds.high, in: 0...100) {
            Text("高阈值 \(environment.settings.thresholds.high)%")
        }
    }
}
.formStyle(.grouped)
```

如果 `DisplayDimension` 还没有 `title`，在本任务中新增：

```swift
extension DisplayDimension {
    var title: String {
        switch self {
        case .fiveHour: "5 小时"
        case .weekly: "周"
        }
    }
}
```

登录启动绑定沿用 `LoginItemSettingSynchronizer.setEnabled(_:settings:manager:)`，失败时设置 `operationError` 并让开关回滚。

- [ ] **Step 4: 运行页面测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/GeneralSettingsViewTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Views/Settings/GeneralSettingsView.swift RoutinUsageTests/GeneralSettingsViewTests.swift
git commit -m "feat: 重建通用设置页"
```

---

### Task 10: 帮助更新页并移除签到区块

**Files:**
- Modify: `RoutinUsage/Views/Settings/HelpUpdateView.swift`
- Modify: `RoutinUsage/Views/UsagePopoverView.swift`
- Test: `RoutinUsageTests/HelpUpdateViewTests.swift`

**Interfaces:**
- Consumes: `AppUpdateStatus`、`UpdateNotesView`、`environment.openIssueReport`。
- Produces: `HelpUpdateView(environment:)`

- [ ] **Step 1: 写更新和反馈失败测试**

创建 `RoutinUsageTests/HelpUpdateViewTests.swift`：

```swift
import XCTest

final class HelpUpdateViewTests: XCTestCase {
    func test帮助页提供版本更新进度发布说明和反馈() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "HelpUpdateView.swift"
        ])

        XCTAssertTrue(source.contains("当前版本"))
        XCTAssertTrue(source.contains("检查更新"))
        XCTAssertTrue(source.contains("ProgressView"))
        XCTAssertTrue(source.contains("UpdateNotesView"))
        XCTAssertTrue(source.contains("提交问题"))
        XCTAssertTrue(source.contains("installAvailableUpdate"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/HelpUpdateViewTests
```

预期：断言失败。

- [ ] **Step 3: 实现帮助页**

页面分为三个区块：

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(title: "帮助与更新", subtitle: "版本维护和问题反馈")
        currentVersionSection
        updateStatusSection
        feedbackSection
    }
    .padding(24)
}
```

更新状态分支复用现有 `AppUpdateStatus` 的 `idle`、`checking`、`available`、`downloading`、`completed`、`failed` 渲染逻辑。`available` 分支调用 `UpdateNotesView(notes: update.notes)`，并提供“安装更新”和“查看发布说明”。反馈按钮调用：

```swift
Task { await environment.openIssueReport() }
```

同时检查真实弹窗：保留更新提示，移除 `Routin 签到` 状态块；不删除 Codex 分组检测需要的登录流程。

- [ ] **Step 4: 运行页面测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/HelpUpdateViewTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Views/Settings/HelpUpdateView.swift RoutinUsage/Views/UsagePopoverView.swift RoutinUsageTests/HelpUpdateViewTests.swift
git commit -m "feat: 重建帮助更新页并移除设置签到区块"
```

---

### Task 11: 删除旧设置实现并迁移静态测试

**Files:**
- Delete: `RoutinUsage/Views/SettingsView.swift`
- Modify: `RoutinUsageTests/AppSettingsTests.swift`
- Modify: `RoutinUsageTests/SettingsSortingModeTests.swift`
- Modify: `RoutinUsageTests/UsagePresentationPolicyTests.swift`
- Modify: `RoutinUsageTests/ProjectBootstrapTests.swift`
- Modify: `RoutinUsageTests/SettingsProviderGroupingTests.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: Task 4 到 Task 10 的新设置文件。
- Produces: 设置入口只保留 `SettingsWindowView`，旧 `SettingsView` 和旧顺序推导完全删除。

- [ ] **Step 1: 搜索所有旧引用**

```bash
rg -n "SettingsView|LegacyCredentialDisplayOrder|selectedCredentialIDs|availableCredentialIDs" RoutinUsage RoutinUsageTests project.yml
```

允许保留：

- `AppSettings` 中旧字段定义和读取，用于迁移。
- `CredentialDisplayOrder.migrated` 的测试入参。

禁止保留：

- `Views/SettingsView.swift`。
- `LegacyCredentialDisplayOrder.popoverIDs`。
- 真实 UI 或新测试读取旧字段作为展示顺序。

- [ ] **Step 2: 更新旧静态测试到新路径**

所有原本读取 `RoutinUsage/Views/SettingsView.swift` 的测试改为读取对应新文件：

```swift
try TestSourceReader.read([
    "RoutinUsage", "Views", "Settings", "SettingsWindowView.swift"
])
```

`SettingsSortingModeTests` 改为断言：

```swift
let menuBar = try TestSourceReader.read([
    "RoutinUsage", "Views", "Settings", "MenuBarOrderingView.swift"
])
XCTAssertTrue(menuBar.contains("CredentialDropDelegate"))
XCTAssertTrue(menuBar.contains("UTType.credentialID"))
XCTAssertFalse(menuBar.contains("isReorderingMenuBarIndicators"))
XCTAssertFalse(menuBar.contains("isReorderingAvailableIndicators"))
```

`UsagePresentationPolicyTests` 中设置页用量指标检查迁移到 `CredentialManagementView.swift`；Dock 图标检查迁移到 `SettingsWindowView.swift`。

`project.yml` 删除旧 `SettingsView.swift` 资源复制，并确认不再有旧文件路径。

- [ ] **Step 3: 删除旧文件并重新生成工程**

```bash
rm RoutinUsage/Views/SettingsView.swift
xcodegen generate
```

- [ ] **Step 4: 全量测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test
```

预期：全量通过；全量测试数量可能因新增测试增加。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor: 移除旧设置实现和旧弹窗顺序推导"
```

---

### Task 12: 液态玻璃和无障碍统一检查

**Files:**
- Modify: `RoutinUsage/Views/LiquidGlassSurface.swift`
- Modify: `RoutinUsage/Views/Settings/**/*.swift`
- Test: `RoutinUsageTests/SettingsAccessibilityTests.swift`

**Interfaces:**
- Consumes: Task 4 到 Task 10 的页面。
- Produces: 设置页统一的玻璃层级、减少动态效果和无障碍断言。

- [ ] **Step 1: 写玻璃和无障碍失败测试**

创建 `RoutinUsageTests/SettingsAccessibilityTests.swift`：

```swift
import XCTest

final class SettingsAccessibilityTests: XCTestCase {
    func test设置页统一使用玻璃扩展并支持减少动态效果() throws {
        let files = [
            "SettingsWindowView",
            "CredentialManagementView",
            "MenuBarOrderingView",
            "PopoverOrderingView",
            "GeneralSettingsView",
            "HelpUpdateView"
        ]

        for file in files {
            let source = try TestSourceReader.read([
                "RoutinUsage", "Views", "Settings", "\(file).swift"
            ])
            XCTAssertFalse(
                source.contains("glassEffect("),
                "\(file) 必须通过 LiquidGlassSurface 使用玻璃效果"
            )
        }

        let ordering = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "MenuBarOrderingView.swift"
        ])
        XCTAssertTrue(ordering.contains("accessibilityAction"))
        XCTAssertTrue(ordering.contains("accessibilityLabel"))
        XCTAssertTrue(ordering.contains("reduceMotion"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/SettingsAccessibilityTests
```

预期：至少一处直接 `glassEffect` 或缺少无桥接 API 导致失败。

- [ ] **Step 3: 收敛玻璃和动画**

`LiquidGlassSurface` 增加环境读取：

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

拖拽和插入动画统一改为：

```swift
withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) { }
```

页面不得直接调用 `glassEffect`；所有表面继续调用 `liquidGlassWindowBackground()`、`liquidGlassSurface(cornerRadius:)`、`liquidGlassButton(prominent:)`。

- [ ] **Step 4: 运行无障碍测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test -only-testing:RoutinUsageTests/SettingsAccessibilityTests
```

预期：通过。

- [ ] **Step 5: 提交**

```bash
git add RoutinUsage/Views/LiquidGlassSurface.swift RoutinUsage/Views/Settings RoutinUsageTests/SettingsAccessibilityTests.swift
git commit -m "feat: 统一设置液态玻璃与无障碍行为"
```

---

### Task 13: 最终验证和 Debug 包交付

**Files:**
- Modify: 允许修复 Task 1 到 Task 12 验收中发现的问题。
- Test: 全量测试。

**Interfaces:**
- Consumes: 所有已完成任务。
- Produces: 可运行、可持久化、可跨窗口验证的 Debug 版 `MyToken.app`。

- [ ] **Step 1: 静态冲突检查**

```bash
rg -n "selectedCredentialIDs|availableCredentialIDs|LegacyCredentialDisplayOrder|glassEffect\\(" RoutinUsage RoutinUsageTests
rg -n "TODO|TBD|待定|fill in|implement later" RoutinUsage/Views/Settings RoutinUsage/Models/CredentialDisplayOrder.swift
```

预期：旧字段只出现在 `AppSettings` 与迁移代码；设置页没有直接 `glassEffect`；没有占位符。

- [ ] **Step 2: 全量构建测试**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' test
```

预期：全部通过。

- [ ] **Step 3: 构建 Debug 应用**

```bash
xcodebuild -project RoutinUsage.xcodeproj -scheme RoutinUsage -destination 'platform=macOS' build
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 4: 重启 Debug 应用**

```bash
pids=$(pgrep -x MyToken || true)
if [ -n "$pids" ]; then kill $pids; sleep 1; fi
open '/Users/dickies/Library/Developer/Xcode/DerivedData/RoutinUsage-dnzgzojdhsoggtadbwtoaftudwet/Build/Products/Debug/MyToken.app'
```

预期：进程存在，菜单栏图标出现。

- [ ] **Step 5: 手工验收矩阵**

逐项验证并记录结果：

1. 打开设置窗口，检查五个导航分类、页面间距和玻璃质感。
2. 使用至少 7 个启用凭证，分别调整菜单栏和弹窗顺序，确认真实界面实时更新且互不影响。
3. 停用凭证后两个真实展示面隐藏，重新启用后分别回到原位置。
4. 删除凭证后确认设置、真实菜单栏、真实弹窗、本地密钥和缓存清理。
5. 重启应用后两个顺序保持。
6. 从旧配置升级时菜单栏顺序不丢。
7. 在浅色、深色、增强对比度和“减弱动态效果”下检查所有设置页。
8. 把窗口缩放到最小宽度，确认菜单栏展示区 / 待选区堆叠，文字不重叠。
9. 点击真实菜单栏图标，确认弹窗仍出现在当前显示器。
10. 验证设置页不再出现 Routin 签到区块，帮助页的更新和反馈功能正常。

- [ ] **Step 6: 提交最终修复**

```bash
git status --short
git add -A
git commit -m "test: 完成设置界面重构验收修复"
```

## Self-Review

- 已覆盖规范中的独立顺序模型、迁移、真实菜单栏、真实弹窗、生命周期同步、五个设置分类、液态玻璃、拖拽、无障碍、测试和手工验收。
- 排序接口在 Task 1 定义，并在 Task 2、3、7、8 中使用相同签名。
- 新文件使用 XcodeGen 生成工程，不需要手工维护 `project.pbxproj`。
- 旧 `CredentialDisplayOrder` 在 Task 1 过渡改名为 `LegacyCredentialDisplayOrder`，在 Task 2 后仅允许迁移阶段存在，Task 11 全量清理。
- 真实 UI 切换和旧静态测试迁移分开成任务，保证每个阶段都能编译运行。
