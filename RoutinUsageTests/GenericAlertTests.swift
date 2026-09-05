import XCTest
@testable import RoutinUsage

final class GenericAlertTests: XCTestCase {
    func testDeepSeek余额低于阈值触发余额通知且正文不伪造百分比() throws {
        let suite = "generic-alert-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let evaluator = AlertEvaluator(
            defaults: defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )
        let key = KeyConfiguration(
            id: UUID(),
            name: "DeepSeek",
            keySuffix: "",
            sortOrder: 0,
            providerID: .deepseek,
            credentialKind: .apiKey,
            metadata: ["balanceWarningThreshold": "10"]
        )
        let snapshot = UsageSnapshot(
            planName: "API 余额",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: .now,
            providerID: .deepseek,
            metrics: [NormalizedUsageMetric(
                id: "balance",
                label: "余额",
                value: 5,
                unit: .currency,
                presentation: .balance,
                semantic: .balance,
                currencyCode: "CNY",
                healthState: .warning
            )]
        )

        let alert = try XCTUnwrap(evaluator.evaluate(key: key, snapshot: snapshot, thresholds: .init()).first)

        XCTAssertEqual(alert.dimension, .balance)
        XCTAssertTrue(alert.notificationBody().contains("余额低于预警值"))
        XCTAssertFalse(alert.notificationBody().contains("已达 0%"))
    }
}
