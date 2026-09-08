import CryptoKit
import Network
import XCTest
@testable import RoutinUsage

/// Per-connection line reader used by loopback client tests.
private actor TransferTestLineBuffer {
    private var buffer = Data()
    private var continuation: CheckedContinuation<Data, Error>?

    func append(_ data: Data) {
        buffer.append(data)
        // Extract a line only when a reader is waiting; otherwise keep it in
        // the buffer so a later nextLine() can return it.
        guard continuation != nil, let index = buffer.firstIndex(of: 10) else { return }
        let line = Data(buffer[..<index])
        buffer.removeSubrange(..<buffer.index(after: index))
        continuation?.resume(returning: line)
        continuation = nil
    }

    func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func nextLine() async throws -> Data {
        if let index = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<index])
            buffer.removeSubrange(..<buffer.index(after: index))
            return line
        }
        return try await withCheckedThrowingContinuation { current in
            continuation = current
        }
    }
}

@MainActor
final class TransferCryptoTests: XCTestCase {
    private enum TestTimeout: Error { case timedOut }

    private func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TestTimeout.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    // MARK: - Session key agreement

    private func makeConnectedSession() throws -> (TransferSession, Curve25519.KeyAgreement.PrivateKey) {
        let androidKey = Curve25519.KeyAgreement.PrivateKey()
        let session = TransferSession()
        return (session, androidKey)
    }

    private func connect(_ session: TransferSession) async throws {
        let state = await session.state
        if state == .created {
            try await session.beginWaitingForAndroid()
        }
        let id = await session.sessionID
        let code = await session.connectionCode
        let macKey = await session.macEphemeralPublicKey
        try await session.acceptConnection(sessionID: id, connectionCode: code, macEphemeralPublicKey: macKey)
    }

    private func acceptHandshake(_ session: TransferSession, androidKey: Curve25519.KeyAgreement.PrivateKey) async throws {
        let id = await session.sessionID
        try await session.acceptHandshake(
            TransferHandshake(sessionID: id, androidEphemeralPublicKey: androidKey.publicKey.rawRepresentation)
        )
    }

    private func androidSessionKey(
        androidKey: Curve25519.KeyAgreement.PrivateKey,
        macPublicKey: Data,
        sessionID: UUID
    ) throws -> SymmetricKey {
        let macPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: macPublicKey)
        let shared = try androidKey.sharedSecretFromKeyAgreement(with: macPublicKey)
        return TransferCrypto.deriveSessionKey(sharedSecret: shared, sessionID: sessionID, protocolVersion: 1)
    }

    func testBothPartiesDeriveSameKeyAndPackageRoundTrips() async throws {
        let (session, androidKey) = try makeConnectedSession()
        try await connect(session)
        try await acceptHandshake(session, androidKey: androidKey)
        let sessionID = await session.sessionID
        let macKey = await session.macEphemeralPublicKey

        let androidSideKey = try androidSessionKey(androidKey: androidKey, macPublicKey: macKey, sessionID: sessionID)
        let package = try TransferPackageBuilder.makePackage(
            credentials: [try KeyConfiguration(
                id: UUID(),
                name: "主账号",
                keySuffix: "abcd",
                sortOrder: 0,
                providerID: .routin,
                credentialKind: .bearerAPIKey
            )],
            exportedAt: Date(timeIntervalSince1970: 1_000)
        )
        let plaintext = try JSONEncoder().encode(package)
        let message = try await session.sealMessage(plaintext)
        XCTAssertEqual(message.protocolVersion, 1)
        XCTAssertEqual(message.sessionID, sessionID)
        XCTAssertEqual(message.nonce.count, 12)

        let decrypted = try TransferCrypto.open(message, key: androidSideKey)
        XCTAssertEqual(decrypted, plaintext)
        XCTAssertEqual(try JSONDecoder().decode(TransferPackageV1.self, from: decrypted), package)
    }

    func testTamperedSessionIDNonceCiphertextOrTagFailsDecryption() async throws {
        let (session, androidKey) = try makeConnectedSession()
        try await connect(session)
        try await acceptHandshake(session, androidKey: androidKey)
        let sessionID = await session.sessionID
        let macKey = await session.macEphemeralPublicKey
        let key = try androidSessionKey(androidKey: androidKey, macPublicKey: macKey, sessionID: sessionID)

        let message = try await session.sealMessage(Data("configuration".utf8))

        var wrongSession = message
        wrongSession = TransferEncryptedMessage(
            protocolVersion: message.protocolVersion,
            sessionID: UUID(),
            nonce: message.nonce,
            ciphertext: message.ciphertext,
            authenticationTag: message.authenticationTag
        )
        XCTAssertThrowsError(try TransferCrypto.open(wrongSession, key: key))

        var wrongNonce = message
        wrongNonce = TransferEncryptedMessage(
            protocolVersion: message.protocolVersion,
            sessionID: message.sessionID,
            nonce: Data(repeating: 3, count: 12),
            ciphertext: message.ciphertext,
            authenticationTag: message.authenticationTag
        )
        XCTAssertThrowsError(try TransferCrypto.open(wrongNonce, key: key))

        var wrongCiphertext = message
        wrongCiphertext = TransferEncryptedMessage(
            protocolVersion: message.protocolVersion,
            sessionID: message.sessionID,
            nonce: message.nonce,
            ciphertext: Data(repeating: 0, count: message.ciphertext.count),
            authenticationTag: message.authenticationTag
        )
        XCTAssertThrowsError(try TransferCrypto.open(wrongCiphertext, key: key))

        var wrongTag = message
        wrongTag = TransferEncryptedMessage(
            protocolVersion: message.protocolVersion,
            sessionID: message.sessionID,
            nonce: message.nonce,
            ciphertext: message.ciphertext,
            authenticationTag: Data(message.authenticationTag.map { $0 ^ 0xFF })
        )
        XCTAssertThrowsError(try TransferCrypto.open(wrongTag, key: key))
    }

    func testNonceIsUniqueForEachSeal() async throws {
        let (session, androidKey) = try makeConnectedSession()
        try await connect(session)
        try await acceptHandshake(session, androidKey: androidKey)

        let first = try await session.sealMessage(Data("first".utf8))
        let second = try await session.sealMessage(Data("second".utf8))

        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.ciphertext, second.ciphertext)
    }

    func testSealRequiresConnectedHandshake() async throws {
        let (session, androidKey) = try makeConnectedSession()
        await assertThrowsAsync { try await session.sealMessage(Data("x".utf8)) }

        try await session.beginWaitingForAndroid()
        await assertThrowsAsync { try await session.sealMessage(Data("x".utf8)) }

        try await connect(session)
        await assertThrowsAsync { try await session.sealMessage(Data("x".utf8)) }

        try await acceptHandshake(session, androidKey: androidKey)
        do {
            _ = try await session.sealMessage(Data("x".utf8))
        } catch {
            XCTFail("seal after handshake must succeed: \(error)")
        }
    }

    func testHandshakeRejectsWrongSessionIDInvalidKeyAndWrongState() async throws {
        let (session, androidKey) = try makeConnectedSession()

        // Handshake before connection is rejected.
        do {
            try await session.acceptHandshake(
                TransferHandshake(sessionID: await session.sessionID, androidEphemeralPublicKey: androidKey.publicKey.rawRepresentation)
            )
            XCTFail("handshake before connect must throw")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .invalidState(.created))
        }

        try await connect(session)

        do {
            try await session.acceptHandshake(
                TransferHandshake(sessionID: UUID(), androidEphemeralPublicKey: androidKey.publicKey.rawRepresentation)
            )
            XCTFail("session mismatch must throw")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .sessionMismatch)
        }

        do {
            try await session.acceptHandshake(
                TransferHandshake(sessionID: await session.sessionID, androidEphemeralPublicKey: Data(repeating: 1, count: 31))
            )
            XCTFail("invalid android public key must throw")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .invalidAndroidPublicKey)
        }

        try await acceptHandshake(session, androidKey: androidKey)

        do {
            try await session.acceptHandshake(
                TransferHandshake(sessionID: await session.sessionID, androidEphemeralPublicKey: androidKey.publicKey.rawRepresentation)
            )
            XCTFail("duplicate handshake must throw")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .invalidState(.connected))
        }
    }

    func testSentSessionCannotSealAgainAndTerminalStatesDestroyKeyMaterial() async throws {
        let (session, androidKey) = try makeConnectedSession()
        try await connect(session)
        try await acceptHandshake(session, androidKey: androidKey)
        _ = try await session.sealMessage(Data("only send".utf8))
        try await session.markSent()

        do {
            _ = try await session.sealMessage(Data("replay".utf8))
            XCTFail("sent session must not seal again")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .invalidState(.sent))
        }

        try await session.complete()
        let hasSessionKey = await session.hasSessionKey
        XCTAssertFalse(hasSessionKey)

        // Expired sessions cannot derive or seal.
        let (expiredSession, expiredAndroidKey) = try makeConnectedSession()
        try await connect(expiredSession)
        let expired = await expiredSession.expireIfNeeded(now: Date().addingTimeInterval(301))
        XCTAssertTrue(expired)
        do {
            try await expiredSession.acceptHandshake(
                TransferHandshake(sessionID: await expiredSession.sessionID, androidEphemeralPublicKey: expiredAndroidKey.publicKey.rawRepresentation)
            )
            XCTFail("expired session must not accept handshake")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .invalidState(.expired))
        }
        await assertThrowsAsync { try await expiredSession.sealMessage(Data("x".utf8)) }
    }

    func testMessageFromOldSessionCannotBeDecryptedWithNewSessionKey() async throws {
        let (oldSession, oldAndroidKey) = try makeConnectedSession()
        try await connect(oldSession)
        try await acceptHandshake(oldSession, androidKey: oldAndroidKey)
        let oldMessage = try await oldSession.sealMessage(Data("old configuration".utf8))
        try await oldSession.markSent()
        try await oldSession.complete()

        let (newSession, newAndroidKey) = try makeConnectedSession()
        try await connect(newSession)
        try await acceptHandshake(newSession, androidKey: newAndroidKey)
        let newSessionID = await newSession.sessionID
        let newMacKey = await newSession.macEphemeralPublicKey
        let newAndroidSideKey = try androidSessionKey(androidKey: newAndroidKey, macPublicKey: newMacKey, sessionID: newSessionID)

        XCTAssertThrowsError(try TransferCrypto.open(oldMessage, key: newAndroidSideKey))
    }

    // MARK: - Server encrypted send

    func testServerSendsEncryptedPackageOnceAndRejectsReplay() async throws {
        let server = TransferServer(host: "127.0.0.1")
        let payload = try await withTimeout(seconds: 2) { try await server.start() }
        let androidKey = Curve25519.KeyAgreement.PrivateKey()
        let lines = TransferTestLineBuffer()
        let session = await server.session
        let sessionID = payload.sessionID

        let connection = NWConnection(
            host: "127.0.0.1",
            port: try XCTUnwrap(NWEndpoint.Port(rawValue: UInt16(payload.port))),
            using: .tcp
        )
        connection.start(queue: DispatchQueue(label: "transfer-crypto-test-client"))
        try await withTimeout(seconds: 1) {
            while connection.state != .ready { try await Task.sleep(nanoseconds: 10_000_000) }
        }

        final class ReceivePump: @unchecked Sendable {
            let buffer: TransferTestLineBuffer
            let connection: NWConnection
            init(buffer: TransferTestLineBuffer, connection: NWConnection) {
                self.buffer = buffer
                self.connection = connection
            }
            func start() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
                    if let data {
                        Task { await buffer.append(data) }
                    }
                    if error == nil {
                        start()
                    } else {
                        Task { await buffer.fail(error!) }
                    }
                }
            }
        }
        ReceivePump(buffer: lines, connection: connection).start()

        let request = TransferConnectionRequest(
            sessionID: payload.sessionID,
            connectionCode: payload.connectionCode,
            macEphemeralPublicKey: payload.macEphemeralPublicKey
        )
        connection.send(content: try JSONEncoder().encode(request) + Data([10]), completion: .contentProcessed { _ in })
        let acknowledgement = try await withTimeout(seconds: 2) { try await lines.nextLine() }
        XCTAssertTrue(String(data: acknowledgement, encoding: .utf8)?.contains("\"ok\":true") == true)

        let handshake = TransferHandshake(sessionID: payload.sessionID, androidEphemeralPublicKey: androidKey.publicKey.rawRepresentation)
        connection.send(content: try JSONEncoder().encode(handshake) + Data([10]), completion: .contentProcessed { _ in })
        try await withTimeout(seconds: 2) {
            while await !session.hasSessionKey {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        let package = try TransferPackageBuilder.makePackage(
            credentials: [try KeyConfiguration(
                id: UUID(),
                name: "迁移账号",
                keySuffix: "ef12",
                sortOrder: 0,
                providerID: .deepseek,
                credentialKind: .apiKey
            )],
            exportedAt: Date(timeIntervalSince1970: 2_000)
        )
        try await withTimeout(seconds: 2) { try await server.send(package: package) }

        let sentState = await session.state
        XCTAssertEqual(sentState, .sent)

        let encryptedLine = try await withTimeout(seconds: 2) { try await lines.nextLine() }
        let message = try JSONDecoder().decode(TransferEncryptedMessage.self, from: encryptedLine)
        XCTAssertEqual(message.protocolVersion, 1)
        XCTAssertEqual(message.sessionID, payload.sessionID)
        XCTAssertEqual(message.nonce.count, 12)

        let androidSideKey = try androidSessionKey(androidKey: androidKey, macPublicKey: payload.macEphemeralPublicKey, sessionID: sessionID)
        let plaintext = try TransferCrypto.open(message, key: androidSideKey)
        XCTAssertEqual(try TransferSchemaCodec.decode(plaintext), package)
        XCTAssertTrue(String(data: plaintext, encoding: .utf8)!.contains("迁移账号"))
        let wirePackage = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any]
        XCTAssertTrue(wirePackage?["exportedAt"] is String, "wire package must use schema-compatible ISO8601 exportedAt")

        do {
            _ = try await withTimeout(seconds: 2) { try await server.send(package: package) }
            XCTFail("second send must be rejected")
        } catch let error as TransferSessionError {
            XCTAssertEqual(error, .invalidState(.sent))
        }

        connection.cancel()
        await server.stop()
    }

    func testServerSendWithoutConnectionOrHandshakeFails() async throws {
        let server = TransferServer(host: "127.0.0.1")
        _ = try await withTimeout(seconds: 2) { try await server.start() }
        let package = try TransferPackageBuilder.makePackage(credentials: [], exportedAt: Date())

        do {
            _ = try await withTimeout(seconds: 2) { try await server.send(package: package) }
            XCTFail("send without accepted client must fail")
        } catch let error as TransferServerError {
            XCTAssertEqual(error, .notConnected)
        }
        await server.stop()
    }

    // MARK: - Package builder and model

    func testPackageBuilderExportsRealTypedSecretEntries() throws {
        let context = TransferCryptoTestContext()
        defer { context.cleanUp() }

        let bearerSecret = "plan-\(UUID().uuidString)"
        let bearer = try context.addCredential(name: "签名版", providerID: .routin, secret: bearerSecret)
        let apiKeySecret = "sk-secret-\(UUID().uuidString)"
        _ = try context.addCredential(name: "秘密账号", providerID: .deepseek, secret: apiKeySecret)
        let accessKeyID = "AKLT\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let accessSecret = "volc-secret-\(UUID().uuidString)"
        _ = try context.addVolcengineCredential(
            name: "火山账号",
            accessKeyID: accessKeyID,
            secretAccessKey: accessSecret
        )

        let package = try context.makeModel().makeTransferPackage()
        XCTAssertEqual(package.credentials.count, 3)
        XCTAssertEqual(package.secretEnvelope.entries.count, 3)

        let entriesById = Dictionary(uniqueKeysWithValues: package.secretEnvelope.entries.map { ($0.credentialId, $0) })
        XCTAssertEqual(entriesById[bearer.id.uuidString]?.bearerToken, TransferPackageBuilder.base64URLEncode(bearerSecret))
        XCTAssertNil(entriesById[bearer.id.uuidString]?.apiKey)
        let apiKeyID = try XCTUnwrap(package.credentials.first { $0.name == "秘密账号" }?.credentialId)
        XCTAssertEqual(entriesById[apiKeyID]?.apiKey, TransferPackageBuilder.base64URLEncode(apiKeySecret))
        let volcID = try XCTUnwrap(package.credentials.first { $0.name == "火山账号" }?.credentialId)
        XCTAssertEqual(entriesById[volcID]?.accessKeyID, TransferPackageBuilder.base64URLEncode(accessKeyID))
        XCTAssertEqual(entriesById[volcID]?.secretAccessKey, TransferPackageBuilder.base64URLEncode(accessSecret))
    }

    func testPackageBuilderSkipsCredentialsWithoutReadableSecret() throws {
        let context = TransferCryptoTestContext()
        defer { context.cleanUp() }

        let known = try context.addCredential(name: "有密钥", providerID: .deepseek)
        // A credential whose configuration exists but whose secret was removed
        // (or was never readable): the entry must be omitted, not fabricated.
        let orphan = try context.addCredential(name: "无密钥", providerID: .glm)
        context.removeStoredSecret(for: orphan.id)
        context.store.reloadConfigurations()

        let package = try context.makeModel().makeTransferPackage()
        XCTAssertEqual(package.credentials.count, 2)
        XCTAssertEqual(package.secretEnvelope.entries.count, 1)
        XCTAssertEqual(package.secretEnvelope.entries.first?.credentialId, known.id.uuidString)
        XCTAssertEqual(package.secretEnvelope.entries.first?.apiKey, TransferPackageBuilder.base64URLEncode(context.storedSecret(for: known.id)))
    }

    func testPackageBuilderOmitsAccessKeyPairWithoutAccessKeyID() throws {
        let context = TransferCryptoTestContext()
        defer { context.cleanUp() }

        let secret = "volc-secret-\(UUID().uuidString)"
        _ = try context.addVolcengineCredential(name: "缺 AK", accessKeyID: nil, secretAccessKey: secret)

        let package = try context.makeModel().makeTransferPackage()
        XCTAssertEqual(package.credentials.count, 1)
        XCTAssertTrue(package.secretEnvelope.entries.isEmpty)
    }

    func testPackageJSONCarriesOnlyBase64URLEncodedSecrets() throws {
        let context = TransferCryptoTestContext()
        defer { context.cleanUp() }

        let secret = "sk-very-secret-value-/\(UUID().uuidString)"
        _ = try context.addCredential(name: "秘密账号", providerID: .deepseek, secret: secret)

        let package = try context.makeModel().makeTransferPackage()
        let encoded = String(data: try JSONEncoder().encode(package), encoding: .utf8)!
        // The raw secret never appears on the wire; only its unpadded base64url
        // form inside the session-sealed package does.
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertTrue(encoded.contains(TransferPackageBuilder.base64URLEncode(secret)))
        XCTAssertTrue(TransferPackageBuilder.base64URLEncode(secret).allSatisfy { char in
            char.isLetter || char.isNumber || char == "-" || char == "_"
        })
    }

    func testModelSummaryReflectsRealSensitiveItemCount() throws {
        let context = TransferCryptoTestContext()
        defer { context.cleanUp() }

        _ = try context.addCredential(name: "A", providerID: .routin)
        _ = try context.addCredential(name: "B", providerID: .deepseek)
        let model = context.makeModel()

        XCTAssertEqual(model.exportableSecretCount, 2)
        XCTAssertEqual(model.migrationSummaryText, "将迁移以下配置（2 项密钥将以密文传输）")
        XCTAssertTrue(model.migrationSummaryText.contains("密文"))

        context.removeStoredSecret(for: context.store.orderedKeyIDs[1])
        XCTAssertEqual(model.exportableSecretCount, 1)
        XCTAssertEqual(model.migrationSummaryText, "将迁移以下配置（1 项密钥以密文传输，1 个凭据缺少密钥将被跳过）")
    }

    func testModelSummarizesProvidersAndCountdown() throws {
        let context = TransferCryptoTestContext()
        defer { context.cleanUp() }
        _ = try context.addCredential(name: "A", providerID: .routin)
        _ = try context.addCredential(name: "B", providerID: .deepseek)
        _ = try context.addCredential(name: "C", providerID: .deepseek)
        let model = context.makeModel()

        XCTAssertEqual(model.providerSummaries, [
            TransferProviderSummary(providerName: "Routin", credentialCount: 1),
            TransferProviderSummary(providerName: "DeepSeek", credentialCount: 2)
        ])

        let now = Date()
        let expiresAt = now.addingTimeInterval(125.4)
        XCTAssertEqual(model.remainingSeconds(now: now, expiresAt: expiresAt), 126)
        XCTAssertEqual(model.remainingSeconds(now: expiresAt, expiresAt: expiresAt), 0)
    }

    // MARK: - Mac migration UI contract

    func test迁移页面包含二维码倒计时摘要取消与关闭清理() throws {
        let source = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "TransferToAndroidView.swift"
        ])
        let managementSource = try TestSourceReader.read([
            "RoutinUsage", "Views", "Settings", "CredentialManagementView.swift"
        ])

        XCTAssertTrue(source.contains("qrCodeGenerator"))
        XCTAssertTrue(source.contains("剩余有效时间"))
        XCTAssertTrue(source.contains("providerSummaries"))
        XCTAssertTrue(source.contains("取消迁移"))
        XCTAssertTrue(source.contains("onDisappear"))
        XCTAssertTrue(source.contains("stop()"))
        XCTAssertTrue(source.contains("迁移到 Android"))
        XCTAssertTrue(managementSource.contains("TransferToAndroidView"))
        XCTAssertTrue(managementSource.contains("迁移到 Android"))
    }

    // MARK: - Helpers

    private func assertThrowsAsync<T>(_ operation: @escaping () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await operation()
            XCTFail("Expected operation to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}

@MainActor
private struct TransferCryptoTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let keychain: LocalKeyStore
    let repository: KeyRepository
    let store: UsageStore
    let settings: AppSettings

    init() {
        suiteName = "transfer-crypto-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
        keychain = LocalKeyStore(defaults: defaults)
        repository = KeyRepository(defaults: defaults, localStore: keychain)
        settings = AppSettings(defaults: defaults)
        store = UsageStore(
            keyRepository: repository,
            localStore: keychain,
            apiClient: ScriptedUsageFetcher(responses: [:]),
            cache: InMemoryUsageCache(),
            alertEvaluator: AlertEvaluator(defaults: defaults),
            notificationSender: NotificationSenderFake(),
            defaults: defaults
        )
    }

    func addCredential(
        name: String,
        providerID: ProviderID,
        secret: String? = nil,
        metadata: [String: String] = [:]
    ) throws -> KeyConfiguration {
        let resolvedSecret = secret ?? (providerID == .routin
            ? "plan-\(UUID().uuidString)"
            : "secret-\(UUID().uuidString)")
        let configuration = try repository.add(
            name: name,
            secret: resolvedSecret,
            providerID: providerID,
            credentialKind: providerID == .routin ? .bearerAPIKey : .apiKey,
            metadata: metadata
        )
        settings.appendCredential(configuration.id)
        store.reloadConfigurations()
        return configuration
    }

    func addVolcengineCredential(
        name: String,
        accessKeyID: String?,
        secretAccessKey: String
    ) throws -> KeyConfiguration {
        let metadata = accessKeyID.map { ["accessKeyID": $0, "region": "cn-beijing"] } ?? [:]
        let configuration = try repository.add(
            name: name,
            secret: secretAccessKey,
            providerID: .volcengine,
            credentialKind: .accessKeyPair,
            metadata: metadata
        )
        settings.appendCredential(configuration.id)
        store.reloadConfigurations()
        return configuration
    }

    func storedSecret(for id: UUID) -> String {
        try! keychain.read(for: id)!
    }

    func removeStoredSecret(for id: UUID) {
        try? keychain.delete(for: id)
    }

    func makeModel() -> TransferToAndroidModel {
        TransferToAndroidModel(store: store)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
