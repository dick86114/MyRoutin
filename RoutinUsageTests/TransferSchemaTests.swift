import XCTest
@testable import RoutinUsage

final class TransferSchemaTests: XCTestCase {
    private let credentialNames = ["routin-bearer", "deepseek-bearer", "glm-bearer", "volcengine-access-key"]
    private let usageNames = ["routin-periodic", "deepseek-balance", "glm-usage", "volcengine-usage"]
    private var fixtureBundle: Bundle { Bundle(for: TransferSchemaTests.self) }

    func test凭证fixtures可解析且不包含明文秘密() throws {
        for name in credentialNames {
            let url = try XCTUnwrap(fixtureBundle.url(forResource: name, withExtension: "json"))
            let data = try Data(contentsOf: url)
            let credential = try JSONDecoder().decode(TransferCredential.self, from: data)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(credential.schemaVersion, 1, name)
            XCTAssertNotNil(ProviderID(rawValue: credential.providerId), name)
            XCTAssertNotNil(CredentialKind(rawValue: credential.credentialKind), name)
            XCTAssertNotNil(UUID(uuidString: credential.credentialId), name)
            XCTAssertNil(object["secret"], name)
            XCTAssertNil(object["accessKeyID"], name)
        }
    }

    func test凭证缺少必需字段无效UUID供应商或类型时被拒绝() throws {
        let valid = Data(#"{"schemaVersion":1,"credentialId":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","providerId":"routin","credentialKind":"bearerAPIKey","name":"fixture","isEnabled":true,"sortOrder":0,"metadata":{}}"#.utf8)
        for key in ["schemaVersion", "credentialId", "providerId", "credentialKind"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            object.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(TransferCredential.self, from: JSONSerialization.data(withJSONObject: object)), key)
        }
        for (key, value) in [("credentialId", "not-a-uuid"), ("providerId", "unknown"), ("credentialKind", "password")] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            object[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(TransferCredential.self, from: JSONSerialization.data(withJSONObject: object)), key)
        }
        var metadataObject = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        metadataObject["metadata"] = ["accessKeyID": "must-be-encrypted"]
        XCTAssertThrowsError(try JSONDecoder().decode(TransferCredential.self, from: JSONSerialization.data(withJSONObject: metadataObject)))
    }

    func test所有usageFixtures通过TransferSchemaCodec解析RFC3339日期() throws {
        for name in usageNames {
            let url = try XCTUnwrap(fixtureBundle.url(forResource: name, withExtension: "json"))
            let package = try TransferSchemaCodec.decode(Data(contentsOf: url))
            XCTAssertEqual(package.schemaVersion, 1, name)
        }
    }

    func test未知字段被Swift忽略且codec输出包含显式secretEnvelope() throws {
        let data = Data(#"{"schemaVersion":1,"credentialId":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","providerId":"routin","credentialKind":"bearerAPIKey","name":"fixture","metadata":{},"futureField":"ignored"}"#.utf8)
        let credential = try JSONDecoder().decode(TransferCredential.self, from: data)
        let package = TransferPackageV1(credentials: [credential], preferences: TransferPreferences(), exportedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoded = try TransferSchemaCodec.encode(package)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["secretEnvelope"] as? [String: Any])
        XCTAssertNil(object["futureField"])
    }

    func testsecretEnvelope按credentialId关联多凭证且Volcengine字段有类型() throws {
        let id = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let entry = try EncryptedSecretEntry(credentialId: id, accessKeyID: "YWstZHVtbXk", secretAccessKey: "c2VjcmV0LWR1bW15")
        let envelope = try EncryptedSecretEnvelope(algorithm: "AES-256-GCM", keyAgreement: "X25519-HKDF-SHA256", nonce: "bm9uY2U", ciphertext: "Y2lwaGVydGV4dA", tag: "dGFn", ephemeralPublicKey: "cHVibGljLWtleQ", entries: [entry])
        XCTAssertEqual(envelope.entries.first?.credentialId, id.uuidString)
        XCTAssertEqual(envelope.entries.first?.accessKeyID, "YWstZHVtbXk")
        XCTAssertNil(envelope.entries.first?.bearerToken)
        XCTAssertNoThrow(try JSONEncoder().encode(entry))
        let package = TransferPackageV1(
            credentials: [TransferCredential(credentialId: id, providerId: "volcengine", credentialKind: "accessKeyPair", name: "fixture")],
            preferences: TransferPreferences(), secretEnvelope: envelope, exportedAt: Date()
        )
        XCTAssertNoThrow(try TransferSchemaCodec.encode(package))
        let orphan = try EncryptedSecretEntry(credentialId: UUID(), apiKey: "AA")
        let orphanEnvelope = try EncryptedSecretEnvelope(algorithm: "AES-256-GCM", keyAgreement: "X25519-HKDF-SHA256", nonce: "AA", ciphertext: "AA", tag: "AA", ephemeralPublicKey: "AA", entries: [orphan])
        XCTAssertThrowsError(try TransferSchemaCodec.encode(TransferPackageV1(credentials: [], preferences: TransferPreferences(), secretEnvelope: orphanEnvelope, exportedAt: Date())))
    }

    func test偏好范围算法编码必填字段和重复秘密凭证被拒绝() throws {
        let invalidPreferences = Data(#"{"refreshIntervalMinutes":2,"wifiOnly":false,"openAppRefresh":true,"notificationsEnabled":true,"alertThresholds":[50],"pinnedCredentialIds":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TransferPreferences.self, from: invalidPreferences))
        XCTAssertThrowsError(try EncryptedSecretEnvelope(algorithm: "RSA", keyAgreement: "X25519-HKDF-SHA256", nonce: "AA", ciphertext: "AA", tag: "AA", ephemeralPublicKey: "AA"))
        XCTAssertThrowsError(try EncryptedSecretEnvelope(algorithm: "AES-256-GCM", keyAgreement: "wrong", nonce: "AA", ciphertext: "AA", tag: "AA", ephemeralPublicKey: "AA"))
        let id = UUID()
        let entry = try EncryptedSecretEntry(credentialId: id, apiKey: "AA")
        XCTAssertThrowsError(try EncryptedSecretEntry(credentialId: id, accessKeyID: "AA"))
        XCTAssertThrowsError(try EncryptedSecretEntry(credentialId: id, secretAccessKey: "AA"))
        XCTAssertThrowsError(try EncryptedSecretEnvelope(algorithm: "AES-256-GCM", keyAgreement: "X25519-HKDF-SHA256", nonce: "AA", ciphertext: "AA", tag: "AA", ephemeralPublicKey: "AA", entries: [entry, entry]))
        let malformed = Data(#"{"algorithm":"AES-256-GCM","keyAgreement":"X25519-HKDF-SHA256","nonce":"AA","ciphertext":"AA","tag":"AA","ephemeralPublicKey":"AA"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EncryptedSecretEnvelope.self, from: malformed))
        let plainSecret = Data(#"{"credentialId":"44444444-4444-4444-8444-444444444444","bearerToken":"plain-text-secret"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EncryptedSecretEntry.self, from: plainSecret))
    }

    func testBase64URL词法契约在schema与Swift接受集一致() throws {
        let schemaURL = try XCTUnwrap(fixtureBundle.url(forResource: "transfer-schema-v1", withExtension: "json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let base64url = try XCTUnwrap(definitions["base64url"] as? [String: Any])
        let patterns = try XCTUnwrap(base64url["anyOf"] as? [[String: Any]]).compactMap { $0["pattern"] as? String }
        XCTAssertEqual(patterns.count, 3)
        for (value, expected) in [
            ("AA", true), ("Zh", true), ("AAA", true),
            ("A", false), ("AAAAA", false), ("AA=", false), ("", false), ("é", false)
        ] {
            let schemaAccepted = patterns.contains { pattern in
                (try? NSRegularExpression(pattern: pattern).firstMatch(in: value, range: NSRange(value.startIndex..., in: value))) != nil
            }
            let entry = Data(#"{"credentialId":"44444444-4444-4444-8444-444444444444","bearerToken":""#.utf8) + Data(value.utf8) + Data(#""}"#.utf8)
            let swiftAccepted = (try? JSONDecoder().decode(EncryptedSecretEntry.self, from: entry)) != nil
            XCTAssertEqual(schemaAccepted, expected, value)
            XCTAssertEqual(swiftAccepted, schemaAccepted, value)
        }
    }

    func testEncryptedSecretEnvelope所有encoded字段与schema词法接受集一致() throws {
        let encodedFields = ["nonce", "ciphertext", "tag", "ephemeralPublicKey"]
        let acceptedValues = ["AA", "Zh", "AAA"]
        let rejectedValues = ["A", "AAAAA", "AA=", "", "é"]
        let base: [String: Any] = [
            "algorithm": "AES-256-GCM",
            "keyAgreement": "X25519-HKDF-SHA256",
            "nonce": "AA",
            "ciphertext": "AA",
            "tag": "AA",
            "ephemeralPublicKey": "AA",
            "entries": []
        ]

        for field in encodedFields {
            for value in acceptedValues {
                var object = base
                object[field] = value
                XCTAssertNoThrow(
                    try JSONDecoder().decode(
                        EncryptedSecretEnvelope.self,
                        from: JSONSerialization.data(withJSONObject: object)
                    ),
                    "expected \(field)=\(value) to be accepted"
                )
            }
            for value in rejectedValues {
                var object = base
                object[field] = value
                XCTAssertThrowsError(
                    try JSONDecoder().decode(
                        EncryptedSecretEnvelope.self,
                        from: JSONSerialization.data(withJSONObject: object)
                    ),
                    "expected \(field)=\(value) to be rejected"
                )
            }
        }
    }

    func testschema和能力清单资源可解析且包含六个provider及Volcengine两个variant() throws {
        let schemaURL = try XCTUnwrap(fixtureBundle.url(forResource: "transfer-schema-v1", withExtension: "json"))
        let capabilityURL = try XCTUnwrap(fixtureBundle.url(forResource: "provider-capabilities", withExtension: "json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let capabilities = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: capabilityURL)) as? [String: Any])
        XCTAssertEqual(schema["$id"] as? String, "https://mytoken.routin.ai/schema/transfer/v1")
        let providers = try XCTUnwrap(capabilities["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.count, 6)
        let volcengine = try XCTUnwrap(providers.first { $0["providerId"] as? String == "volcengine" })
        XCTAssertEqual((volcengine["variants"] as? [[String: Any]])?.count, 2)
    }
}
