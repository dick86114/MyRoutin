import XCTest
@testable import RoutinUsage

final class ProviderModelsTests: XCTestCase {
    func test凭证官网链接自动补全协议并保存到元数据() throws {
        let result = try CredentialEditorValidation.validate(
            providerID: .glm,
            name: "GLM",
            apiKey: "key",
            accessKeyID: "",
            secretAccessKey: "",
            region: "",
            balanceWarningThreshold: "",
            websiteURL: "example.com/console/"
        )

        XCTAssertEqual(result.metadata["websiteURL"], "https://example.com/console/")
    }

    func test无效官网链接被拒绝且空链接不保存元数据() throws {
        XCTAssertThrowsError(
            try CredentialEditorValidation.validate(
                providerID: .glm,
                name: "GLM",
                apiKey: "key",
                accessKeyID: "",
                secretAccessKey: "",
                region: "",
                balanceWarningThreshold: "",
                websiteURL: "ht tp://example.com"
            )
        ) { error in
            XCTAssertEqual(error as? UsageStoreError, .invalidURL)
        }

        let result = try CredentialEditorValidation.validate(
            providerID: .glm,
            name: "GLM",
            apiKey: "key",
            accessKeyID: "",
            secretAccessKey: "",
            region: "",
            balanceWarningThreshold: "",
            websiteURL: " "
        )
        XCTAssertNil(result.metadata["websiteURL"])
    }

    func test每个供应商使用独立主题色() {
        let colors = ProviderID.allCases.map { ProviderTheme.accentColor(for: $0) }
        XCTAssertEqual(Set(colors).count, ProviderID.allCases.count)
    }

    func test首期供应商描述包含简称凭证类型和能力() {
        let descriptors = ProviderRegistry.builtInDescriptors

        XCTAssertEqual(descriptors.map(\.id), [.routin, .deepseek, .glm, .volcengine, .newAPI, .commandCode])
        XCTAssertEqual(descriptors.first(where: { $0.id == .deepseek })?.shortCode, "DS")
        XCTAssertEqual(descriptors.first(where: { $0.id == .glm })?.shortCode, "GLM")
        XCTAssertEqual(descriptors.first(where: { $0.id == .volcengine })?.shortCode, "VOL")
        XCTAssertTrue(descriptors.first(where: { $0.id == .deepseek })?.capabilities.contains(.balance) == true)
        XCTAssertTrue(descriptors.first(where: { $0.id == .routin })?.capabilities.contains(.quotaWindow) == true)
        XCTAssertEqual(descriptors.first(where: { $0.id == .newAPI })?.shortCode, "NEW")
        XCTAssertTrue(descriptors.first(where: { $0.id == .newAPI })?.capabilities.contains(.balance) == true)
        XCTAssertEqual(descriptors.first(where: { $0.id == .commandCode })?.shortCode, "CMD")
        XCTAssertTrue(descriptors.first(where: { $0.id == .commandCode })?.capabilities.contains(.quotaWindow) == true)
    }

    func test旧KeyConfiguration默认映射为Routin凭证() throws {
        let configuration = KeyConfiguration(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "主账号",
            keySuffix: "1234",
            sortOrder: 0
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(KeyConfiguration.self, from: data)

        XCTAssertEqual(decoded.providerID, .routin)
        XCTAssertEqual(decoded.credentialKind, .bearerAPIKey)
        XCTAssertEqual(decoded.metadata, [:])
    }

    func test凭证配置编码保留供应商和非秘密元数据() throws {
        let configuration = KeyConfiguration(
            id: UUID(),
            name: "火山账号",
            keySuffix: "ABCD",
            sortOrder: 1,
            providerID: .volcengine,
            credentialKind: .accessKeyPair,
            metadata: ["region": "cn-beijing", "planType": "coding"]
        )

        let decoded = try JSONDecoder().decode(
            KeyConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded.providerID, .volcengine)
        XCTAssertEqual(decoded.credentialKind, .accessKeyPair)
        XCTAssertEqual(decoded.metadata["region"], "cn-beijing")
        XCTAssertEqual(decoded.metadata["planType"], "coding")
    }
}
