import Network
import XCTest
@testable import RoutinUsage

final class TransferServerTests: XCTestCase {
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

    private func withTimeoutResult<T>(seconds: Double, operation: @escaping @Sendable () async -> T) async -> T? {
        try? await withTimeout(seconds: seconds, operation: operation)
    }

    func testQRCodeContainsOnlyTransferMetadataAndRoundTrips() throws {
        let now = Date()
        let payload = try TransferQRCodePayload(
            protocolVersion: 1,
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            host: "192.168.1.10",
            port: 49231,
            macEphemeralPublicKey: Data(repeating: 7, count: 32),
            expiresAt: now.addingTimeInterval(300),
            connectionCode: "123456"
        )

        let encoded = try payload.encodedString()
        XCTAssertTrue(encoded.hasPrefix("mytoken-transfer://v1"))
        XCTAssertFalse(encoded.contains("apiKey"))
        XCTAssertFalse(encoded.contains("bearerToken"))
        XCTAssertFalse(encoded.contains("secretAccessKey"))
        let decoded = try TransferQRCodePayload.decode(encoded)
        XCTAssertEqual(decoded.protocolVersion, payload.protocolVersion)
        XCTAssertEqual(decoded.sessionID, payload.sessionID)
        XCTAssertEqual(decoded.host, payload.host)
        XCTAssertEqual(decoded.port, payload.port)
        XCTAssertEqual(decoded.macEphemeralPublicKey, payload.macEphemeralPublicKey)
        XCTAssertEqual(decoded.connectionCode, payload.connectionCode)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970, payload.expiresAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testPayloadRejectsInvalidPortOrExpiredDate() {
        let values = [0, 65536]
        for port in values {
            XCTAssertThrowsError(try TransferQRCodePayload(
                protocolVersion: 1, sessionID: UUID(), host: "127.0.0.1", port: port,
                macEphemeralPublicKey: Data(repeating: 1, count: 32),
                expiresAt: Date().addingTimeInterval(300), connectionCode: "123456"
            ))
        }
        let expiredPayload = try! TransferQRCodePayload(
            protocolVersion: 1, sessionID: UUID(), host: "127.0.0.1", port: 1234,
            macEphemeralPublicKey: Data(repeating: 1, count: 32),
            expiresAt: Date(timeIntervalSince1970: 1), connectionCode: "123456"
        )
        XCTAssertThrowsError(try expiredPayload.validate())
    }

    func testServerCanStartOnLoopbackAndStopOnce() async throws {
        let server = TransferServer(host: "127.0.0.1")
        let payload = try await server.start()
        XCTAssertEqual(payload.host, "127.0.0.1")
        XCTAssertGreaterThan(payload.port, 0)
        await server.stop()
        await server.stop()
    }

    func testConcurrentStartIsRejectedAndFirstCallIsReleasedByStop() async throws {
        let server = TransferServer(host: "127.0.0.1")
        let first = Task { try? await server.start() }
        let second = Task { () -> TransferServerError? in
            do {
                _ = try await withTimeout(seconds: 1) { try await server.start() }
                return nil
            } catch let error as TransferServerError {
                return error
            } catch {
                return nil
            }
        }
        let secondResult = try await withTimeout(seconds: 1) { await second.value }
        XCTAssertEqual(secondResult, .alreadyStarting, "second start must be rejected")
        await server.stop()
        _ = await withTimeoutResult(seconds: 1) { await first.value }
    }

    func testRealLocalHandshakeAndDisconnectTerminatesSession() async throws {
        let server = TransferServer(host: "127.0.0.1")
        let payload = try await withTimeout(seconds: 2) { try await server.start() }
        let connection = NWConnection(host: "127.0.0.1", port: try XCTUnwrap(NWEndpoint.Port(rawValue: UInt16(payload.port))), using: .tcp)
        connection.start(queue: DispatchQueue(label: "transfer-test-client"))
        try await withTimeout(seconds: 1) {
            while connection.state != .ready { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        let request = TransferConnectionRequest(sessionID: payload.sessionID, connectionCode: payload.connectionCode, macEphemeralPublicKey: payload.macEphemeralPublicKey)
        connection.send(content: try JSONEncoder().encode(request) + Data([10]), completion: .contentProcessed { _ in })
        for _ in 0..<20 {
            if await server.session.state == .connected { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let connectedState = await server.session.state
        XCTAssertEqual(connectedState, .connected)
        connection.cancel()
        for _ in 0..<20 {
            if await server.session.state == .cancelled { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let cancelledState = await server.session.state
        XCTAssertEqual(cancelledState, .cancelled)
        await server.stop()
    }

    func testExpiredHandshakeTerminatesServerAndClosesOneShotSession() async throws {
        let session = TransferSession()
        let server = TransferServer(host: "127.0.0.1", session: session)
        let payload = try await withTimeout(seconds: 2) { try await server.start() }
        let didExpire = await session.expireIfNeeded(now: Date().addingTimeInterval(301))
        XCTAssertTrue(didExpire)
        let connection = NWConnection(host: "127.0.0.1", port: try XCTUnwrap(NWEndpoint.Port(rawValue: UInt16(payload.port))), using: .tcp)
        connection.start(queue: DispatchQueue(label: "transfer-expired-test-client"))
        try await withTimeout(seconds: 1) {
            while connection.state != .ready { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        let request = TransferConnectionRequest(sessionID: payload.sessionID, connectionCode: payload.connectionCode, macEphemeralPublicKey: payload.macEphemeralPublicKey)
        connection.send(content: try JSONEncoder().encode(request) + Data([10]), completion: .contentProcessed { _ in })
        try await Task.sleep(nanoseconds: 100_000_000)
        let state = await session.state
        XCTAssertEqual(state, .expired)
        do {
            _ = try await withTimeout(seconds: 1) { try await server.start() }
            XCTFail("expired handshake must terminate server")
        } catch let error as TransferServerError {
            XCTAssertEqual(error, .sessionExpired)
        }
        connection.cancel()
        await server.stop()
    }

    func testExpiredCachedPayloadCannotBeReturned() async throws {
        let server = TransferServer(host: "127.0.0.1", timeout: 0.02)
        _ = try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        do {
            _ = try await server.start()
            XCTFail("expired server must not return cached payload")
        } catch let error as TransferServerError {
            XCTAssertEqual(error, .sessionExpired)
        }
        let hasKey = await server.session.hasEphemeralPrivateKey
        XCTAssertFalse(hasKey)
    }

    func testInvalidHostFailsStartAndCleansSessionForSubsequentStart() async throws {
        let server = TransferServer(host: "bad/host")
        do {
            _ = try await server.start()
            XCTFail("invalid host must fail")
        } catch let error as TransferQRCodePayloadError {
            XCTAssertEqual(error, .invalidHost)
        }
        let hasKey = await server.session.hasEphemeralPrivateKey
        XCTAssertFalse(hasKey)
        do {
            _ = try await server.start()
            XCTFail("failed one-shot server must not start again")
        } catch let error as TransferServerError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }

    func testQRCodeRejectsHostInjectionDuplicateKeysAndUnexpectedAuthority() throws {
        let payload = try TransferQRCodePayload(protocolVersion: 1, sessionID: UUID(), host: "localhost", port: 1234, macEphemeralPublicKey: Data(repeating: 1, count: 32), expiresAt: Date().addingTimeInterval(300), connectionCode: "123456")
        let encoded = try payload.encodedString()
        for invalidHost in ["bad/host", "bad?host", "bad#host", "bad\\host", "bad\u{0000}host", "256.1.1.1", "1.2.3", "-bad.example", "bad-.example", "bad..example"] {
            XCTAssertThrowsError(try TransferQRCodePayload(protocolVersion: 1, sessionID: UUID(), host: invalidHost, port: 1234, macEphemeralPublicKey: Data(repeating: 1, count: 32), expiresAt: Date().addingTimeInterval(300), connectionCode: "123456"), invalidHost)
        }
        XCTAssertNoThrow(try TransferQRCodePayload(protocolVersion: 1, sessionID: UUID(), host: "example-host.local", port: 1234, macEphemeralPublicKey: Data(repeating: 1, count: 32), expiresAt: Date().addingTimeInterval(300), connectionCode: "123456"))
        XCTAssertThrowsError(try TransferQRCodePayload.decode(encoded + "&code=accessKey"))
        XCTAssertThrowsError(try TransferQRCodePayload.decode(encoded + "&cookie=secret"))
        XCTAssertThrowsError(try TransferQRCodePayload.decode(encoded.replacingOccurrences(of: "mytoken-transfer://v1", with: "mytoken-transfer://v1:443")))
        XCTAssertThrowsError(try TransferQRCodePayload.decode(encoded.replacingOccurrences(of: "mytoken-transfer://v1", with: "mytoken-transfer://v1/path")))
        XCTAssertFalse(encoded.contains("accessKey"))
        XCTAssertFalse(encoded.contains("cookie"))
        XCTAssertFalse(encoded.contains("password"))
        XCTAssertFalse(encoded.contains("config"))
        XCTAssertFalse(encoded.contains("snapshot"))
    }
}
