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

---

# Scoped Re-review Fix Report

## Result

已修复剩余两项 review finding。接收握手在 session 已过期或进入终止状态时，现在会立即关闭 listener、pending/accepted connections、buffers、timeout task 并终止 server lifecycle；ready 后 listener cancelled 也会进入同一清理路径。并发 start 测试现在明确断言第二次调用返回 `.alreadyStarting`，且首次 start、第二次 start、任务 value、TCP start 和握手等待均有有界超时。

## Changes made with file paths

- `RoutinUsage/Transfer/TransferServer.swift`
  - handshake catch 检测 terminal session 并执行完整 server cleanup。
  - ready 状态后的 listener `.cancelled` 触发终止与资源清理。
  - 保持并发 start 显式拒绝策略。
- `RoutinUsageTests/TransferServerTests.swift`
  - 增加过期 handshake 清理测试。
  - 并发 start 第二调用显式 `XCTAssertEqual(.alreadyStarting)`；所有异步等待使用 1–2 秒 timeout helper。
  - 真实 TCP 握手/断开测试的 listener start 和 client ready 等待均有 timeout。
- `RoutinUsageTests/TransferSessionTests.swift`
  - 保留具体 session mismatch/code/public key error 断言。

## Validation command and observed output

- `xcodegen generate && xcodebuild test -project RoutinUsage.xcodeproj -scheme RoutinUsage -only-testing:RoutinUsageTests/TransferSessionTests -only-testing:RoutinUsageTests/TransferServerTests CODE_SIGNING_ALLOWED=NO`
  - PASS: 13 tests，0 failures。
- `scripts/test.sh`
  - PASS: 499 tests，0 failures。
- `git diff --check`
  - PASS: no whitespace errors。

## Assumptions

- 并发 start 继续采用显式拒绝；测试通过两个并发 Task 和 bounded timeout 验证，不依赖固定 sleep 时序。
- 未实现 Task 4 AEAD、Mac UI、Android 或二维码图像渲染。

## Blockers/remaining risks

- 本机为 Xcode 26.6 / macOS 26.5 SDK，尚未在 CI 要求的 Xcode 26.3 环境运行。
- listener 底层系统 failure 的具体 errno 仍由 Network.framework 提供；代码已统一处理 `.failed` 回调。

---

# Concurrent Start Reliability Fix Report (Round 4)

## Result

已修复并发 start 测试的可靠性缺陷。上一版通过「外部 Task 的 value + timeout」和等待 `.waitingForAndroid` 后再调用第二次 start 的 latch 方案都不可靠：latch 与 listener `.ready` 之间存在竞态，第二次 start 会合法地返回缓存 payload 而非 `.alreadyStarting`。新实现将两次 start 调用背靠背并发地提交到同一 throwing task group 中：actor 的 `isStarting` 保证恰好一个调用被拒绝；先完成的一个必然是被拒调用（pending 的调用在 `stop()` 释放前无法完成），断言其为 `.alreadyStarting`，成功则明确 XCTFail；另一个调用在 `stop()` 与 3 秒 watchdog 的双重有界内结束（成功或 cancellation/error 均可）。所有 await 均在结构化 task group 内，超时会级联取消 pending 的 start（生产端 `start()` 带 `onCancel` → `stop()` → resume CancellationError），不会留下等待的非结构化任务。保留了上一代理写入的有效改动（各关键 await 的 `withTimeout` 包装等），未修改生产代码。

## Changes made with file paths

- `RoutinUsageTests/TransferServerTests.swift`
  - 重写并发 start 测试：移除外部 Task + timeout 吞错方案与不可靠的 `.waitingForAndroid` latch，改为背靠背并发两次 `start()` + 动态标注（先完成者必须是被拒调用）。
  - 第二个 start 成功返回 payload 时明确 `XCTFail`，失败时断言具体为 `.alreadyStarting`（含非 `TransferServerError` 的失败路径）。
  - 首个（pending）start 的完成由 `stop()` 和 group watchdog 双重有界，超时抛错前会取消全部子任务；被取消的 watchdog 静默退出，不污染结果。
  - 保留上一轮对 `testServerCanStartOnLoopbackAndStopOnce`、`testExpiredCachedPayloadCannotBeReturned` 等关键 await 的有界 timeout 改动。

## Validation command and observed output

- `xcodebuild test ... -only-testing:RoutinUsageTests/TransferServerTests/testConcurrentStartIsRejectedAndFirstCallIsReleasedByStop -test-iterations 20 CODE_SIGNING_ALLOWED=NO`
  - PASS: 20/20 iterations passed（单次 ≤10ms，验证拒绝路径确定性成立）。
- `xcodebuild test ... -only-testing:RoutinUsageTests/TransferSessionTests -only-testing:RoutinUsageTests/TransferServerTests CODE_SIGNING_ALLOWED=NO`
  - PASS: 13 tests（9 TransferServerTests + 4 TransferSessionTests），0 failures。
- `scripts/test.sh`
  - PASS: 499 tests，0 failures（运行两次均通过）。
- `git diff --check`
  - PASS: no whitespace errors。

## Assumptions

- 「第二个 start」按动态语义标注：并发两次调用中先完成、被 actor 以 `isStarting` 拒绝的那个即第二个调用；其成功（返回缓存 payload）视为违反并发拒绝约定并 XCTFail。
- listener `.ready` 先于第二次调用触发的场景（缓存 payload 返回）属于正确的生产行为，不属于并发拒绝路径；测试通过背靠背调用使该竞态窗口不再影响断言。
- Task 4 AEAD、Mac UI、Android 或二维码图像渲染仍不在本次修复范围。

## Blockers/remaining risks

- 生产端 `TransferServer.start()` 在 `listener.start` 与 continuation 存储之间存在极窄窗口：若 `stop()` 恰好在其间完成，continuation 将永不被 resume，调用方即使取消也会挂起（`onCancel` 的 `stop()` 因 `isStopped` guard 直接返回）。本次范围禁止修改生产代码，测试与既有版本一样未覆盖该窗口；建议后续生产修复（如 stop 时兜底 resume 或 start 结尾检查 isStopped）。
- 本机为 Xcode 26.6 / macOS 26.5 SDK，尚未在 CI 要求的 Xcode 26.3 环境运行。
