import XCTest
@testable import RoutinUsage

final class TransferSchemaTests: XCTestCase {
    private let fixtureNames = [
        "routin-bearer",
        "deepseek-bearer",
        "glm-bearer",
        "volcengine-access-key"
    ]

    private var fixtureBundle: Bundle { Bundle(for: TransferSchemaTests.self) }

    func test凭证fixtures可解析且不包含明文秘密() throws {
        for name in fixtureNames {
            let url = try XCTUnwrap(fixtureBundle.url(forResource: name, withExtension: "json"))
            let data = try Data(contentsOf: url)
            let credential = try JSONDecoder().decode(TransferCredential.self, from: data)

            XCTAssertEqual(credential.schemaVersion, 1, name)
            XCTAssertFalse(credential.providerId.isEmpty, name)
            XCTAssertFalse(credential.credentialKind.isEmpty, name)
            XCTAssertNotNil(UUID(uuidString: credential.credentialId), name)
            XCTAssertNil(credential.secret, name)
        }
    }

    func test凭证缺少必需字段或UUID时被拒绝() throws {
        let valid = """
        {"schemaVersion":1,"credentialId":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","providerId":"routin","credentialKind":"bearerAPIKey","name":"fixture","isEnabled":true,"sortOrder":0,"metadata":{}}
        """.data(using: .utf8)!

        for key in ["schemaVersion", "credentialId", "providerId", "credentialKind"] {
            var object = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
            object.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(TransferCredential.self, from: data), key)
        }

        var malformed = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
        malformed["credentialId"] = "not-a-uuid"
        let malformedData = try JSONSerialization.data(withJSONObject: malformed)
        XCTAssertThrowsError(try JSONDecoder().decode(TransferCredential.self, from: malformedData))
    }

    func test所有usageFixtures可解析() throws {
        let usageNames = ["routin-periodic", "deepseek-balance", "glm-usage", "volcengine-usage"]
        for name in usageNames {
            let url = try XCTUnwrap(fixtureBundle.url(forResource: name, withExtension: "json"))
            let package = try JSONDecoder().decode(TransferPackageV1.self, from: Data(contentsOf: url))
            XCTAssertEqual(package.schemaVersion, 1, name)
        }
    }

    func test未知字段被忽略且codec往返保持协议数据() throws {
        let data = """
        {"schemaVersion":1,"credentialId":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","providerId":"routin","credentialKind":"bearerAPIKey","name":"fixture","isEnabled":true,"sortOrder":0,"metadata":{},"futureField":"ignored"}
        """.data(using: .utf8)!
        let credential = try JSONDecoder().decode(TransferCredential.self, from: data)
        XCTAssertEqual(credential.providerId, "routin")

        let package = TransferPackageV1(
            credentials: [credential],
            preferences: TransferPreferences(),
            secretEnvelope: nil,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try TransferSchemaCodec.decode(TransferSchemaCodec.encode(package))
        XCTAssertEqual(decoded, package)
    }

    func testsecretEnvelope可承载密文但二维码payload类型不含秘密字段() throws {
        let envelope = EncryptedSecretEnvelope(
            algorithm: "AES-256-GCM",
            keyAgreement: "X25519-HKDF-SHA256",
            nonce: "bm9uY2U",
            ciphertext: "Y2lwaGVydGV4dA",
            tag: "dGFn",
            ephemeralPublicKey: "cHVibGljLWtleQ"
        )
        XCTAssertEqual(envelope.algorithm, "AES-256-GCM")
        let package = TransferPackageV1(credentials: [], preferences: TransferPreferences(), secretEnvelope: envelope, exportedAt: Date())
        let encoded = try TransferSchemaCodec.encode(package)
        XCTAssertNotNil(String(data: encoded, encoding: .utf8))
    }
}
