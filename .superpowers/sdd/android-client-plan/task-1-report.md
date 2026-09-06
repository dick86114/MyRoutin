# Task 1 Report

## Result

DONE. 已定义 MyToken Transfer Schema v1、跨平台供应商能力清单、脱敏凭证/用量 fixtures，并实现 Swift Codable 模型与 JSON codec。协议保留稳定 provider ID 与凭证 UUID；敏感材料只允许位于加密 secret envelope，二维码/凭证模型不会编码明文 secret。

## Changes made with file paths

- `shared/transfer-schema/transfer-schema-v1.json`
  - 定义 `schemaVersion: 1`、`credentials`、`preferences`、`secretEnvelope`、`exportedAt`。
  - 定义凭证 UUID、稳定 provider ID、三种 `credentialKind`、metadata allowlist、迁移偏好与 X25519/HKDF/AES-GCM 或 ChaCha20 envelope 结构。
- `shared/provider-contracts/provider-capabilities.json`
  - 为 routin、deepseek、glm、volcengine、newAPI 声明凭证类型及 5 小时、周、余额、剩余额度、重置时间能力。
- `shared/fixtures/credentials/routin-bearer.json`
- `shared/fixtures/credentials/deepseek-bearer.json`
- `shared/fixtures/credentials/glm-bearer.json`
- `shared/fixtures/credentials/volcengine-access-key.json`
  - 提供不含 API Key、Bearer Token、Access Key 或 Cookie 的脱敏凭证样例。
- `shared/fixtures/usage/routin-periodic.json`
- `shared/fixtures/usage/deepseek-balance.json`
- `shared/fixtures/usage/glm-usage.json`
- `shared/fixtures/usage/volcengine-usage.json`
  - 提供可解析的 v1 迁移包样例；无秘密内容。
- `RoutinUsage/Transfer/TransferModels.swift`
  - 新增 `TransferPackageV1`、`TransferCredential`、`TransferPreferences`、`EncryptedSecretEnvelope` 与协议错误类型。
  - 严格拒绝缺失/错误版本、无效 UUID、缺少 provider/kind、metadata 非白名单及凭证模型中的 secret；未知顶层字段按 Codable 默认规则忽略。
  - 自定义凭证编码，确保 `secret` 不会以 `null` 或明文形式输出。
- `RoutinUsage/Transfer/TransferSchemaCodec.swift`
  - 提供 ISO-8601 日期、稳定排序键的 `encode`/`decode`。
- `RoutinUsageTests/TransferSchemaTests.swift`
  - 覆盖凭证 fixtures、用量 fixtures、缺少必需字段、无效 UUID、未知字段、codec 往返及 secret envelope。
- `project.yml`
  - 将 shared credentials/usage fixtures 加入测试 Bundle 资源。

## Validation command and observed results

- `python3 -m json.tool`（全部 shared JSON）：通过，10 个 JSON 文件可解析。
- `git diff --check`：通过。
- `scripts/test.sh`：退出码 0；最终测试日志显示 `** TEST SUCCEEDED **`，TransferSchemaTests 6 项全部通过，测试套件无失败。

## Assumptions

- `credentialId` 使用字符串形式承载 UUID，以便 Swift 与 Android 独立实现之间保持 JSON 协议稳定。
- provider ID 使用现有 macOS 注册表中的五个稳定字符串（含既有 `newAPI`）；未知 provider 由后续导入层提示，不在本 codec 层伪造映射。
- 用量 fixtures 复用 v1 迁移包外形，作为首屏过渡/协议回归样例，不代表实时用量数据。
- 加密 envelope 的字段使用 Base64URL 字符串，由后续迁移会话负责实际加密与解密。

## Blockers/remaining risks

- 无当前阻塞。
- `scripts/test.sh` 运行时 macOS App 测试宿主偶尔会在断言结束后短暂存活；本次脚本最终正常收尾并返回 0。后续迁移任务仍需实现真实密钥交换、加密、二维码 payload 与安全存储，当前 Task 1 仅定义协议形状。

# Review Fix Report

## Result

DONE_WITH_CONCERNS. 已处理 review 的 7 项 findings：日期统一为 RFC3339 并通过 codec 解码；secretEnvelope 统一为必填对象（无秘密时使用显式空 envelope）；多凭证秘密按 credentialId 关联并使用 typed secret fields；补齐 provider/credential kind、偏好、加密 envelope、泄漏防护、资源一致性和未知字段兼容性测试。

## Changes made with file paths

- `RoutinUsage/Transfer/TransferModels.swift`
  - 移除 public credential model 的 nullable `secret`，不再存在明文秘密字段。
  - `TransferPackageV1.secretEnvelope` 改为必填 `EncryptedSecretEnvelope`，默认值为显式空 envelope。
  - 新增 `EncryptedSecretEntry`，每项以 UUID 关联 credential，并明确 bearerToken、apiKey、accessKeyID、secretAccessKey 字段。
  - 严格校验已知 provider/kind、metadata 白名单、刷新间隔/阈值/置顶 UUID、算法、密钥协商、Base64URL 字段、必填 entries 与重复关联。
- `shared/transfer-schema/transfer-schema-v1.json`
  - 与 Swift 保持 secretEnvelope 必填对象语义；新增多凭证 typed secret entries、算法/编码/偏好约束。
  - 顶层、credential、preferences、envelope 和 secret entry 允许未知字段，保持 forward compatibility；metadata 白名单仍严格限制。
- `shared/provider-contracts/provider-capabilities.json`
  - GLM resetTime、Volcengine fiveHour/weekly 按现有 macOS provider 能力修正。
  - 明确 Volcengine `agentPlan` 与 `codingPlan` 两个 variant；明确保留 macOS `newAPI` 但 `androidV1: false`，不扩大 Android v1 范围。
- `shared/fixtures/usage/*.json`
  - 四个用量 fixture 改用 `2023-11-14T22:13:20Z` RFC3339 日期和显式空 secret envelope。
  - Volcengine fixture 展示 coding variant，并以脱敏 Base64URL 占位值表达 accessKeyID/secretAccessKey 的 encrypted entry；无真实凭证。
- `RoutinUsageTests/TransferSchemaTests.swift`
  - 新增 codec 解码全部 usage fixtures、schema/capability 资源、未知字段、无效 provider/kind、偏好范围、算法/编码/必填字段、重复 credential entry、secret leakage 与 envelope 一致性测试。
- `project.yml`
  - 将 `shared/transfer-schema` 与 `shared/provider-contracts` JSON 加入测试 Bundle。

## Validation command and observed results

- `python3 -m json.tool shared/**/*.json` 等价逐文件校验：通过，10 个 shared JSON 文件可解析；4 个 usage fixture 日期可按 RFC3339 解析。
- `git diff --check`：通过。
- focused command：`xcodegen generate && xcodebuild ... -only-testing:RoutinUsageTests/TransferSchemaTests test`：退出码 0，7/7 tests passed，`** TEST SUCCEEDED **`。
- `scripts/test.sh`：退出码 0，477 tests passed，0 failures，`** TEST SUCCEEDED **`。

## Assumptions

- secret entry 字段值在 envelope model 中表示已编码的密文片段/typed encrypted material；真实加密与解密由后续迁移任务负责，Task 1 不实现密码学或 QR/LAN。
- `newAPI` 继续存在于跨平台稳定 provider registry 以兼容现有 macOS 配置，但通过 `androidV1: false` 明确不属于 Android v1 provider 集合。
- metadata `planType` 沿用现有 macOS 的 `personal`/`coding` 值；Volcengine variant 的协议标识使用 `agentPlan`/`codingPlan`。

## Blockers/remaining risks

- 无当前阻塞。
- JSON Schema 的 `additionalProperties: true` 实现未知字段前向兼容；metadata 仍是明确白名单并由 Swift 拒绝未知键，后续 Android 实现需保持同一边界。
- secret envelope 当前只定义形状和 encoded field 关联，不提供真实性/完整性密码学实现；Task 2/3 需继续实现安全存储、密钥交换和迁移服务。

## Review fix validation evidence

- `xcodegen generate && xcodebuild ... -only-testing:RoutinUsageTests/TransferSchemaTests test`：退出码 0；7/7 focused tests passed，`** TEST SUCCEEDED **`。
- `scripts/test.sh`：退出码 0；477 tests passed，0 failures，`** TEST SUCCEEDED **`。
- `python3 -m json.tool` 逐文件校验 shared JSON：10 个文件通过；`git diff --check` 通过。

## Scoped re-review fix report

### Result

DONE. 收紧 `EncryptedSecretEntry` 的安全边界：所有 bearerToken/apiKey/accessKeyID/secretAccessKey 在 Swift decode 与 encode 均必须是非空、无 padding 的 canonical Base64URL；Volcengine accessKeyID 与 secretAccessKey 必须同时存在，bearer/apiKey 不受该 pair 规则影响。

### Changes made with file paths

- `RoutinUsage/Transfer/TransferModels.swift`
  - 为 typed secret entry 增加 canonical Base64URL 校验（字符集、长度模 4、解码后再编码一致性），覆盖 decode 与 encode。
  - 强制 accessKeyID/secretAccessKey 成对出现。
- `shared/transfer-schema/transfer-schema-v1.json`
  - secret entry 保持 Base64URL pattern，并通过 required/allOf 条件约束 access-key pair。
- `RoutinUsageTests/TransferSchemaTests.swift`
  - 覆盖 `plain-text-secret` 拒绝、有效 Base64URL 接受、编码校验、AK/SK 单独出现拒绝及成对接受；确认 bearer/apiKey 不套用 AK/SK pair 规则。

### Validation command and observed results

- focused TransferSchemaTests：`xcodegen generate && xcodebuild ... -only-testing:RoutinUsageTests/TransferSchemaTests test`，退出码 0，7/7 passed，`** TEST SUCCEEDED **`。
- `scripts/test.sh`：退出码 0，477 tests passed，0 failures，`** TEST SUCCEEDED **`。
- JSON 解析与 `git diff --check`：通过。

### Assumptions

- Base64URL 采用无 `=` padding 的 canonical 表示；后续加密任务须输出该格式。
- pair 规则针对 typed access-key fields，不影响 bearerToken/apiKey 单字段 entry。

### Blockers/remaining risks

- 无当前阻塞；真实加密、密钥交换和 QR/LAN 仍属于后续任务。
