# MyToken 跨端迁移 wire 契约 v1

本文档固定 macOS（Swift，`RoutinUsage/Transfer/`）与 Android（Kotlin，
`android/feature-transfer/`）之间的迁移协议常量。两端实现与本文档不一致时，
以 Swift 源码为准并在此登记。数据模型 schema 见同目录 `transfer-schema-v1.json`。

## 1. 二维码 URI（`TransferQRCodePayload`）

- scheme：`mytoken-transfer`，authority 必须是 `v1`（协议版本）。
- query key 集合**精确等于** `{session, host, port, publicKey, expiry, code}`，
  恰好 6 项，不允许多余/缺失/重复；不允许 user/password/fragment/port/path。
- `session`：UUID，**大写、带连字符**（Swift `uuidString` 词法）。
- `host`：IPv4 点分十进制或合法 hostname（`localhost` 允许）；禁止空白与
  `/\?#@:[]`。
- `port`：1–65535 的十进制字符串。
- `publicKey`：X25519 临时公钥（32 字节），**无 padding 的 base64url**
  （`+→-`、`/→_`、去掉 `=`）。
- `expiry`：ISO-8601 带毫秒小数秒（`withInternetDateTime +
  withFractionalSeconds`），例如 `2027-01-15T08:00:00.000Z`。
- `code`：6 位数字连接码（100000–999999）。

## 2. TCP 握手顺序

1. Android → Mac：`TransferConnectionRequest`
2. Mac → Android：ack（`{"ok":true,"protocolVersion":1}`）
3. Android → Mac：`TransferHandshake`
4. Mac → Android：`TransferEncryptedMessage`（一行 JSON + `\n`）

每条消息一行 JSON（`\n` 结尾）；行缓冲上限 64 KiB。

### JSON 键名（Swift Codable 属性名原样）

| 消息 | 键名 |
| --- | --- |
| ConnectionRequest | `sessionID`, `connectionCode`, `macEphemeralPublicKey` |
| Ack | `ok`, `protocolVersion` |
| Handshake | `sessionID`, `androidEphemeralPublicKey` |
| EncryptedMessage | `protocolVersion`, `sessionID`, `nonce`, `ciphertext`, `authenticationTag` |

**注意**：Swift 属性 `sessionID`（大写 ID）在 JSON 中就是 `sessionID`；
`TransferPackageV1` 内部的 `credentialId`（小写 d）同理，二者拼写不同，
均以 Swift 源码为准。

### Data 字段编码：标准 padded Base64

Swift `JSONEncoder` 对 `Data` 类型字段（`macEphemeralPublicKey`、
`androidEphemeralPublicKey`、`nonce`、`ciphertext`、`authenticationTag`）
输出**标准 Base64 含 padding**（`+`、`/`、`=`；`/` 会被转义为 `\/`，Android
端用宽松 MIME 解码兼容）。这与 base64url（§1、§4）是两套编码，不要混用。

UUID 字段在 JSON 中为大写带连字符字符串；Java 端发送/比较时均规范化为大写。

## 3. 会话密钥（X25519 + HKDF-SHA256）

- ECDH：Curve25519（X25519，32 字节 raw 公钥）。
- HKDF-SHA256（RFC 5869，输出 32 字节）：
  - salt = `sessionID.uuidString` 的 UTF-8（大写、带连字符）
  - info = `mytoken-transfer/v{protocolVersion}/hkdf-sha256`
    （当前版本即 `mytoken-transfer/v1/hkdf-sha256`）
- AEAD：AES-256-GCM，12 字节随机 nonce，128-bit tag；密文/nonce/tag 三段
  分离传输。
- AAD = `mytoken-transfer/v{protocolVersion}|{sessionID.uuidString}`
  （当前即 `mytoken-transfer/v1|{SESSION-UUID}`）。
- 会话一次性：connect → handshake → seal 恰好一次；`markSent` 之后拒绝再封。
- 会话超时 5 分钟（二维码过期即会话过期）。

## 4. 迁移包（TransferPackageV1）

整体 JSON（`TransferPackageV1`）作为 AES-GCM 明文经 §3 密封后发送。
结构见 `transfer-schema-v1.json`，要点：

- `schemaVersion` 恒为 1。
- `credentials[].credentialId`：UUID 大写字符串；`providerId` ∈
  {routin, deepseek, glm, volcengine, newAPI, commandCode}；`credentialKind` ∈
  {bearerAPIKey, apiKey, accessKeyPair}。
- `metadata` 白名单键：`baseURL, userID, region, planType, usageKind,
  websiteURL`；其余键拒绝。
- `preferences`：`refreshIntervalMinutes` ∈ {1,5,15,30}；`alertThresholds`
  ∈ [0,100]；`pinnedCredentialIds` 为 UUID 数组。
- `exportedAt`：JSON 中为 ISO-8601 日期时间（Swift `dateEncodingStrategy =
  .iso8601`，`TransferSchemaCodec` 导出时 sortedKeys；`TransferServer` 发送
  路径使用默认 JSONEncoder）。Android 端用 `Instant.parse` 解析。

### secretEnvelope

- 顶层 `algorithm` ∈ {AES-256-GCM, ChaCha20-Poly1305}（当前实现固定
  `AES-256-GCM`），`keyAgreement` 恒为 `X25519-HKDF-SHA256`。
- **当前实现的语义**：保密性由外层会话 AEAD（§3）提供。顶层
  `nonce/ciphertext/tag/ephemeralPublicKey` 保持惰性占位值（`"AA"`，仅满足
  base64url 词法校验），Android 端对这些字段只做词法校验、不做二次解密。
  `associatedData` 可省略。
- `entries[]`：每条关联一个 `credentialId`（必须出现在 `credentials[]` 中，
  不得重复）。secret 字段（`bearerToken`/`apiKey`/`accessKeyID`/
  `secretAccessKey`）为**原始 secret 字符串的 UTF-8 字节、无 padding
  base64url 编码**——词法规则：非空、字符集 `[A-Za-z0-9_-]`、长度 %4 != 1。
  Android 导入时按 `credentialKind` 取对应字段并 base64url 解码为明文。
  - `bearerAPIKey` → `bearerToken`
  - `apiKey` → `apiKey`
  - `accessKeyPair` → `accessKeyID` + `secretAccessKey` 成对出现（access
    key ID 本身非机密，但同样按 base64url 词法编码）
  - 无条目（Mac 侧读不到 secret）的凭据在导入时计为 skippedWithoutSecret，
    不会写入空密钥。

## 5. 词法校验参考实现

- Swift：`TransferModels.swift` 的 `TransferBase64URLLexicalValidator`。
- Kotlin：`feature-transfer/.../TransferWire.kt` 的 `Base64UrlLexical`。

两端对 base64url 字段（envelope 顶层字段与 entry secret 字段）执行同一规则；
新增字段必须同时更新两端与本文件。
