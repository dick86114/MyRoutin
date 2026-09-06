import XCTest
@testable import RoutinUsage

final class TransferSessionTests: XCTestCase {
    private func assertThrowsAsync<T>(_ operation: @escaping () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await operation()
            XCTFail("Expected operation to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }

    func testSessionStartsCreatedAndBuildsFiveMinutePayload() async throws {
        let now = Date()
        let session = TransferSession(now: now)
        let state = await session.state
        let expiresAt = await session.expiresAt
        let code = await session.connectionCode
        let publicKey = await session.macEphemeralPublicKey
        XCTAssertEqual(state, .created)
        XCTAssertEqual(expiresAt, now.addingTimeInterval(300))
        XCTAssertEqual(code.count, 6)
        XCTAssertFalse(publicKey.isEmpty)

        try await session.beginWaitingForAndroid()
        let payload = try await session.makeQRCodePayload(host: "192.168.1.10", port: 49231)
        let sessionID = await session.sessionID
        XCTAssertEqual(payload.protocolVersion, 1)
        XCTAssertEqual(payload.sessionID, sessionID)
        XCTAssertEqual(payload.expiresAt, now.addingTimeInterval(300))
        XCTAssertFalse(payload.macEphemeralPublicKey.isEmpty)
    }

    func testOnlyOneClientCanConnectAndSuccessfulSessionIsOneShot() async throws {
        let session = TransferSession(now: Date())
        try await session.beginWaitingForAndroid()
        let id = await session.sessionID
        let code = await session.connectionCode
        let macKey = await session.macEphemeralPublicKey

        try await session.acceptConnection(sessionID: id, connectionCode: code, macEphemeralPublicKey: macKey)
        let connected = await session.state
        XCTAssertEqual(connected, .connected)
        await assertThrowsAsync { try await session.acceptConnection(sessionID: id, connectionCode: code, macEphemeralPublicKey: macKey) }
        try await session.markSent()
        try await session.complete()
        let completed = await session.state
        let hasKey = await session.hasEphemeralPrivateKey
        XCTAssertEqual(completed, .completed)
        XCTAssertFalse(hasKey)
        await assertThrowsAsync { try await session.markSent() }
    }

    func testInvalidCredentialsAndExpiredSessionAreRejected() async throws {
        let now = Date()
        let session = TransferSession(now: now)
        try await session.beginWaitingForAndroid()
        let id = await session.sessionID
        let key = await session.macEphemeralPublicKey
        let code = await session.connectionCode

        await assertThrowsAsync { try await session.acceptConnection(sessionID: UUID(), connectionCode: code, macEphemeralPublicKey: key, now: now) }
        await assertThrowsAsync { try await session.acceptConnection(sessionID: id, connectionCode: "000000", macEphemeralPublicKey: key, now: now) }
        await assertThrowsAsync { try await session.acceptConnection(sessionID: id, connectionCode: code, macEphemeralPublicKey: Data([1, 2]), now: now) }

        let expired = await session.expireIfNeeded(now: now.addingTimeInterval(301))
        let state = await session.state
        let hasKey = await session.hasEphemeralPrivateKey
        XCTAssertTrue(expired)
        XCTAssertEqual(state, .expired)
        XCTAssertFalse(hasKey)
        await assertThrowsAsync { try await session.acceptConnection(sessionID: id, connectionCode: code, macEphemeralPublicKey: key, now: now) }
    }

    func testCancellationInvalidatesSessionAndDestroysKey() async throws {
        let session = TransferSession()
        await session.cancel()
        let state = await session.state
        let hasKey = await session.hasEphemeralPrivateKey
        XCTAssertEqual(state, .cancelled)
        XCTAssertFalse(hasKey)
        await assertThrowsAsync { try await session.beginWaitingForAndroid() }
    }
}
