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

    func test剩余额度语义按剩余量推导提醒百分比且不读取标签() throws {
        let suite = "generic-alert-remaining-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let evaluator = AlertEvaluator(
            defaults: defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )
        let key = KeyConfiguration(
            id: UUID(),
            name: "GLM",
            keySuffix: "",
            sortOrder: 0,
            providerID: .glm,
            credentialKind: .apiKey
        )
        let snapshot = UsageSnapshot(
            planName: "套餐",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: .now,
            providerID: .glm,
            metrics: [NormalizedUsageMetric(
                id: "quota",
                label: "本期用量",
                limit: 100,
                remaining: 20,
                unit: .token,
                presentation: .progress,
                semantic: .remainingQuota
            )]
        )

        let alert = try XCTUnwrap(evaluator.evaluate(key: key, snapshot: snapshot, thresholds: .init()).first)

        XCTAssertEqual(alert.percent, 80)
        XCTAssertEqual(alert.level, .low)
    }

    func test非额度语义的进度指标不参与提醒() {
        let suite = "generic-alert-non-quota-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let evaluator = AlertEvaluator(
            defaults: defaults,
            deliveryCoordinator: AlertDeliveryCoordinator()
        )
        let key = KeyConfiguration(
            id: UUID(),
            name: "GLM",
            keySuffix: "",
            sortOrder: 0,
            providerID: .glm,
            credentialKind: .apiKey
        )
        let snapshot = UsageSnapshot(
            planName: "套餐",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: .now,
            providerID: .glm,
            metrics: [NormalizedUsageMetric(
                id: "request-count",
                label: "剩余请求",
                used: 100,
                limit: 100,
                unit: .request,
                presentation: .progress,
                semantic: .value
            )]
        )

        XCTAssertTrue(evaluator.evaluate(key: key, snapshot: snapshot, thresholds: .init()).isEmpty)
    }
}
