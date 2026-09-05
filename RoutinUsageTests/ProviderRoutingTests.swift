import XCTest
@testable import RoutinUsage

@MainActor
final class ProviderRoutingTests: XCTestCase {
    func test火山CodingPlan在首次刷新前声明可选窗口() throws {
        let configuration = KeyConfiguration(
            id: UUID(),
            name: "火山",
            keySuffix: "",
            sortOrder: 0,
            providerID: .volcengine,
            credentialKind: .accessKeyPair,
            metadata: ["planType": "coding"]
        )

        let registry = ProviderRegistry(providers: [VolcenginePlanUsageProvider()])
        let capabilities = registry.metricCapabilities(for: configuration)

        XCTAssertEqual(capabilities.map(\.metricID), ["fiveHour", "weekly", "monthly"])
        XCTAssertEqual(capabilities.first?.menuBarPriority, 0)
    }

    func test供应商能力声明保留指标策略和预警默认值() throws {
        let configuration = KeyConfiguration(
            id: UUID(),
            name: "DeepSeek",
            keySuffix: "",
            sortOrder: 0,
            providerID: .deepseek,
            credentialKind: .apiKey,
            metadata: ["balanceWarningThreshold": "10.5"]
        )
        let registry = ProviderRegistry(providers: [DeepSeekUsageProvider()])

        let capabilities = registry.metricCapabilities(for: configuration)

        XCTAssertEqual(capabilities.map(\.metricID), ["balance", "availability"])
        XCTAssertEqual(capabilities.first?.defaultAbsoluteAlertThreshold, Decimal(string: "10.5"))
        XCTAssertTrue(capabilities.first?.isMenuBarSelectable == true)
        XCTAssertFalse(capabilities.last?.defaultAlertEnabled == true)
    }

    func testNewAPI统计指标默认不进入菜单栏或预警() throws {
        let configuration = KeyConfiguration(
            id: UUID(),
            name: "New API",
            keySuffix: "",
            sortOrder: 0,
            providerID: .newAPI,
            credentialKind: .bearerAPIKey
        )
        let registry = ProviderRegistry(providers: [NewAPIUsageProvider()])

        let capabilities = registry.metricCapabilities(for: configuration)
        let statistics = capabilities.filter { $0.metricID.hasSuffix("token") }

        XCTAssertTrue(capabilities.first?.isMenuBarSelectable == true)
        XCTAssertTrue(statistics.allSatisfy { !$0.isMenuBarSelectable && !$0.defaultAlertEnabled })
    }

    func testUsageStore按凭证供应商路由刷新请求() async throws {
        let suite = "provider-routing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let localStore = LocalKeyStore(defaults: defaults)
        let repository = KeyRepository(defaults: defaults, localStore: localStore)
        let configuration = try repository.add(
            name: "DeepSeek",
            secret: "sk-test",
            providerID: .deepseek,
            credentialKind: .apiKey,
            metadata: [:]
        )
        let snapshot = UsageSnapshot(
            planName: "余额",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 100),
            providerID: .deepseek,
            credentialID: configuration.id,
            metrics: [NormalizedUsageMetric(id: "balance", label: "余额", value: 8, unit: .currency, presentation: .balance, semantic: .balance)]
        )
        let provider = RecordingProvider(id: .deepseek, snapshot: snapshot)
        let store = UsageStore(
            keyRepository: repository,
            localStore: localStore,
            apiClient: ScriptedUsageFetcher(responses: [:]),
            cache: InMemoryUsageCache(),
            alertEvaluator: AlertEvaluator(defaults: defaults),
            notificationSender: NotificationSenderFake(),
            defaults: defaults,
            providerRegistry: ProviderRegistry(providers: [provider])
        )

        await store.refresh(keyID: configuration.id)

        XCTAssertEqual(store.state(for: configuration.id)?.snapshot?.providerID, .deepseek)
        let count = await provider.requestCount()
        XCTAssertEqual(count, 1)
    }
}

private actor RecordingProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    private let snapshot: UsageSnapshot
    private var count = 0

    init(id: ProviderID, snapshot: UsageSnapshot) {
        descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == id })!
        self.snapshot = snapshot
    }

    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        try await fetchUsage(credential, now: now)
    }

    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        count += 1
        return snapshot
    }

    func requestCount() -> Int { count }
}
