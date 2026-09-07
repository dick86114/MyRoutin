# Task 3 Report

## Result

已完成 macOS 临时迁移会话、局域网临时服务和二维码 payload。会话默认有效期为 5 分钟，支持一次性单客户端连接、session ID/连接码/Mac 临时 X25519 公钥校验，并在完成、取消、过期和断开后进入终止状态并释放临时私钥。二维码 URI 仅编码协议版本、session、host、port、公钥、expiry 和连接码，不包含 TransferPackage、凭证、secret、Cookie 或完整快照。

## Changes made with file paths

- `RoutinUsage/Transfer/TransferSession.swift`
  - 增加 created、waitingForAndroid、connected、sent、completed、cancelled、expired 状态机。
  - 使用 CryptoKit X25519 临时密钥和系统随机连接码；校验有效期、单客户端和三项握手元数据。
  - 终止状态销毁临时私钥。
- `RoutinUsage/Transfer/TransferQRCodePayload.swift`
  - 增加 `TransferQRCodePayload: Codable, Equatable, Sendable`。
  - 增加 `mytoken-transfer://v1` metadata-only URI 编解码、协议/端口/公钥/连接码/expiry 校验。
- `RoutinUsage/Transfer/TransferServer.swift`
  - 增加 `TransferServing`、Network.framework TCP 临时监听服务和 metadata-only 握手请求。
  - 监听临时端口，仅接受一个有效客户端；处理重复连接、取消、断开、listener failure 和 5 分钟超时。
  - 默认选择非 loopback IPv4 作为 LAN host，无可用地址时回退 loopback。
- `RoutinUsageTests/TransferSessionTests.swift`
  - 覆盖创建、有效期、状态流转、单客户端、错误 session/code/public key、过期、取消及临时密钥释放。
- `RoutinUsageTests/TransferServerTests.swift`
  - 覆盖二维码敏感字段排除与 URI 往返、payload 校验、服务启动和幂等停止。

未修改 Task 1 TransferModels/Codec、Task 2 CredentialStoring/SecureCredentialStoring、AppEnvironment、UI、Android 或 Task 4 AEAD 实现。

## Validation command and observed output

- `xcodegen generate && xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage -only-testing:RoutinUsageTests/TransferSessionTests -only-testing:RoutinUsageTests/TransferServerTests CODE_SIGNING_ALLOWED=NO`
  - PASS: 7 tests, 0 failures。
- `scripts/test.sh`
  - PASS: 493 tests, 0 failures。
- `git diff --check`
  - PASS: no whitespace errors。

## Assumptions

- Task 3 只实现握手和服务生命周期；实际 TransferPackage 加密/发送留给 Task 4。
- “销毁临时密钥”在 Swift/CryptoKit 中通过释放临时私钥引用实现；公钥作为二维码 payload 元数据保留至对象生命周期结束。
- 默认 LAN host 使用本机可发现的非 loopback IPv4；调用方和测试可显式传入 host。

## Blockers/remaining risks

- 当前工作区 Xcode 版本为 Xcode 26.6 / macOS 26.5 SDK；测试脚本整体通过，但 AGENTS.md 要求的 CI Xcode 26.3 尚未在本机验证。
- Task 4 仍需在现有连接生命周期上加入 X25519 派生、AEAD 消息格式和加密配置包发送；本任务不会把未加密的凭证包写入网络通道。
- 当前未加入二维码图像渲染和 Mac UI，按 brief 属于后续任务范围。

---

# Review Fix Report

## Result

已修复 review 提出的 Task 3 生命周期与输入校验问题。`TransferServer.start()` 现在对并发调用显式返回 `.alreadyStarting`，不会覆盖 continuation；ready、listener failure、取消、超时和 start/payload 构造失败都会释放等待中的调用并清理 listener、连接与临时会话。缓存 payload 返回前会重新校验 session 状态和 expiry。连接断开会终止 one-shot session。QR host 及 URI authority/path/query key 均执行严格校验，握手缓存限制为 64 KiB。

## Changes made with file paths

- `RoutinUsage/Transfer/TransferServer.swift`
  - 增加并发 start 拒绝、start continuation 的统一 resume 和失败清理。
  - listener failure、cancel、expiry、accepted connection disconnect 统一关闭 listener 和 pending/accepted connections，并终止 session。
  - 缓存 payload 返回前验证状态与有效期；限制握手缓冲区为 64 KiB。
- `RoutinUsage/Transfer/TransferQRCodePayload.swift`
  - 严格拒绝控制字符、路径/查询/片段/authority 分隔符、非法 IPv4/hostname、重复或未知 QR query key。
  - 拒绝非 `mytoken-transfer://v1`、带端口、用户信息、路径或 fragment 的 URI。
- `RoutinUsageTests/TransferServerTests.swift`
  - 新增并发 start 无挂死测试、缓存过期测试、非法 host 失败清理测试、严格 QR key/authority 测试和真实 loopback TCP 握手/断开生命周期测试。
- `RoutinUsageTests/TransferSessionTests.swift`
  - 增加正确长度 mismatched public key 及具体 `TransferSessionError` 断言。

## Validation command and observed output

- 上一轮 focused 结果读取确认：11 tests，0 failures。
- `xcodegen generate && xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage -only-testing:RoutinUsageTests/TransferSessionTests -only-testing:RoutinUsageTests/TransferServerTests CODE_SIGNING_ALLOWED=NO`
  - PASS: 12 tests，0 failures。
- `scripts/test.sh`
  - PASS: 498 tests，0 failures。
- `git diff --check`
  - PASS: no whitespace errors。

## Assumptions

- 并发 `start()` 采用显式拒绝策略；首个调用仍由 stop/failure/ready 路径确定性结束。
- Task 4 AEAD、Mac UI、Android 和二维码图像渲染仍不属于本次修复范围。

## Blockers/remaining risks

- 尚未在 CI 指定的 Xcode 26.3 环境验证；本机为 Xcode 26.6 / macOS 26.5 SDK。
- listener failure 通过非法 host/start 清理路径覆盖；底层端口占用等系统级 listener failure 仍依赖 Network.framework 状态回调。
