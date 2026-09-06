import XCTest
@testable import RoutinUsage

final class TransferServerTests: XCTestCase {
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
}
