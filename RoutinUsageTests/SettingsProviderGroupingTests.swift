import XCTest
@testable import RoutinUsage

final class SettingsProviderGroupingTests: XCTestCase {
    func test凭证配置支持非Routin供应商并保留元数据() throws {
        let suite = "provider-grouping-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = KeyRepository(defaults: defaults, localStore: LocalKeyStore(defaults: defaults))

        let configuration = try repository.add(
            name: "DeepSeek",
            secret: "sk-test",
            providerID: .deepseek,
            credentialKind: .apiKey,
            metadata: ["balanceWarningThreshold": "10"]
        )

        XCTAssertEqual(configuration.providerID, .deepseek)
        XCTAssertEqual(configuration.credentialKind, .apiKey)
        XCTAssertEqual(repository.list().first?.metadata["balanceWarningThreshold"], "10")
    }

}
