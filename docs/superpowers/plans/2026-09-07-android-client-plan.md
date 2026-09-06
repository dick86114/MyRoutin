# MyToken Android Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不引入服务端的前提下，为 MyToken 增加 Android 10+ 原生客户端，完整展示当前 macOS 支持的供应商用量，并通过二维码 + 局域网临时加密连接迁移凭证配置。

**Architecture:** Android 使用 Kotlin + Jetpack Compose，按 core/domain/data/provider/feature 模块拆分；macOS 保持 SwiftUI/AppKit。两端通过版本化 Transfer Schema、供应商 ID、指标语义和 JSON fixtures 对齐，不共享 UI 源码。迁移由 macOS 开启一次性局域网服务，Android 扫描二维码后完成 X25519 + HKDF + AEAD 加密传输。

**Tech Stack:** Kotlin, Jetpack Compose, Material 3, Coroutines, Flow, ViewModel, Room, DataStore, Android Keystore, CameraX/ML Kit, WorkManager, Android Notifications；macOS 侧继续使用 Swift 5、SwiftUI/AppKit、XcodeGen。

## Global Constraints

- Android 最低支持 Android 10（API 29）。
- Android 首版覆盖 Routin、DeepSeek、GLM Coding Plan、火山方舟个人 Agent Plan 和 Coding Plan。
- Android 主界面以 macOS 菜单栏弹窗的内容组织和视觉层级为母版，做纵向、触控和滚动适配。
- 不增加服务端、账号系统或云端凭证同步；Android 直接调用官方接口。
- 二维码只携带一次性迁移会话信息，不携带明文 API Key、Access Key、Secret Access Key、Bearer Token、Cookie 或密码。
- 迁移会话默认 5 分钟过期、单客户端、成功或取消后立即失效。
- 敏感凭证必须使用平台安全存储；不得进入日志、剪贴板、诊断包或提交内容。
- macOS 工程由 `project.yml` 管理；修改工程结构时同步更新配置并运行 `xcodegen generate`。
- 新增行为必须增加测试；macOS 测试使用 `scripts/test.sh`，Android 测试使用 Gradle 单元测试和 Compose UI 测试。
- 使用 Conventional Commits；不要直接推送默认分支。

---

## 子计划边界

本计划包含四个可分别验收的子系统，实施顺序固定：

1. 跨平台协议与安全存储基础
2. Mac → Android 局域网加密迁移
3. Android 工程、供应商适配与首页
4. 凭证管理、设置、后台刷新、通知与签到

每个任务都必须在对应测试通过后提交一个独立 Conventional Commit。

## 文件地图

第一阶段计划创建或修改：

- Create: `shared/transfer-schema/transfer-schema-v1.json`
- Create: `shared/provider-contracts/provider-capabilities.json`
- Create: `shared/fixtures/credentials/*.json`
- Create: `RoutinUsage/Transfer/TransferModels.swift`
- Create: `RoutinUsage/Transfer/TransferSchemaCodec.swift`
- Create: `RoutinUsage/Transfer/TransferSession.swift`
- Modify: `RoutinUsage/Security/LocalKeyStore.swift`
- Create: `RoutinUsage/Security/SecureCredentialStore.swift`
- Create: `RoutinUsageTests/TransferSchemaTests.swift`
- Create: `RoutinUsageTests/SecureCredentialStoreTests.swift`

第二阶段计划创建或修改：

- Create: `RoutinUsage/Transfer/TransferServer.swift`
- Create: `RoutinUsage/Transfer/TransferQRCodePayload.swift`
- Create: `RoutinUsage/Views/Settings/TransferToAndroidView.swift`
- Create: `RoutinUsageTests/TransferSessionTests.swift`
- Create: `RoutinUsageTests/TransferServerTests.swift`
- Create: `android/settings.gradle.kts`
- Create: `android/build.gradle.kts`
- Create: `android/gradle.properties`
- Create: `android/app/build.gradle.kts`
- Create: `android/app/src/main/AndroidManifest.xml`
- Create: `android/core/...`
- Create: `android/data/...`
- Create: `android/domain/...`
- Create: `android/feature-transfer/...`

第三、四阶段计划创建：

- Create: `android/provider/...`
- Create: `android/feature-home/...`
- Create: `android/feature-credentials/...`
- Create: `android/feature-settings/...`
- Create: `android/app/src/test/...`
- Create: `android/app/src/androidTest/...`
- Modify: `README.md`
- Modify: `docs/android/...`

## Task 1: 定义跨平台协议和能力清单

**Files:**
- Create: `shared/transfer-schema/transfer-schema-v1.json`
- Create: `shared/provider-contracts/provider-capabilities.json`
- Create: `shared/fixtures/credentials/routin-bearer.json`
- Create: `shared/fixtures/credentials/deepseek-bearer.json`
- Create: `shared/fixtures/credentials/glm-bearer.json`
- Create: `shared/fixtures/credentials/volcengine-access-key.json`
- Create: `shared/fixtures/usage/*.json`
- Test: `RoutinUsageTests/TransferSchemaTests.swift`

**Interfaces:**
- Produces schema version `1`, stable provider IDs, `CredentialKind`, metadata allowlist, migration settings and encrypted secret envelope shape.
- Produces provider capability fields for 5-hour usage, weekly usage, balance, remaining quota and reset time.

- [ ] **Step 1: Write fixture-driven failing tests**

测试必须读取 bundle 中的 schema fixtures，验证每个 fixture 可解析，并拒绝缺少 `schemaVersion`、`providerId`、`credentialKind` 或 UUID 的凭证。

- [ ] **Step 2: 运行 `scripts/test.sh` 验证测试失败**

Expected: `TransferSchemaTests` 因缺少 schema codec 或 fixture 解析失败。

- [ ] **Step 3: 编写 schema 和能力清单**

schema 必须定义 `schemaVersion: 1`、`credentials`、`preferences`、`secretEnvelope` 和 `exportedAt`；敏感值只允许出现在加密包模型，不允许出现在二维码 payload 模型。

- [ ] **Step 4: 实现 Swift Codable 类型和 codec**

在 `TransferModels.swift` 中定义 `TransferPackageV1`、`TransferCredential`、`TransferPreferences`、`EncryptedSecretEnvelope`；在 `TransferSchemaCodec.swift` 中提供：

```swift
func encode(_ package: TransferPackageV1) throws -> Data
func decode(_ data: Data) throws -> TransferPackageV1
```

- [ ] **Step 5: 运行测试并提交**

Run: `scripts/test.sh`

Expected: schema、fixture 和 codec 测试 PASS。

Commit: `feat: define cross-platform transfer schema`

## Task 2: 统一 macOS 安全凭证存储接口

**Files:**
- Create: `RoutinUsage/Security/SecureCredentialStore.swift`
- Modify: `RoutinUsage/Security/LocalKeyStore.swift`
- Create: `RoutinUsageTests/SecureCredentialStoreTests.swift`

**Interfaces:**

```swift
protocol SecureCredentialStoring: Sendable {
    func save(_ secret: String, for id: UUID) throws
    func read(for id: UUID) throws -> String?
    func delete(for id: UUID) throws
}
```

- [ ] **Step 1: 增加存储契约测试**

测试 save/read/delete、读取不存在的 ID、覆盖已有密钥，并验证测试日志不输出 secret。

- [ ] **Step 2: 运行 `scripts/test.sh` 验证失败**

Expected: `SecureCredentialStoring` 尚未存在或现有实现未满足接口。

- [ ] **Step 3: 抽取明确命名的安全存储适配器**

将生产代码中依赖秘密存储的路径改为 `SecureCredentialStoring`；保留现有迁移兼容逻辑，但明确区分 metadata store 与 secure store。不得在本任务中改变现有用户数据格式或删除旧数据。

- [ ] **Step 4: 运行测试并提交**

Run: `scripts/test.sh`

Commit: `refactor: clarify macOS secure credential storage`

## Task 3: 实现 macOS 临时迁移会话和二维码 payload

**Files:**
- Create: `RoutinUsage/Transfer/TransferSession.swift`
- Create: `RoutinUsage/Transfer/TransferQRCodePayload.swift`
- Create: `RoutinUsage/Transfer/TransferServer.swift`
- Create: `RoutinUsageTests/TransferSessionTests.swift`
- Create: `RoutinUsageTests/TransferServerTests.swift`

**Interfaces:**

```swift
struct TransferQRCodePayload: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let host: String
    let port: Int
    let macEphemeralPublicKey: Data
    let expiresAt: Date
    let connectionCode: String
}

protocol TransferServing: Sendable {
    func start() async throws -> TransferQRCodePayload
    func stop() async
}
```

- [ ] **Step 1: 写会话状态测试**

覆盖创建、有效期、单客户端、完成后失效、取消后失效、过期拒绝、错误连接码和错误 session ID。

- [ ] **Step 2: 运行测试验证失败**

Expected: 缺少会话状态机和临时服务。

- [ ] **Step 3: 实现临时会话状态机**

会话状态必须至少包括 `created`、`waitingForAndroid`、`connected`、`sent`、`completed`、`cancelled`、`expired`；通过系统安全随机源生成 session ID、连接码和临时 X25519 密钥对；所有终止状态销毁临时密钥。

- [ ] **Step 4: 实现局域网服务**

监听临时端口，只允许单个客户端；连接后校验 session ID、连接码和二维码中对应的 Mac 公钥；服务默认设置 5 分钟超时，停止时关闭 listener 和所有 pending connection。

- [ ] **Step 5: 运行测试并提交**

Run: `scripts/test.sh`

Commit: `feat: add macOS transfer session service`

## Task 4: 完成迁移加密协议和 Mac UI

**Files:**
- Modify: `RoutinUsage/Transfer/TransferServer.swift`
- Modify: `RoutinUsage/Transfer/TransferSession.swift`
- Create: `RoutinUsage/Views/Settings/TransferToAndroidView.swift`
- Modify: `RoutinUsage/Views/Settings/CredentialManagementView.swift`
- Create: `RoutinUsageTests/TransferCryptoTests.swift`

**Interfaces:**

```swift
struct TransferHandshake: Codable, Sendable {
    let sessionID: UUID
    let androidEphemeralPublicKey: Data
}

struct TransferEncryptedMessage: Codable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let nonce: Data
    let ciphertext: Data
    let authenticationTag: Data
}
```

- [ ] **Step 1: 写加密测试**

测试双方使用 X25519 + HKDF-SHA256 得到相同会话密钥；AES-GCM 密文可解密；修改 session ID、nonce、密文或 authentication tag 必须失败；旧会话和重复发送必须失败。

- [ ] **Step 2: 运行测试验证失败**

Expected: 加密 envelope 和 handshake 尚未实现。

- [ ] **Step 3: 实现握手和加密发送**

Android 公钥发送后，Mac 校验 session 数据并派生会话密钥；配置包序列化后使用 AEAD 加密；AAD 至少包含协议版本和 session ID；发送后将会话置为 `sent`，不得再次发送。

- [ ] **Step 4: 实现 Mac 迁移页面**

在凭证设置中增加“迁移到 Android”入口，显示二维码、过期倒计时、连接状态、供应商/凭证数量、取消按钮和异常提示。页面关闭时立即停止服务并销毁会话。

- [ ] **Step 5: 运行 macOS 测试并提交**

Run: `scripts/test.sh`

Commit: `feat: encrypt macOS to Android transfer`

## Task 5: 创建 Android 原生工程和数据层

**Files:**
- Create: `android/settings.gradle.kts`
- Create: `android/build.gradle.kts`
- Create: `android/gradle.properties`
- Create: `android/app/build.gradle.kts`
- Create: `android/app/src/main/AndroidManifest.xml`
- Create: `android/core/src/main/kotlin/...`
- Create: `android/domain/src/main/kotlin/...`
- Create: `android/data/src/main/kotlin/...`
- Create: `android/app/src/test/...`

**Interfaces:**

```kotlin
interface CredentialRepository {
    fun observeCredentials(): Flow<List<Credential>>
    suspend fun save(credential: Credential, secret: CredentialSecret)
    suspend fun delete(id: UUID)
    suspend fun readSecret(id: UUID): CredentialSecret?
}
```

- [ ] **Step 1: 创建 Android 10 工程和最小失败测试**

配置 `minSdk = 29`，创建能启动的 Compose Activity，并增加一个 repository contract test。

- [ ] **Step 2: 运行 `./gradlew test` 验证测试失败**

Expected: repository 实现和加密存储尚未存在。

- [ ] **Step 3: 实现 Room、DataStore 和 Keystore**

普通 metadata 使用 Room，设置使用 DataStore，secret 使用 Android Keystore 保护的加密密文；定义 `Credential`、`CredentialSecret` sealed hierarchy、`UsageSnapshot`、`UsageMetric` 和 `AppError`。

- [ ] **Step 4: 实现 repository**

保存 metadata 和 secret 必须有事务边界；secret 写入失败时不得留下 metadata；删除凭证同时删除 secret 和快照缓存。

- [ ] **Step 5: 运行测试并提交**

Run: `./gradlew test`

Commit: `feat: scaffold Android secure data layer`

## Task 6: 实现 Android 扫码、握手和导入预览

**Files:**
- Create: `android/feature-transfer/src/main/kotlin/.../TransferViewModel.kt`
- Create: `android/feature-transfer/src/main/kotlin/.../TransferRepository.kt`
- Create: `android/feature-transfer/src/main/kotlin/.../TransferScannerScreen.kt`
- Create: `android/feature-transfer/src/main/kotlin/.../TransferPreviewScreen.kt`
- Create: `android/core/src/main/kotlin/.../CryptoSession.kt`
- Create: `android/app/src/androidTest/.../TransferFlowTest.kt`

**Interfaces:**

```kotlin
interface TransferRepository {
    suspend fun connect(payload: TransferQRCodePayload): Result<EncryptedTransferPackage>
    suspend fun decrypt(packageData: EncryptedTransferPackage): Result<TransferPackageV1>
    suspend fun import(packageData: TransferPackageV1): Result<ImportSummary>
}
```

- [ ] **Step 1: 写迁移状态和 UI 测试**

覆盖扫码成功、扫码内容非法、局域网不可达、会话过期、密文篡改、导入预览、用户取消和完整导入。

- [ ] **Step 2: 运行 `./gradlew connectedAndroidTest` 验证失败**

Expected: transfer screens and repository are missing.

- [ ] **Step 3: 实现 URI/payload 解析和扫码**

解析 `mytoken-transfer://v1`，验证协议版本、UUID、地址、端口、公钥格式、过期时间和连接码；扫码结果不得写入日志。

- [ ] **Step 4: 实现局域网握手和解密**

生成 Android 临时 X25519 密钥，发送 handshake，校验 Mac 公钥和 session ID，使用相同 HKDF 参数派生密钥，验证 AEAD 后再反序列化配置包。

- [ ] **Step 5: 实现导入预览和事务导入**

显示供应商数量、凭证数量和敏感项数量；用户确认前不写入；确认后 metadata 与 secret 原子导入，冲突支持覆盖、跳过或副本；失败时回滚。

- [ ] **Step 6: 运行测试并提交**

Run: `./gradlew test connectedAndroidTest`

Commit: `feat: import credentials from macOS transfer session`

## Task 7: 接入供应商适配器和统一用量领域层

**Files:**
- Create: `android/provider/src/main/kotlin/.../UsageProvider.kt`
- Create: `android/provider/src/main/kotlin/.../routin/RoutinUsageProvider.kt`
- Create: `android/provider/src/main/kotlin/.../deepseek/DeepSeekUsageProvider.kt`
- Create: `android/provider/src/main/kotlin/.../glm/GLMUsageProvider.kt`
- Create: `android/provider/src/main/kotlin/.../volcengine/VolcengineUsageProvider.kt`
- Create: `android/provider/src/test/.../*ProviderTest.kt`
- Create: `android/domain/src/main/kotlin/.../RefreshCredentialsUseCase.kt`

**Interfaces:**

```kotlin
interface UsageProvider {
    val providerId: ProviderId
    suspend fun fetchUsage(credential: Credential): Result<UsageSnapshot>
}
```

- [ ] **Step 1: 从 shared fixtures 编写每个供应商失败测试**

每个供应商覆盖成功响应、认证失败、限流、服务端错误、空数据、指标映射和供应商特有字段；火山方舟增加签名测试。

- [ ] **Step 2: 运行 `./gradlew test` 验证失败**

Expected: provider adapters and fixtures are not implemented.

- [ ] **Step 3: 实现 HTTP client 和 provider adapters**

为每个供应商独立实现请求、解析和错误分类；不得将 secret 写入异常文本；复用统一 `UsageSnapshot` 和 `UsageMetric`。

- [ ] **Step 4: 实现刷新用例**

按凭证独立维护 Loading/Ready/Failed/Disabled；限制并发；失败时保留最后成功快照并标记过期；不支持的指标不生成伪造值。

- [ ] **Step 5: 运行测试并提交**

Run: `./gradlew test`

Commit: `feat: add Android provider usage adapters`

## Task 8: 实现首页和 macOS 弹窗风格移动适配

**Files:**
- Create: `android/feature-home/src/main/kotlin/.../HomeScreen.kt`
- Create: `android/feature-home/src/main/kotlin/.../HomeViewModel.kt`
- Create: `android/feature-home/src/main/kotlin/.../ProviderGroupSection.kt`
- Create: `android/feature-home/src/main/kotlin/.../CredentialUsageCard.kt`
- Create: `android/feature-home/src/main/kotlin/.../UsageMetricGrid.kt`
- Create: `android/feature-home/src/main/kotlin/.../CredentialDetailScreen.kt`
- Create: `android/feature-home/src/androidTest/.../HomeScreenTest.kt`

- [ ] **Step 1: 写 Compose UI 测试**

覆盖多供应商分组、用量型卡片、余额型卡片、缺失指标隐藏、错误保留旧数据、深色模式、大字体和展开详情。

- [ ] **Step 2: 运行 `./gradlew connectedAndroidTest` 验证失败**

Expected: screens and semantics are not implemented.

- [ ] **Step 3: 实现首页状态流和卡片**

首页纵向滚动；顶部显示刷新状态和更新时间；卡片保留 macOS 弹窗的供应商分组、状态颜色、指标层级和进度表达；用 2/3 列指标网格取代 Mac 的横向紧凑行；异常使用文字标签，不只依赖颜色。

- [ ] **Step 4: 实现详情页**

展示所有供应商支持的指标、最后更新时间、错误原因、单凭证刷新、编辑和删除入口；使用分段控件只展示实际支持的维度。

- [ ] **Step 5: 运行测试并提交**

Run: `./gradlew test connectedAndroidTest`

Commit: `feat: add Android usage dashboard`

## Task 9: 实现凭证管理、独立排序和设置

**Files:**
- Create: `android/feature-credentials/src/main/kotlin/.../CredentialListScreen.kt`
- Create: `android/feature-credentials/src/main/kotlin/.../CredentialEditorScreen.kt`
- Create: `android/feature-credentials/src/main/kotlin/.../CredentialViewModel.kt`
- Create: `android/feature-settings/src/main/kotlin/.../SettingsScreen.kt`
- Create: `android/feature-settings/src/main/kotlin/.../RefreshSettingsScreen.kt`
- Create: `android/feature-settings/src/main/kotlin/.../NotificationSettingsScreen.kt`
- Create: `android/feature-settings/src/main/kotlin/.../DisplaySettingsScreen.kt`
- Create: `android/app/src/androidTest/.../CredentialAndSettingsTest.kt`

- [ ] **Step 1: 写 UI 和排序测试**

覆盖新增、编辑、删除确认、密钥掩码、连接测试、启用/停用、长按排序、供应商分组排序、置顶、刷新频率和阈值设置。

- [ ] **Step 2: 运行测试验证失败**

Expected: credential and settings screens are absent.

- [ ] **Step 3: 实现凭证管理**

按 `CredentialKind` 动态显示 Bearer API Key 或 Access Key/Secret Access Key 字段；保存前校验格式；密钥默认掩码；删除同时清理安全存储和缓存；排序与 Mac 独立保存。

- [ ] **Step 4: 实现设置页**

提供自动刷新 1/5/15/30 分钟、仅 Wi-Fi、打开应用刷新、失败重试、卡片密度、指标显隐、默认展开、排序方式、置顶凭证和数据迁移入口。不要显示 macOS 菜单栏专属选项。

- [ ] **Step 5: 运行测试并提交**

Run: `./gradlew test connectedAndroidTest`

Commit: `feat: add Android credential management and settings`

## Task 10: 实现后台刷新、通知和 Routin 签到

**Files:**
- Create: `android/core/src/main/kotlin/.../RefreshWorker.kt`
- Create: `android/core/src/main/kotlin/.../NotificationChannels.kt`
- Create: `android/core/src/main/kotlin/.../MetricAlertEvaluator.kt`
- Create: `android/feature-credentials/src/main/kotlin/.../RoutinCheckInLauncher.kt`
- Create: `android/app/src/test/.../MetricAlertEvaluatorTest.kt`
- Create: `android/app/src/androidTest/.../NotificationAndCheckInTest.kt`

- [ ] **Step 1: 写 worker、阈值和通知测试**

覆盖后台刷新、网络不可用重试、低电量策略、50/80/自定义阈值、每个凭证覆盖全局设置、只提醒一次、凭证失效通知和三个通知频道。

- [ ] **Step 2: 运行测试验证失败**

Expected: worker, alert evaluator and notification channels are absent.

- [ ] **Step 3: 实现 WorkManager 刷新**

使用周期 WorkManager；接受系统调度偏差；记录最后成功和失败时间；网络约束下执行；避免常驻后台服务；前台和后台刷新共享 repository 但不重复请求。

- [ ] **Step 4: 实现阈值评估和通知**

将用量阈值、重置时间和凭证错误拆成独立通知频道；通知内容只包含别名、供应商和脱敏指标，不包含密钥或完整请求信息；处理 Android 13+ 通知权限，同时 Android 10 正常运行。

- [ ] **Step 5: 实现 Routin Custom Tabs 签到**

从 Routin 凭证详情启动官方 URL；不读取页面 DOM、密码、验证码或 Cookie；不将网页内容写入日志。

- [ ] **Step 6: 运行测试并提交**

Run: `./gradlew test connectedAndroidTest`

Commit: `feat: add Android refresh alerts and check-in`

## Task 11: 集成导航、发布配置、文档和验收

**Files:**
- Modify: `android/app/src/main/.../MainActivity.kt`
- Modify: `android/app/src/main/.../App.kt`
- Create: `android/app/src/main/res/values/strings.xml`
- Create: `android/app/src/main/res/xml/backup_rules.xml`
- Modify: `README.md`
- Create: `docs/android/README.md`
- Create: `docs/android/transfer-troubleshooting.md`
- Create: `.github/workflows/android-ci.yml`

- [ ] **Step 1: 集成三项底部导航**

接入首页、凭证、设置和详情/迁移子路由；应用首次打开显示空状态并提供“从 Mac 导入”和“手动添加”。

- [ ] **Step 2: 配置 Android 安全和备份策略**

明确 encrypted secret 不进入不可控云备份；检查 manifest 的网络、相机和通知权限；发布构建不得包含开发密钥、测试 URL 或完整日志开关。

- [ ] **Step 3: 增加 CI**

CI 执行 `./gradlew test`、静态检查和可用模拟器上的 Compose instrumentation tests；macOS CI 继续执行 `scripts/test.sh`。

- [ ] **Step 4: 更新项目文档**

记录 Android 构建、运行、迁移前置条件、局域网权限、失败排查、供应商配置字段和日志脱敏原则；明确 Android 10+ 要求。

- [ ] **Step 5: 执行完整验收**

Run: `scripts/test.sh`；Run: `cd android && ./gradlew test`；Run: `cd android && ./gradlew connectedAndroidTest`。

手工验收：至少一台 Android 10+ 真机和当前 macOS 客户端完成全供应商迁移、首次刷新、排序、通知、Routin 签到、断网重试、会话过期和重复导入。

- [ ] **Step 6: 提交发布准备变更**

Commit: `feat: integrate Android client build and documentation`

## 计划自检

- 规格中的供应商、首页布局、独立排序、迁移安全、Keystore、后台刷新、通知、签到、测试和验收要求均有对应任务。
- 占位符检查已完成，计划中的步骤均包含具体文件、接口、命令和验收结果。
- 任务间接口名称一致：`TransferQRCodePayload`、`TransferPackageV1`、`CredentialRepository`、`UsageProvider` 和 `TransferRepository` 在定义任务后复用。
- 迁移先于首页接入，但 Android 工程基础在迁移消费者之前建立；Mac 迁移服务先定义协议，再由 Android 实现客户端。
- 任何实施任务都不应把 API Key、Token、Cookie 或测试凭证写入源码、fixture、日志或提交。
