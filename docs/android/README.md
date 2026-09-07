# MyToken Android 客户端

MyToken Android 是 macOS 菜单栏用量监控工具的移动端伴侣应用：从 Mac 扫码迁移
凭证后，在手机上查看各供应商的用量、余额、剩余额度与重置时间，接收用量提醒，
并支持 Routin 每日签到。

## 系统要求

- **Android 10（API 29）或更高版本**。
- 迁移扫码、通知提醒和签到需要真机；模拟器可运行但相机与通知体验受限。

## 构建

前置条件：JDK 17、Android SDK（`ANDROID_HOME` 指向 commandlinetools），
本机可在 `android/local.properties` 写入 `sdk.dir`（该文件不入库）。

```bash
cd android
./gradlew test                          # 全模块 JVM 单元测试（Robolectric 覆盖 Compose UI）
./gradlew :app:assembleDebug            # 构建 Debug APK
./gradlew :app:assembleDebugAndroidTest # 编译 instrumented 测试 APK
./gradlew :app:connectedDebugAndroidTest # 需要已连接的真机/模拟器
```

## 模块结构

| 模块 | 职责 |
| --- | --- |
| `:app` | MainActivity、底部导航（首页/凭证/设置）与子路由（详情/编辑器/迁移）、手写依赖图 `AppGraph`、后台刷新代理与用量提醒分发 |
| `:domain` | 纯 Kotlin 模型与用例：`Credential`、`CredentialSecret`、`CredentialRepository`、`RefreshCredentialsUseCase`（含快照缓存读写与启动恢复） |
| `:data` | Room（凭证元数据 + usage snapshot 缓存）、Keystore 加密 secret 存储、DataStore 偏好/提醒状态 |
| `:core` | 传输加密原语（X25519+HKDF+AES-GCM）、AndroidKeystoreSecretStore、WorkManager 调度、提醒评估器、通知渠道 |
| `:provider` | 各供应商用量适配器（Routin/DeepSeek/GLM/火山方舟/NewAPI）与 `ProviderRegistry` |
| `:feature-home` | 首页用量仪表盘、按供应商分组、详情页（含签到入口） |
| `:feature-credentials` | 凭证列表（搜索/启停/拖动排序/置顶）、凭证编辑器、独立于 Mac 的排序 DataStore |
| `:feature-settings` | 刷新/首页显示/通知/数据迁移/关于设置 |
| `:feature-transfer` | 扫码（CameraX + ML Kit）、局域网握手、解密、导入预览与事务导入 |

跨端迁移协议常量见 `shared/transfer-schema/wire-contract.md` 与
`shared/transfer-schema/transfer-schema-v1.json`。

## CI

- `.github/workflows/android-ci.yml`：`./gradlew test` 全模块 JVM 单元测试 +
  `:app:assembleDebugAndroidTest` 编译验证。`connectedAndroidTest` 需要带
  KVM/真机的 self-hosted runner（工作流内有注释说明如何启用）。
- macOS 侧继续由 `.github/workflows/ci.yml` 执行 `scripts/test.sh`。

## 发布配置审计

- 权限最小化：声明 `POST_NOTIFICATIONS`、`INTERNET`（正常权限，安装时授予）
  与 `CAMERA`；相机权限在 manifest 声明，扫码时经系统对话框授权。
- 云备份：`android:allowBackup="false"`，并以 `backup_rules.xml`
  （Android 11-）与 `data_extraction_rules.xml`（Android 12+）排除数据库、
  DataStore 与 `noBackupFilesDir` 作为纵深防御。Keystore 包裹的密文
  （`cred-*.bin`）本身因密钥不可导出也无法跨设备恢复。
- 发布构建（release）：无开发密钥、无测试 URL、无完整日志开关；minification
  保持关闭直至在真机完成供应商签名相关 keep 规则验证。
- 日志：诊断输出只包含失败消息，不含凭证材料、密文或网页会话内容。

## 手工验收（待真机验证）

以下项目需要在 Android 10+ 真机上与当前 macOS 客户端联调确认：

- [ ] 全供应商迁移（含 accessKeyPair、已停用凭证）与重复导入（跳过/覆盖）。
- [ ] 首次刷新、下拉/手动刷新、断网重试、会话过期提示。
- [ ] 后台周期刷新与用量/失效提醒（含通知权限拒绝后的静默降级）。
- [ ] Routin 签到 Custom Tab 打开与回跳。
- [ ] Keystore 密文在应用更新/重启后的可读性。
