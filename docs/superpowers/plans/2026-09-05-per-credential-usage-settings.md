# 按凭证配置菜单栏指标与用量提醒实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将全局菜单栏用量维度和全局提醒阈值改造为按凭证选择单一菜单栏指标、按凭证和指标配置独立提醒规则。

**Architecture:** 以 `UsageSnapshot.normalizedMetrics` 和稳定 `metricID` 为事实来源，新增显式指标语义、供应商能力描述、凭证用量偏好和两个独立解析器。菜单栏通过 `MenuBarMetricResolver` 解析每个凭证的单一指标；通知通过 `MetricAlertRuleResolver` 和规则驱动的 `AlertEvaluator` 只评估标准化指标。

**Tech Stack:** Swift 5、SwiftUI、Observation、AppKit、UserNotifications、UserDefaults、XCTest、XcodeGen，最低 macOS 14.0。

**Spec:** `docs/superpowers/specs/2026-09-05-per-credential-usage-settings-design.md`

## Global Constraints

- 每个凭证在菜单栏中只显示一个指标，默认选择“自动”。
- 菜单栏最多保持 5 个凭证指标，不改变 `CredentialDisplayOrder.maximumMenuBarCount`。
- 指标选项以运行时 `normalizedMetrics` 为事实来源，供应商能力只作为首次刷新前的回退。
- 应用通知总开关和凭证通知开关默认开启，但必须保留已有用户主动关闭的总开关。
- 新发现的可预警指标默认启用；用户关闭过的同一规则不得因指标重新出现而自动开启。
- 不再使用指标标签文本执行正常业务判断；标签推断只允许用于旧缓存解码迁移。
- `KeyConfiguration.metadata` 继续只保存供应商请求和非秘密配置，不写入菜单栏或通知偏好。
- 通用设置最终只保留刷新间隔、登录时启动和应用通知总开关。
- 所有用户界面文字、代码注释和提交信息使用中文。
- 新增 Swift 文件后运行 `xcodegen generate`；前端包管理约束不适用于本 macOS 原生项目。
- 当前工作区存在尚未提交的菜单栏管理改动。执行前必须保留这些改动；不得通过 `reset`、`checkout --` 或从旧 `HEAD` 创建不包含它们的工作树来丢弃。

---

### Task 1: 为标准化指标增加显式语义

**Files:**
- Modify: `RoutinUsage/Models/UsageSnapshot.swift`
- Modify: `RoutinUsage/Providers/DeepSeekUsageProvider.swift`
- Modify: `RoutinUsage/Providers/GLMUsageProvider.swift`
- Modify: `RoutinUsage/Providers/NewAPIUsageProvider.swift`
- Modify: `RoutinUsage/Providers/VolcenginePlanUsageProvider.swift`
- Modify: `RoutinUsage/Usage/UsageMapper.swift`
- Test: `RoutinUsageTests/UsageSnapshotTests.swift`
- Test: `RoutinUsageTests/ProviderRoutingTests.swift`
- Test: `RoutinUsageTests/UsageFormatterTests.swift`

**Interfaces:**
- Consumes: 现有 `NormalizedUsageMetric.presentation`、`used`、`remaining`、`value`。
- Produces: `NormalizedUsageMetricSemantic`、`NormalizedUsageMetric.semantic`，供菜单栏和提醒解析器使用。

- [ ] **Step 1: 写入旧缓存与显式语义的失败测试**

在 `UsageSnapshotTests.swift` 增加：

```swift
func test标准化指标编码保留显式语义() throws {
    let metric = NormalizedUsageMetric(
        id: "monthly",
        label: "近一月用量",
        used: 30,
        limit: 100,
        remaining: 70,
        unit: .token,
        presentation: .progress,
        semantic: .usedQuota
    )

    let data = try JSONEncoder().encode(metric)
    let decoded = try JSONDecoder().decode(NormalizedUsageMetric.self, from: data)

    XCTAssertEqual(decoded.semantic, .usedQuota)
}

func test旧缓存缺少语义时只在解码阶段执行兼容推断() throws {
    let json = #"{"id":"remaining","label":"剩余额度","remaining":20,"limit":100,"unit":"token","presentation":"progress","healthState":"normal"}"#

    let decoded = try JSONDecoder().decode(
        NormalizedUsageMetric.self,
        from: Data(json.utf8)
    )

    XCTAssertEqual(decoded.semantic, .remainingQuota)
}
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/UsageSnapshotTests \
  -only-testing:RoutinUsageTests/ProviderRoutingTests \
  -only-testing:RoutinUsageTests/UsageFormatterTests
```

Expected: FAIL，提示 `NormalizedUsageMetricSemantic`、`semantic` 或新初始化参数不存在。

- [ ] **Step 3: 增加语义模型和旧缓存解码逻辑**

在 `UsageSnapshot.swift` 增加：

```swift
enum NormalizedUsageMetricSemantic: String, Codable, Equatable, Sendable {
    case usedQuota
    case remainingQuota
    case balance
    case status
    case value
}
```

为 `NormalizedUsageMetric` 增加：

```swift
let semantic: NormalizedUsageMetricSemantic
```

初始化器要求调用方明确传入 `semantic`。自定义 `init(from:)` 使用 `decodeIfPresent`；缺失时仅按以下兼容规则推断：

```swift
private static func legacySemantic(
    id: String,
    label: String,
    presentation: NormalizedUsageMetricPresentation
) -> NormalizedUsageMetricSemantic {
    switch presentation {
    case .balance: return .balance
    case .status: return .status
    case .value: return .value
    case .progress:
        return id.localizedCaseInsensitiveContains("remaining") || label.contains("剩余")
            ? .remainingQuota
            : .usedQuota
    }
}
```

- [ ] **Step 4: 更新所有生产指标构造点**

所有供应商必须显式填写语义：

```swift
NormalizedUsageMetric(
    id: "monthly",
    label: "近一月用量",
    used: used,
    limit: quota,
    remaining: max(0, quota - used),
    unit: .token,
    presentation: .progress,
    semantic: .usedQuota,
    healthState: healthState
)
```

余额使用 `.balance`，可用状态使用 `.status`，无额度上限的统计值使用 `.value`。更新测试工厂和测试内直接构造的指标，禁止依赖初始化器默认语义。

- [ ] **Step 5: 运行指标与供应商测试**

Run: 与 Step 2 相同。

Expected: PASS；旧缓存测试证明只有解码路径使用标签兼容推断。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Models/UsageSnapshot.swift RoutinUsage/Providers \
  RoutinUsage/Usage/UsageMapper.swift RoutinUsageTests
git commit -m "refactor: 为用量指标增加显式语义"
```

### Task 2: 声明供应商指标能力

**Files:**
- Create: `RoutinUsage/Providers/UsageMetricCapability.swift`
- Modify: `RoutinUsage/Providers/UsageProvider.swift`
- Modify: `RoutinUsage/Providers/DeepSeekUsageProvider.swift`
- Modify: `RoutinUsage/Providers/GLMUsageProvider.swift`
- Modify: `RoutinUsage/Providers/NewAPIUsageProvider.swift`
- Modify: `RoutinUsage/Providers/VolcenginePlanUsageProvider.swift`
- Test: `RoutinUsageTests/ProviderRoutingTests.swift`
- Test: `RoutinUsageTests/UsageSnapshotTests.swift`

**Interfaces:**
- Consumes: `KeyConfiguration.providerID`、`credentialKind`、套餐相关 `metadata`。
- Produces: `UsageMetricCapability`、`UsageProvider.metricCapabilities(for:)`、`ProviderRegistry.metricCapabilities(for:)`。

- [ ] **Step 1: 写入首次刷新前能力声明的失败测试**

```swift
func test火山CodingPlan在首次刷新前声明可选窗口() throws {
    let configuration = KeyConfiguration(
        id: UUID(),
        name: "火山",
        keySuffix: "",
        sortOrder: 0,
        providerID: .volcengine,
        credentialKind: .accessKeyPair,
        metadata: ["planType": "coding"]
    )

    let registry = ProviderRegistry(providers: [VolcenginePlanUsageProvider()])
    let capabilities = registry.metricCapabilities(for: configuration)

    XCTAssertEqual(capabilities.map(\.metricID), ["fiveHour", "weekly", "monthly"])
    XCTAssertEqual(capabilities.first?.menuBarPriority, 0)
}
```

使用测试注册表或现有 `ProviderRegistry` 构造方式，不访问网络。

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/ProviderRoutingTests
```

Expected: FAIL，提示能力类型或注册表方法不存在。

- [ ] **Step 3: 实现能力描述接口**

新增：

```swift
struct UsageMetricCapability: Codable, Equatable, Identifiable, Sendable {
    let metricID: String
    let label: String
    let presentation: NormalizedUsageMetricPresentation
    let semantic: NormalizedUsageMetricSemantic
    let isMenuBarSelectable: Bool
    let menuBarPriority: Int?
    let defaultAlertEnabled: Bool
    let defaultAbsoluteAlertThreshold: Decimal?

    var id: String { metricID }
}
```

扩展供应商协议：

```swift
protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability]
    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot?
    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot?
}

extension UsageProvider {
    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] { [] }
}
```

`ProviderRegistry` 增加：

```swift
func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] {
    provider(for: configuration.providerID)?.metricCapabilities(for: configuration) ?? []
}
```

- [ ] **Step 4: 为各供应商提供明确能力**

- Routin：5 小时、周；Token 包配置只声明 Token 总量。
- DeepSeek：余额和可用状态；存在 `balanceWarningThreshold` 时写入余额能力的 `defaultAbsoluteAlertThreshold`。
- GLM：适配器实际能够返回的配额窗口；普通模型和 MCP 计数标记为不可用于菜单栏、默认不提醒。
- 火山：5 小时、周、月，根据 `planType` 保持稳定顺序。
- New API：账户额度可用于菜单栏；今日、24 小时、7 天、30 天统计值默认不进入菜单栏且不提醒。

- [ ] **Step 5: 验证能力测试**

Run: 与 Step 2 相同。

Expected: PASS，且能力顺序固定、不依赖字典枚举顺序。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Providers RoutinUsageTests/ProviderRoutingTests.swift
git commit -m "feat: 声明供应商用量指标能力"
```

### Task 3: 持久化每凭证用量偏好并迁移全局设置

**Files:**
- Create: `RoutinUsage/Models/CredentialUsagePreferences.swift`
- Modify: `RoutinUsage/Models/AppSettings.swift`
- Modify: `RoutinUsage/Views/Settings/CredentialManagementModel.swift`
- Test: `RoutinUsageTests/AppSettingsTests.swift`
- Test: `RoutinUsageTests/CredentialManagementViewTests.swift`

**Interfaces:**
- Consumes: 旧 `displayDimension`、`thresholds`、凭证 UUID、指标能力或快照指标。
- Produces: `CredentialUsagePreferences`、`MetricAlertRule`、`AppSettings.usagePreferences(for:)`、更新和清理 API。

- [ ] **Step 1: 写入默认值、持久化和删除清理测试**

```swift
func test新凭证用量偏好默认自动且提醒开启() throws {
    let context = try makeContext()
    defer { context.cleanUp() }
    let settings = AppSettings(defaults: context.defaults)
    let id = UUID()

    let preferences = settings.usagePreferences(for: id)

    XCTAssertNil(preferences.menuBarMetricID)
    XCTAssertTrue(preferences.notificationsEnabled)
    XCTAssertEqual(preferences.alertRules, [])
}

func test凭证用量偏好可持久化并按凭证删除() throws {
    let context = try makeContext()
    defer { context.cleanUp() }
    let id = UUID()
    let settings = AppSettings(defaults: context.defaults)
    var preferences = settings.usagePreferences(for: id)
    preferences.menuBarMetricID = "weekly"
    settings.setUsagePreferences(preferences, for: id)

    XCTAssertEqual(AppSettings(defaults: context.defaults).usagePreferences(for: id).menuBarMetricID, "weekly")

    settings.removeUsagePreferences(for: id)
    XCTAssertNil(AppSettings(defaults: context.defaults).storedUsagePreferences(for: id))
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/AppSettingsTests \
  -only-testing:RoutinUsageTests/CredentialManagementViewTests
```

Expected: FAIL，提示偏好模型和 AppSettings API 不存在。

- [ ] **Step 3: 实现偏好和规则类型**

在新文件中定义设计文档中的类型，并提供默认值：

```swift
struct CredentialUsagePreferences: Codable, Equatable, Sendable {
    var menuBarMetricID: String?
    var notificationsEnabled: Bool
    var alertRules: [MetricAlertRule]

    static let defaultValue = Self(
        menuBarMetricID: nil,
        notificationsEnabled: true,
        alertRules: []
    )
}
```

`MetricAlertRule.id` 使用稳定字符串，不包含显示标签：

```swift
static func ruleID(metricID: String, valueSource: MetricAlertValueSource) -> String {
    "\(metricID):\(valueSource.rawValue)"
}
```

`MetricAlertRule` 还必须包含：

```swift
var currencyCode: String?
```

该字段只用于 `.absoluteValue` 规则，记录用户确认阈值时的币种；百分比和状态规则保持 `nil`。

同时提供测试和 UI 共用的明确构造器：

```swift
extension MetricAlertRule {
    static func usedPercent(
        metricID: String,
        isEnabled: Bool,
        low: Decimal,
        high: Decimal
    ) -> Self

    static func remainingPercent(
        metricID: String,
        isEnabled: Bool,
        low: Decimal,
        high: Decimal
    ) -> Self

    static func absoluteValue(
        metricID: String,
        isEnabled: Bool,
        threshold: Decimal,
        currencyCode: String
    ) -> Self

    static func unhealthyState(metricID: String, isEnabled: Bool) -> Self
}
```

- [ ] **Step 4: 在 AppSettings 中增加版本化存储**

```swift
private static let credentialUsagePreferencesKey = "credentialUsagePreferences.v1"

func usagePreferences(for id: UUID) -> CredentialUsagePreferences {
    credentialUsagePreferences[id.uuidString] ?? .defaultValue
}

func storedUsagePreferences(for id: UUID) -> CredentialUsagePreferences? {
    credentialUsagePreferences[id.uuidString]
}

func setUsagePreferences(_ preferences: CredentialUsagePreferences, for id: UUID) {
    credentialUsagePreferences[id.uuidString] = preferences
    persistCredentialUsagePreferences()
}

func removeUsagePreferences(for id: UUID) {
    credentialUsagePreferences.removeValue(forKey: id.uuidString)
    persistCredentialUsagePreferences()
}
```

损坏数据回退为空字典，不影响其他 AppSettings 字段。

- [ ] **Step 5: 删除凭证时同步清理偏好**

在 `CredentialManagementModel` 已有成功删除和缓存清理失败但凭证已删除的两个分支中，都调用：

```swift
settings.removeUsagePreferences(for: id)
```

扩展现有删除测试，断言凭证偏好同步消失。

- [ ] **Step 6: 运行测试并提交**

Run: 与 Step 2 相同。

Expected: PASS。

```bash
git add RoutinUsage/Models RoutinUsage/Views/Settings/CredentialManagementModel.swift \
  RoutinUsageTests/AppSettingsTests.swift RoutinUsageTests/CredentialManagementViewTests.swift
git commit -m "feat: 持久化每凭证用量偏好"
```

### Task 4: 解析每凭证的单一菜单栏指标

**Files:**
- Create: `RoutinUsage/Usage/MenuBarMetricResolver.swift`
- Modify: `RoutinUsage/Views/MenuBarLabelView.swift`
- Modify: `RoutinUsage/App/StatusBarController.swift`
- Modify: `RoutinUsage/Views/Settings/Components/MenuBarIndicatorPreview.swift`
- Test: `RoutinUsageTests/MenuBarSelectionTests.swift`
- Test: `RoutinUsageTests/StatusBarVisibilityTests.swift`
- Test: `RoutinUsageTests/StatusBarIconRenderTests.swift`

**Interfaces:**
- Consumes: `CredentialUsagePreferences.menuBarMetricID`、快照指标、供应商能力。
- Produces: `MenuBarMetricResolver.options`、`resolve`、接收单个 `NormalizedUsageMetric?` 的 `MenuBarIndicatorModel.make`。

- [ ] **Step 1: 写入自动选择、手动选择和失效回退测试**

```swift
private func menuMetric(id: String, label: String) -> NormalizedUsageMetric {
    NormalizedUsageMetric(
        id: id,
        label: label,
        used: 40,
        limit: 100,
        remaining: 60,
        unit: .token,
        presentation: .progress,
        semantic: .usedQuota
    )
}

private func menuCapability(
    id: String,
    label: String,
    priority: Int
) -> UsageMetricCapability {
    UsageMetricCapability(
        metricID: id,
        label: label,
        presentation: .progress,
        semantic: .usedQuota,
        isMenuBarSelectable: true,
        menuBarPriority: priority,
        defaultAlertEnabled: true,
        defaultAbsoluteAlertThreshold: nil
    )
}

func test自动菜单栏指标优先使用供应商首选进度指标() {
    let weeklyMetric = menuMetric(id: "weekly", label: "周")
    let fiveHourMetric = menuMetric(id: "fiveHour", label: "5 小时")
    let resolution = MenuBarMetricResolver.resolve(
        selectedMetricID: nil,
        metrics: [weeklyMetric, fiveHourMetric],
        capabilities: [
            menuCapability(id: "fiveHour", label: "5 小时", priority: 0),
            menuCapability(id: "weekly", label: "周", priority: 1)
        ]
    )

    XCTAssertEqual(resolution.metric?.id, "fiveHour")
    XCTAssertFalse(resolution.isFallback)
}

func test手动指标失效时回退自动但保留原选择() {
    let weeklyMetric = menuMetric(id: "weekly", label: "周")
    let resolution = MenuBarMetricResolver.resolve(
        selectedMetricID: "monthly",
        metrics: [weeklyMetric],
        capabilities: [menuCapability(id: "weekly", label: "周", priority: 0)]
    )

    XCTAssertEqual(resolution.metric?.id, "weekly")
    XCTAssertTrue(resolution.isFallback)
    XCTAssertEqual(resolution.selectedMetricID, "monthly")
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/MenuBarSelectionTests \
  -only-testing:RoutinUsageTests/StatusBarVisibilityTests \
  -only-testing:RoutinUsageTests/StatusBarIconRenderTests
```

Expected: FAIL，提示 `MenuBarMetricResolver` 不存在或菜单栏仍接收全局维度。

- [ ] **Step 3: 实现解析器**

```swift
struct MenuBarMetricResolution: Equatable, Sendable {
    let selectedMetricID: String?
    let metric: NormalizedUsageMetric?
    let isFallback: Bool
}

enum MenuBarMetricResolver {
    static func options(
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability]
    ) -> [UsageMetricCapability]

    static func resolve(
        selectedMetricID: String?,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability]
    ) -> MenuBarMetricResolution
}
```

`options` 先按 `metricID` 合并运行时指标和供应商能力。运行时存在但能力表未声明的 `progress`、`balance`、`status` 指标，根据自身 `presentation` 和 `semantic` 合成临时能力；过滤 `isMenuBarSelectable == false` 和 `.value`。自动选择按 `menuBarPriority`、进度、余额、状态顺序执行。

- [ ] **Step 4: 重构菜单栏模型和真实 StatusItem**

将 `MenuBarIndicatorModel.make` 改为：

```swift
static func make(
    state: KeyUsageState,
    descriptor: ProviderDescriptor,
    metric: NormalizedUsageMetric?
) -> Self
```

只使用传入指标生成百分比、余额或状态，不再在内部选择 `metrics.first`，也不读取 `DisplayDimension`。

`StatusBarController.updateStatusButton()` 对每个凭证执行：

```swift
let preferences = environment.settings.usagePreferences(for: id)
let capabilities = environment.providerRegistry.metricCapabilities(for: state.configuration)
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
```

如果 `providerRegistry` 当前不是 `AppEnvironment` 可访问属性，本任务增加只读访问器，不复制注册表。

- [ ] **Step 5: 更新预览组件并验证测试**

`MenuBarIndicatorPreview` 接收 `metric`，其 `Equatable` 比较包含指标：

```swift
let metric: NormalizedUsageMetric?
```

Run: 与 Step 2 相同。

Expected: PASS；两个凭证可在同一菜单栏使用不同指标。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Usage/MenuBarMetricResolver.swift RoutinUsage/Views/MenuBarLabelView.swift \
  RoutinUsage/App RoutinUsage/Views/Settings/Components/MenuBarIndicatorPreview.swift \
  RoutinUsageTests/MenuBarSelectionTests.swift RoutinUsageTests/StatusBarVisibilityTests.swift \
  RoutinUsageTests/StatusBarIconRenderTests.swift
git commit -m "feat: 按凭证解析菜单栏指标"
```

### Task 5: 在菜单栏管理中配置单一指标并移除全局维度

**Files:**
- Modify: `RoutinUsage/Views/Settings/MenuBarManagementView.swift`
- Modify: `RoutinUsage/Views/Settings/GeneralSettingsView.swift`
- Modify: `RoutinUsage/Models/AppSettings.swift`
- Modify: `RoutinUsage/App/StatusBarController.swift`
- Test: `RoutinUsageTests/MenuBarManagementViewTests.swift`
- Test: `RoutinUsageTests/GeneralSettingsViewTests.swift`
- Test: `RoutinUsageTests/AppSettingsTests.swift`
- Test: `RoutinUsageTests/ProjectBootstrapTests.swift`

**Interfaces:**
- Consumes: Task 3 的凭证偏好 API、Task 4 的菜单栏选项和解析结果。
- Produces: 每张凭证卡片的“菜单栏指标”菜单、通用设置精简后的界面。

- [ ] **Step 1: 写入页面职责失败测试**

`GeneralSettingsViewTests` 改为：

```swift
func test通用页只保留刷新启动和通知总开关() throws {
    let source = try TestSourceReader.read([
        "RoutinUsage", "Views", "Settings", "GeneralSettingsView.swift"
    ])

    XCTAssertTrue(source.contains("刷新"))
    XCTAssertTrue(source.contains("登录时启动"))
    XCTAssertTrue(source.contains("notificationsEnabled"))
    XCTAssertFalse(source.contains("displayDimension"))
    XCTAssertFalse(source.contains("thresholds"))
}
```

`MenuBarManagementViewTests` 增加 `Menu("菜单栏指标")`、`MenuBarMetricResolver.options` 和 `setUsagePreferences` 断言。

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/MenuBarManagementViewTests \
  -only-testing:RoutinUsageTests/GeneralSettingsViewTests \
  -only-testing:RoutinUsageTests/AppSettingsTests \
  -only-testing:RoutinUsageTests/ProjectBootstrapTests
```

Expected: FAIL，通用页仍有全局维度和阈值，菜单栏卡片没有指标菜单。

- [ ] **Step 3: 在每张凭证卡片增加指标菜单**

卡片中增加紧凑菜单：

```swift
Menu {
    Button("自动") {
        setMenuBarMetric(nil, for: id)
    }
    ForEach(metricOptions(for: state)) { option in
        Button(option.label) {
            setMenuBarMetric(option.metricID, for: id)
        }
    }
} label: {
    Label(selectedMetricTitle(for: state), systemImage: "gauge.with.dots.needle.33percent")
        .lineLimit(1)
}
.menuStyle(.borderlessButton)
.help("设置 \(state.configuration.displayName) 的菜单栏指标")
```

`setMenuBarMetric` 只修改目标凭证偏好：

```swift
private func setMenuBarMetric(_ metricID: String?, for id: UUID) {
    var preferences = environment.settings.usagePreferences(for: id)
    preferences.menuBarMetricID = metricID
    environment.settings.setUsagePreferences(preferences, for: id)
}
```

- [ ] **Step 4: 让设置预览使用同一解析结果**

管理卡片和合并预览调用 Task 4 的解析器，删除所有 `environment.settings.displayDimension` 参数。失效手动选项显示“自动（原指标当前不可用）”，但不覆盖持久化值。

- [ ] **Step 5: 精简通用设置并保留迁移键**

从 `GeneralSettingsView` 删除维度 Picker 和全局阈值 Stepper。`AppSettings` 暂时保留旧字段的只读兼容加载，供 Task 6 迁移使用，但不再从 UI 修改。

`StatusBarController` 停止观察 `displayDimension` 和全局 `thresholds`；通知总开关仍然观察。

- [ ] **Step 6: 运行测试并提交**

Run: 与 Step 2 相同。

Expected: PASS；菜单栏预览与真实菜单栏使用同一凭证指标。

```bash
git add RoutinUsage/Views/Settings/MenuBarManagementView.swift \
  RoutinUsage/Views/Settings/GeneralSettingsView.swift RoutinUsage/Models/AppSettings.swift \
  RoutinUsage/App/StatusBarController.swift RoutinUsageTests
git commit -m "feat: 在菜单栏管理中按凭证选择指标"
```

### Task 6: 生成和迁移每指标默认提醒规则

**Files:**
- Create: `RoutinUsage/Notifications/MetricAlertRuleResolver.swift`
- Modify: `RoutinUsage/Models/CredentialUsagePreferences.swift`
- Modify: `RoutinUsage/Models/AppSettings.swift`
- Test: `RoutinUsageTests/MetricAlertRuleResolverTests.swift`
- Test: `RoutinUsageTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: 指标显式语义、供应商能力、旧 `AlertThresholds`、已有凭证规则。
- Produces: `MetricAlertRuleResolver.reconcile`，返回保留用户状态并补齐新指标的偏好。

- [ ] **Step 1: 写入默认规则和用户关闭状态测试**

```swift
private func alertMetric(
    id: String,
    semantic: NormalizedUsageMetricSemantic
) -> NormalizedUsageMetric {
    NormalizedUsageMetric(
        id: id,
        label: id,
        used: semantic == .usedQuota ? 40 : nil,
        limit: 100,
        remaining: semantic == .remainingQuota ? 60 : nil,
        unit: .token,
        presentation: .progress,
        semantic: semantic
    )
}

private func alertCapability(
    id: String,
    semantic: NormalizedUsageMetricSemantic
) -> UsageMetricCapability {
    UsageMetricCapability(
        metricID: id,
        label: id,
        presentation: .progress,
        semantic: semantic,
        isMenuBarSelectable: true,
        menuBarPriority: 0,
        defaultAlertEnabled: true,
        defaultAbsoluteAlertThreshold: nil
    )
}

func test已用和剩余指标生成方向正确的默认规则() {
    let usedMetric = alertMetric(id: "used", semantic: .usedQuota)
    let remainingMetric = alertMetric(id: "remaining", semantic: .remainingQuota)
    let capabilities = [
        alertCapability(id: "used", semantic: .usedQuota),
        alertCapability(id: "remaining", semantic: .remainingQuota)
    ]
    let preferences = MetricAlertRuleResolver.reconcile(
        existing: .defaultValue,
        metrics: [usedMetric, remainingMetric],
        capabilities: capabilities,
        legacyThresholds: AlertThresholds(low: 80, high: 95)
    )

    let used = preferences.alertRules.first { $0.metricID == usedMetric.id }
    XCTAssertEqual(used?.comparator, .greaterThanOrEqual)
    XCTAssertEqual(used?.thresholds.compactMap(\.value), [Decimal(80), Decimal(95)])

    let remaining = preferences.alertRules.first { $0.metricID == remainingMetric.id }
    XCTAssertEqual(remaining?.comparator, .lessThanOrEqual)
    XCTAssertEqual(remaining?.thresholds.compactMap(\.value), [Decimal(20), Decimal(5)])
}

func test用户关闭的规则在指标消失后恢复时仍保持关闭() {
    let weeklyMetric = alertMetric(id: "weekly", semantic: .usedQuota)
    var existing = CredentialUsagePreferences.defaultValue
    existing.alertRules = [.usedPercent(metricID: "weekly", isEnabled: false, low: 70, high: 90)]

    let restored = MetricAlertRuleResolver.reconcile(
        existing: existing,
        metrics: [weeklyMetric],
        capabilities: [alertCapability(id: "weekly", semantic: .usedQuota)],
        legacyThresholds: .init()
    )

    XCTAssertFalse(restored.alertRules.first?.isEnabled ?? true)
}
```

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/MetricAlertRuleResolverTests \
  -only-testing:RoutinUsageTests/AppSettingsTests
```

Expected: FAIL，解析器不存在。

- [ ] **Step 3: 实现规则协调器**

```swift
enum MetricAlertRuleResolver {
    static func reconcile(
        existing: CredentialUsagePreferences,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability],
        legacyThresholds: AlertThresholds
    ) -> CredentialUsagePreferences
}
```

规则生成必须满足：

- `.usedQuota` -> 80/95，比较方向 `>=`。
- `.remainingQuota` -> 20/5，比较方向 `<=`。
- `.balance` -> 能力提供可靠金额阈值时生成金额规则，并把指标 `currencyCode` 写入规则；否则生成 `healthState` 规则。
- `.status` -> `becomesUnhealthy`。
- `.value` -> 不生成规则。
- 已存在同 ID 规则原样保留；不删除休眠规则。
- 新指标仅在 `defaultAlertEnabled == true` 时生成开启规则。

- [ ] **Step 4: 实现一次性旧设置迁移**

`AppSettings` 增加按凭证记录的迁移集合：

```text
credentialUsagePreferencesMigratedCredentialIDs.v1
```

增加明确迁移入口：

```swift
func migrateUsagePreferencesIfNeeded(
    for configuration: KeyConfiguration,
    metrics: [NormalizedUsageMetric],
    capabilities: [UsageMetricCapability]
)
```

对尚无已存偏好且不在迁移集合中的旧凭证，使用旧 `displayDimension` 设置初始 `menuBarMetricID`；只有能力或快照中存在对应 ID 时才迁移，否则保存自动。旧全局阈值传给 `reconcile`，完成后把该凭证 UUID 加入迁移集合。不能使用单个全局布尔标记，否则第一个凭证迁移后会跳过其余凭证。

应用启动时只遍历启动前已经存在的凭证执行旧设置迁移。升级后新建的凭证直接使用 `.defaultValue` 和标准 80% / 95% 规则，不继承旧全局自定义值。

- [ ] **Step 5: 验证测试并提交**

Run: 与 Step 2 相同。

Expected: PASS。

```bash
git add RoutinUsage/Notifications/MetricAlertRuleResolver.swift \
  RoutinUsage/Models/CredentialUsagePreferences.swift RoutinUsage/Models/AppSettings.swift \
  RoutinUsageTests/MetricAlertRuleResolverTests.swift RoutinUsageTests/AppSettingsTests.swift
git commit -m "feat: 生成每指标默认提醒规则"
```

### Task 7: 将提醒评估统一为规则驱动的标准化指标流程

**Files:**
- Modify: `RoutinUsage/Notifications/AlertManager.swift`
- Modify: `RoutinUsage/Usage/UsageStore.swift`
- Modify: `RoutinUsage/App/AppEnvironment.swift`
- Test: `RoutinUsageTests/AlertManagerTests.swift`
- Test: `RoutinUsageTests/GenericAlertTests.swift`
- Test: `RoutinUsageTests/UsageStoreTests.swift`
- Test: `RoutinUsageTests/AppLifecycleTests.swift`

**Interfaces:**
- Consumes: `CredentialUsagePreferences.notificationsEnabled` 和 `alertRules`。
- Produces: `AlertEvaluator.evaluate(key:snapshot:rules:)`、基于字符串指标 ID 的去重键。

- [ ] **Step 1: 写入规则方向、开关和去重测试**

```swift
private func ruleSnapshot(metrics: [NormalizedUsageMetric]) -> UsageSnapshot {
    UsageSnapshot(
        planName: "测试套餐",
        kind: .periodic,
        fiveHour: nil,
        weekly: nil,
        token: nil,
        allowedModels: [],
        fetchedAt: .now,
        providerID: .glm,
        metrics: metrics
    )
}

private func percentMetric(
    id: String,
    semantic: NormalizedUsageMetricSemantic,
    percent: Decimal
) -> NormalizedUsageMetric {
    NormalizedUsageMetric(
        id: id,
        label: id,
        used: semantic == .usedQuota ? percent : 100 - percent,
        limit: 100,
        remaining: semantic == .remainingQuota ? percent : 100 - percent,
        unit: .token,
        presentation: .progress,
        semantic: semantic,
        healthState: .normal
    )
}

func test剩余百分比低于阈值才触发() throws {
    let context = makeContext()
    defer { context.cleanUp() }
    let alerts = context.evaluator.evaluate(
        key: makeKey(),
        snapshot: ruleSnapshot(metrics: [
            percentMetric(id: "remaining", semantic: .remainingQuota, percent: 4)
        ]),
        rules: [.remainingPercent(metricID: "remaining", isEnabled: true, low: 20, high: 5)]
    )

    XCTAssertEqual(alerts.map(\.level), [.high])
    XCTAssertTrue(alerts.allSatisfy { $0.metricID == "remaining" })
}

func test规则关闭和凭证通知关闭都不发送() async throws {
    let context = makeContext()
    defer { context.cleanUp() }
    let sender = NotificationSenderSpy(authorizationGranted: true)
    let manager = AlertManager(evaluator: context.evaluator, sender: sender)
    let key = makeKey()
    let snapshot = ruleSnapshot(metrics: [
        percentMetric(id: "weekly", semantic: .usedQuota, percent: 90)
    ])
    let disabledRule = MetricAlertRule.usedPercent(
        metricID: "weekly", isEnabled: false, low: 80, high: 95
    )
    let enabledRule = MetricAlertRule.usedPercent(
        metricID: "weekly", isEnabled: true, low: 80, high: 95
    )

    let disabledRules = try await manager.evaluateAndNotify(
        key: key,
        snapshot: snapshot,
        preferences: .init(menuBarMetricID: nil, notificationsEnabled: true, alertRules: [disabledRule]),
        applicationNotificationsEnabled: true
    )
    let disabledCredential = try await manager.evaluateAndNotify(
        key: key,
        snapshot: snapshot,
        preferences: .init(menuBarMetricID: nil, notificationsEnabled: false, alertRules: [enabledRule]),
        applicationNotificationsEnabled: true
    )

    XCTAssertEqual(disabledRules, [])
    XCTAssertEqual(disabledCredential, [])
}

func test余额币种变化时金额规则暂停执行() {
    let context = makeContext()
    defer { context.cleanUp() }
    let rule = MetricAlertRule.absoluteValue(
        metricID: "balance",
        isEnabled: true,
        threshold: 10,
        currencyCode: "CNY"
    )
    let usdBalance = NormalizedUsageMetric(
        id: "balance",
        label: "余额",
        value: 5,
        unit: .currency,
        presentation: .balance,
        semantic: .balance,
        currencyCode: "USD",
        healthState: .warning
    )

    XCTAssertEqual(
        context.evaluator.evaluate(
            key: makeKey(),
            snapshot: ruleSnapshot(metrics: [usdBalance]),
            rules: [rule]
        ),
        []
    )
}
```

增加测试证明旧固定字段和 `normalizedMetrics` 同时存在时只发送一次。

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/AlertManagerTests \
  -only-testing:RoutinUsageTests/GenericAlertTests \
  -only-testing:RoutinUsageTests/UsageStoreTests \
  -only-testing:RoutinUsageTests/AppLifecycleTests
```

Expected: FAIL，评估器仍接收全局 `AlertThresholds`。

- [ ] **Step 3: 重构通知载荷和去重键**

`UsageAlert` 替换为以下业务字段；删除旧 `dimension: UsageDimension` 和余额专用分支字段：

```swift
struct UsageAlert: Equatable, Sendable {
    let keyID: UUID
    let keyName: String
    let providerName: String
    let metricID: String
    let metricLabel: String
    let valueSource: MetricAlertValueSource
    let level: AlertLevel
    let currentValue: Decimal?
    let percent: Double?
    let windowEnd: Date?
    let currencyCode: String?
    let reservationID: UUID
    let triggeredWindows: Set<AlertWindowKey>
    let replacedReservationOwners: [AlertWindowKey: UUID]
}
```

`AlertWindowKey` 改为：

```swift
struct AlertWindowKey: Codable, Hashable, Sendable {
    let keyID: UUID
    let metricID: String
    let ruleID: String
    let windowIdentifier: String
    let level: AlertLevel
}
```

旧去重数据解码失败时回退为空集合，不影响刷新。通知正文明确显示供应商、凭证别名、指标和当前值。

- [ ] **Step 4: 只按规则评估 normalizedMetrics**

替换入口：

```swift
func evaluate(
    key: KeyConfiguration,
    snapshot: UsageSnapshot,
    rules: [MetricAlertRule]
) -> [UsageAlert]
```

执行顺序：

1. 按 `metricID` 查找 `snapshot.normalizedMetrics`。
2. 跳过关闭、缺失、过期或不可计算规则。
3. 根据 `valueSource` 计算已用比例、剩余比例、绝对值或健康状态。
4. 根据比较方向判断阈值。
5. 使用新去重键预留、发送和提交。

`.absoluteValue` 规则执行前必须验证 `rule.currencyCode == metric.currencyCode`。不一致时暂停规则，不发送通知，也不修改用户阈值。

删除遍历 `snapshot.fiveHour`、`weekly`、`token` 后再次遍历 `snapshot.metrics` 的双路径。

- [ ] **Step 5: 接入 UsageStore 和 AlertManager**

`AlertManager.evaluateAndNotify` 改为：

```swift
func evaluateAndNotify(
    key: KeyConfiguration,
    snapshot: UsageSnapshot,
    preferences: CredentialUsagePreferences,
    applicationNotificationsEnabled: Bool,
    shouldDeliver: @escaping @Sendable () async -> Bool = { true }
) async throws -> [UsageAlert]
```

`UsageStore` 在合并刷新结果后读取目标凭证偏好和规则。`AppEnvironment.synchronizeStoreSettings()` 不再传递全局阈值，只同步刷新间隔和应用通知总开关。

为避免 `UsageStore` 直接持有整个 `AppSettings`，初始化器注入三个主线程闭包：

```swift
usagePreferencesForCredential: @escaping @MainActor (UUID) -> CredentialUsagePreferences
setUsagePreferencesForCredential: @escaping @MainActor (CredentialUsagePreferences, UUID) -> Void
metricCapabilitiesForCredential: @escaping @MainActor (KeyConfiguration) -> [UsageMetricCapability]
```

`AppEnvironment.live()` 使用同一个 `settings` 和 `providerRegistry` 提供闭包：

```swift
usagePreferencesForCredential: { settings.usagePreferences(for: $0) },
setUsagePreferencesForCredential: { settings.setUsagePreferences($0, for: $1) },
metricCapabilitiesForCredential: { providerRegistry.metricCapabilities(for: $0) }
```

刷新合并成功后先调用 `MetricAlertRuleResolver.reconcile` 补齐新指标规则并持久化，再创建 `NotificationWork`。新指标协调使用标准 `AlertThresholds()`；旧全局阈值只在 Task 6 的一次性迁移入口使用。

- [ ] **Step 6: 验证测试并提交**

Run: 与 Step 2 相同。

Expected: PASS；现有并发、取消、失败恢复和去重测试继续通过。

```bash
git add RoutinUsage/Notifications/AlertManager.swift RoutinUsage/Usage/UsageStore.swift \
  RoutinUsage/App/AppEnvironment.swift RoutinUsageTests/AlertManagerTests.swift \
  RoutinUsageTests/GenericAlertTests.swift RoutinUsageTests/UsageStoreTests.swift \
  RoutinUsageTests/AppLifecycleTests.swift
git commit -m "refactor: 按凭证指标规则评估提醒"
```

### Task 8: 在凭证管理中编辑独立提醒规则

**Files:**
- Create: `RoutinUsage/Views/Settings/CredentialAlertSettingsModel.swift`
- Create: `RoutinUsage/Views/Settings/CredentialAlertSettingsView.swift`
- Modify: `RoutinUsage/Views/Settings/CredentialManagementView.swift`
- Modify: `RoutinUsage/Views/Settings/CredentialManagementModel.swift`
- Modify: `project.yml`
- Test: `RoutinUsageTests/CredentialAlertSettingsViewTests.swift`
- Test: `RoutinUsageTests/CredentialManagementViewTests.swift`
- Test: `RoutinUsageTests/SettingsAccessibilityTests.swift`
- Test: `RoutinUsageTests/ProjectBootstrapTests.swift`

**Interfaces:**
- Consumes: 凭证偏好、当前快照指标、能力描述和规则协调器。
- Produces: `CredentialAlertSettingsModel`、凭证级提醒总开关、按指标编辑的规则弹窗。

- [ ] **Step 1: 写入提醒入口和动态规则列表失败测试**

```swift
func test凭证提醒设置默认开启并只展示可预警指标() {
    let credentialID = UUID()
    let usedMetric = NormalizedUsageMetric(
        id: "weekly",
        label: "周用量",
        used: 40,
        limit: 100,
        remaining: 60,
        unit: .token,
        presentation: .progress,
        semantic: .usedQuota
    )
    let valueMetric = NormalizedUsageMetric(
        id: "requests",
        label: "请求次数",
        value: 20,
        unit: .request,
        presentation: .value,
        semantic: .value
    )
    let capabilities = [
        UsageMetricCapability(
            metricID: "weekly",
            label: "周用量",
            presentation: .progress,
            semantic: .usedQuota,
            isMenuBarSelectable: true,
            menuBarPriority: 0,
            defaultAlertEnabled: true,
            defaultAbsoluteAlertThreshold: nil
        ),
        UsageMetricCapability(
            metricID: "requests",
            label: "请求次数",
            presentation: .value,
            semantic: .value,
            isMenuBarSelectable: false,
            menuBarPriority: nil,
            defaultAlertEnabled: false,
            defaultAbsoluteAlertThreshold: nil
        )
    ]
    let model = CredentialAlertSettingsModel(
        credentialID: credentialID,
        preferences: .defaultValue,
        metrics: [usedMetric, valueMetric],
        capabilities: capabilities
    )

    XCTAssertTrue(model.notificationsEnabled)
    XCTAssertEqual(model.rules.map(\.metricID), [usedMetric.id])
}
```

静态源码测试断言凭证卡片包含 `bell.badge` 按钮和“提醒设置”辅助功能标签。

- [ ] **Step 2: 运行测试并确认失败**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/CredentialAlertSettingsViewTests \
  -only-testing:RoutinUsageTests/CredentialManagementViewTests \
  -only-testing:RoutinUsageTests/SettingsAccessibilityTests \
  -only-testing:RoutinUsageTests/ProjectBootstrapTests
```

Expected: FAIL，新视图和入口不存在。

- [ ] **Step 3: 实现提醒设置模型和视图**

模型只暴露当前可编辑规则，并通过保存闭包持久化：

```swift
@MainActor
@Observable
final class CredentialAlertSettingsModel {
    let credentialID: UUID
    let metrics: [NormalizedUsageMetric]
    private let save: (CredentialUsagePreferences) -> Void
    var preferences: CredentialUsagePreferences {
        didSet { save(preferences) }
    }

    init(
        credentialID: UUID,
        preferences: CredentialUsagePreferences,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability],
        save: @escaping (CredentialUsagePreferences) -> Void = { _ in }
    ) {
        self.credentialID = credentialID
        self.metrics = metrics
        self.save = save
        self.preferences = MetricAlertRuleResolver.reconcile(
            existing: preferences,
            metrics: metrics,
            capabilities: capabilities,
            legacyThresholds: .init()
        )
    }

    var notificationsEnabled: Bool {
        get { preferences.notificationsEnabled }
        set { preferences.notificationsEnabled = newValue }
    }

    var rules: [MetricAlertRule] {
        preferences.alertRules.filter { rule in
            metrics.contains { $0.id == rule.metricID }
        }
    }

    func metric(for rule: MetricAlertRule) -> NormalizedUsageMetric? {
        metrics.first { $0.id == rule.metricID }
    }

    func updateRule(_ updatedRule: MetricAlertRule) {
        guard let index = preferences.alertRules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        preferences.alertRules[index] = updatedRule
    }
}
```

视图使用独立 sheet，不展开凭证主列表：

```swift
struct CredentialAlertSettingsView: View {
    let state: KeyUsageState
    @Bindable var model: CredentialAlertSettingsModel

    var body: some View {
        Form {
            Toggle("提醒此凭证", isOn: $model.notificationsEnabled)
            ForEach(model.rules) { rule in
                MetricAlertRuleEditor(
                    rule: Binding(
                        get: { rule },
                        set: { model.updateRule($0) }
                    ),
                    metric: model.metric(for: rule)
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
    }
}

private struct MetricAlertRuleEditor: View {
    @Binding var rule: MetricAlertRule
    let metric: NormalizedUsageMetric?

    var body: some View {
        Section(metric?.label ?? rule.metricID) {
            Toggle("启用提醒", isOn: $rule.isEnabled)
            MetricAlertThresholdControls(rule: $rule, metric: metric)
        }
    }
}

private struct MetricAlertThresholdControls: View {
    @Binding var rule: MetricAlertRule
    let metric: NormalizedUsageMetric?

    var body: some View {
        switch rule.valueSource {
        case .usedPercent, .remainingPercent:
            ForEach(rule.thresholds.indices, id: \.self) { index in
                Stepper(value: percentBinding(at: index), in: 1...100) {
                    Text("\(percentLabel) \(percentBinding(at: index).wrappedValue)%")
                }
            }
        case .absoluteValue:
            if !rule.thresholds.isEmpty {
                TextField(
                    "余额低于",
                    value: amountBinding,
                    format: .number
                )
                Text(metric?.currencyCode ?? "未提供币种")
                    .foregroundStyle(.secondary)
            }
        case .healthState:
            Text("账户状态变为异常时提醒")
                .foregroundStyle(.secondary)
        }
    }

    private var percentLabel: String {
        rule.valueSource == .remainingPercent ? "剩余低于" : "已用达到"
    }

    private func percentBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: {
                NSDecimalNumber(decimal: rule.thresholds[index].value ?? 0).intValue
            },
            set: { rule.thresholds[index].value = Decimal($0) }
        )
    }

    private var amountBinding: Binding<Decimal> {
        Binding(
            get: { rule.thresholds[0].value ?? 0 },
            set: { rule.thresholds[0].value = $0 }
        )
    }
}
```

规则编辑器文案必须根据语义显示“已用达到”“剩余低于”“余额低于”或“状态异常”，金额显示币种，状态规则不显示数值 Stepper。

- [ ] **Step 4: 在凭证卡片增加通知按钮**

```swift
Button {
    alertSettingsCredentialID = state.configuration.id
} label: {
    Image(systemName: preferences.notificationsEnabled ? "bell.badge" : "bell.slash")
}
.buttonStyle(.borderless)
.help("设置 \(state.configuration.displayName) 的用量提醒")
.accessibilityLabel("提醒设置")
```

sheet 打开前调用 `MetricAlertRuleResolver.reconcile`，确保新指标立即出现，但不覆盖用户关闭状态。

- [ ] **Step 5: 把新源码加入静态测试资源并验证**

在 `project.yml` 测试预构建脚本中复制 `CredentialAlertSettingsView.swift`，同时在 `ProjectBootstrapTests` 的资源映射中增加对应分支。

Run: 与 Step 2 相同。

Expected: PASS，VoiceOver 可访问所有开关和阈值控件。

- [ ] **Step 6: 提交**

```bash
git add RoutinUsage/Views/Settings/CredentialAlertSettingsModel.swift \
  RoutinUsage/Views/Settings/CredentialAlertSettingsView.swift \
  RoutinUsage/Views/Settings/CredentialManagementView.swift \
  RoutinUsage/Views/Settings/CredentialManagementModel.swift project.yml RoutinUsageTests
git commit -m "feat: 在凭证管理中配置独立提醒"
```

### Task 9: 完成兼容清理和端到端验证

**Files:**
- Modify: `RoutinUsage/Models/AppSettings.swift`
- Modify: `RoutinUsage/App/StatusBarController.swift`
- Modify: `RoutinUsage/Usage/UsageStore.swift`
- Modify: `RoutinUsageTests/AppSettingsTests.swift`
- Modify: `RoutinUsageTests/AppLifecycleTests.swift`
- Modify: `RoutinUsageTests/ProjectBootstrapTests.swift`

**Interfaces:**
- Consumes: 前八个任务的最终接口。
- Produces: 完整迁移链、无全局维度运行时依赖、通过全部测试和真实窗口验证的功能。

- [ ] **Step 1: 写入端到端迁移测试**

```swift
func test旧全局设置只迁移一次且之后不覆盖用户选择() throws {
    let context = try makeContext()
    defer { context.cleanUp() }
    context.defaults.set("weekly", forKey: "displayDimension")
    context.defaults.set(70, forKey: "notificationLowThreshold")
    context.defaults.set(90, forKey: "notificationHighThreshold")
    let configuration = KeyConfiguration(
        id: UUID(),
        name: "主账号",
        keySuffix: "",
        sortOrder: 0,
        providerID: .glm,
        credentialKind: .apiKey
    )
    let weeklyMetric = NormalizedUsageMetric(
        id: "weekly",
        label: "周用量",
        used: 30,
        limit: 100,
        remaining: 70,
        unit: .token,
        presentation: .progress,
        semantic: .usedQuota
    )
    let capabilities = [UsageMetricCapability(
        metricID: "weekly",
        label: "周用量",
        presentation: .progress,
        semantic: .usedQuota,
        isMenuBarSelectable: true,
        menuBarPriority: 0,
        defaultAlertEnabled: true,
        defaultAbsoluteAlertThreshold: nil
    )]

    let first = AppSettings(defaults: context.defaults)
    first.migrateUsagePreferencesIfNeeded(for: configuration, metrics: [weeklyMetric], capabilities: capabilities)
    var preferences = first.usagePreferences(for: configuration.id)
    preferences.menuBarMetricID = "fiveHour"
    first.setUsagePreferences(preferences, for: configuration.id)

    let second = AppSettings(defaults: context.defaults)
    second.migrateUsagePreferencesIfNeeded(for: configuration, metrics: [weeklyMetric], capabilities: capabilities)

    XCTAssertEqual(second.usagePreferences(for: configuration.id).menuBarMetricID, "fiveHour")
}
```

- [ ] **Step 2: 运行迁移和生命周期测试**

```bash
xcodegen generate
xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage \
  -only-testing:RoutinUsageTests/AppSettingsTests \
  -only-testing:RoutinUsageTests/AppLifecycleTests \
  -only-testing:RoutinUsageTests/ProjectBootstrapTests
```

Expected: PASS。

- [ ] **Step 3: 删除运行时全局依赖但保留兼容键**

使用 `rg` 验证：

```bash
rg -n 'settings\.displayDimension|settings\.thresholds|AlertThresholds' RoutinUsage
```

允许命中范围仅为旧设置解码、迁移器和兼容测试。菜单栏、设置 UI、`UsageStore`、`StatusBarController` 和 `AlertEvaluator` 不得继续读取全局维度或阈值。

- [ ] **Step 4: 执行完整自动化验证**

```bash
./scripts/test.sh
git diff --check
```

Expected: 全部测试通过，`git diff --check` 无输出。

- [ ] **Step 5: 执行真实 macOS 窗口验证**

```bash
./scripts/run-debug.sh
```

在真实设置窗口中验证：

1. 通用页面只剩刷新、登录启动和通知总开关。
2. 菜单栏管理中两个不同凭证可以选择不同指标，预览和真实菜单栏同步变化。
3. 单个凭证提醒默认开启，可独立关闭。
4. 已用、剩余、余额和状态规则显示正确文案和控件。
5. 将凭证移出菜单栏不影响该凭证提醒。
6. 套餐指标变化后旧规则休眠，新可预警指标默认开启。
7. 菜单栏管理拖拽排序继续流畅，指标菜单不会抢占拖拽手势。

- [ ] **Step 6: 提交兼容清理**

```bash
git add RoutinUsage RoutinUsageTests project.yml
git commit -m "test: 完成按凭证用量设置回归验证"
```

- [ ] **Step 7: 最终检查提交边界**

```bash
git status --short --branch
git log --oneline --decorate -12
git diff HEAD^ --check
```

Expected: 没有遗漏的功能文件；执行前已存在且不属于本计划的用户改动仍按原边界保留。
