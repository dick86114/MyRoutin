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
