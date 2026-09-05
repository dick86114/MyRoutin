import XCTest
@testable import RoutinUsage

@MainActor
final class ProviderRoutingTests: XCTestCase {
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
