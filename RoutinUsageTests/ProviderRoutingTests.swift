import XCTest
@testable import RoutinUsage

@MainActor
final class ProviderRoutingTests: XCTestCase {
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

    func test供应商能力声明保持完整顺序和默认策略() throws {
        let registry = ProviderRegistry(providers: [
            RoutinUsageProvider(client: ScriptedUsageFetcher(responses: [:])),
            GLMUsageProvider(),
            NewAPIUsageProvider(),
            VolcenginePlanUsageProvider()
        ])
        let cases: [(
            name: String,
            configuration: KeyConfiguration,
            metricIDs: [String],
            menuBarPriorities: [Int?]
        )] = [
            (
                "Routin 周期套餐",
                KeyConfiguration(
                    id: UUID(),
                    name: "Routin",
                    keySuffix: "",
                    sortOrder: 0,
                    providerID: .routin,
                    credentialKind: .bearerAPIKey
                ),
                ["fiveHour", "weekly"],
                [0, 1]
            ),
            (
                "Routin Token 包",
                KeyConfiguration(
                    id: UUID(),
                    name: "Routin Token",
                    keySuffix: "",
                    sortOrder: 0,
                    providerID: .routin,
                    credentialKind: .bearerAPIKey,
                    metadata: ["usageKind": "tokenPack"]
                ),
                ["token"],
                [0]
            ),
            (
                "GLM",
                KeyConfiguration(
                    id: UUID(),
                    name: "GLM",
                    keySuffix: "",
                    sortOrder: 0,
                    providerID: .glm,
                    credentialKind: .apiKey
                ),
                ["five-hour", "weekly", "model-calls", "zcode-mcp"],
                [0, 1, nil, nil]
            ),
            (
                "New API",
                KeyConfiguration(
                    id: UUID(),
                    name: "New API",
                    keySuffix: "",
                    sortOrder: 0,
                    providerID: .newAPI,
                    credentialKind: .bearerAPIKey
                ),
                [
                    "quota-progress",
                    "today-token",
                    "one-day-token",
                    "seven-day-token",
                    "thirty-day-token",
                    "today-token-cost",
                    "one-day-token-cost",
                    "seven-day-token-cost",
                    "thirty-day-token-cost",
                    "rpm",
                    "tpm",
                    "request-count"
                ],
                [0, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
            ),
            (
                "火山 Coding Plan",
                KeyConfiguration(
                    id: UUID(),
                    name: "火山",
                    keySuffix: "",
                    sortOrder: 0,
                    providerID: .volcengine,
                    credentialKind: .accessKeyPair,
                    metadata: ["planType": "coding"]
                ),
                ["fiveHour", "weekly", "monthly"],
                [0, 1, 2]
            )
        ]

        for testCase in cases {
            let capabilities = registry.metricCapabilities(for: testCase.configuration)

            XCTAssertEqual(
                capabilities.map(\.metricID),
                testCase.metricIDs,
                "\(testCase.name) 的指标顺序应保持稳定"
            )
            XCTAssertEqual(
                capabilities.map(\.menuBarPriority),
                testCase.menuBarPriorities,
                "\(testCase.name) 的菜单栏优先级应保持稳定"
            )
            for capability in capabilities where capability.presentation == .value {
                XCTAssertFalse(
                    capability.isMenuBarSelectable,
                    "\(testCase.name) 的 \(capability.metricID) 不应进入菜单栏"
                )
                XCTAssertFalse(
                    capability.defaultAlertEnabled,
                    "\(testCase.name) 的 \(capability.metricID) 不应默认启用预警"
                )
            }
        }
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
