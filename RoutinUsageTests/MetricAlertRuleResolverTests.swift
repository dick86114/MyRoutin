import XCTest
@testable import RoutinUsage

final class MetricAlertRuleResolverTests: XCTestCase {
    private func alertMetric(
        id: String,
        semantic: NormalizedUsageMetricSemantic
    ) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: id,
            used: semantic == .usedQuota ? 40 : nil,
            limit: 100,
            remaining: semantic == .remainingQuota ? 60 : nil,
            unit: .token,
            presentation: .progress,
            semantic: semantic
        )
    }

    private func alertCapability(
        id: String,
        semantic: NormalizedUsageMetricSemantic,
        defaultAlertEnabled: Bool = true,
        defaultAbsoluteAlertThreshold: Decimal? = nil
    ) -> UsageMetricCapability {
        UsageMetricCapability(
            metricID: id,
            label: id,
            presentation: semantic == .balance ? .balance : .progress,
            semantic: semantic,
            isMenuBarSelectable: true,
            menuBarPriority: 0,
            defaultAlertEnabled: defaultAlertEnabled,
            defaultAbsoluteAlertThreshold: defaultAbsoluteAlertThreshold
        )
    }

    func test已用和剩余指标生成方向正确的默认规则() {
        let preferences = MetricAlertRuleResolver.reconcile(
            existing: .defaultValue,
            metrics: [
                alertMetric(id: "used", semantic: .usedQuota),
                alertMetric(id: "remaining", semantic: .remainingQuota)
            ],
            capabilities: [
                alertCapability(id: "used", semantic: .usedQuota),
                alertCapability(id: "remaining", semantic: .remainingQuota)
            ],
            legacyThresholds: AlertThresholds(low: 80, high: 95)
        )

        let used = preferences.alertRules.first { $0.metricID == "used" }
        XCTAssertEqual(used?.comparator, .greaterThanOrEqual)
        XCTAssertEqual(used?.thresholds.compactMap(\.value), [Decimal(80), Decimal(95)])

        let remaining = preferences.alertRules.first { $0.metricID == "remaining" }
        XCTAssertEqual(remaining?.comparator, .lessThanOrEqual)
        XCTAssertEqual(remaining?.thresholds.compactMap(\.value), [Decimal(20), Decimal(5)])
    }

    func test用户关闭的规则在指标消失后恢复时仍保持关闭() {
        var existing = CredentialUsagePreferences.defaultValue
        existing.alertRules = [.usedPercent(metricID: "weekly", isEnabled: false, low: 70, high: 90)]

        let restored = MetricAlertRuleResolver.reconcile(
            existing: existing,
            metrics: [alertMetric(id: "weekly", semantic: .usedQuota)],
            capabilities: [alertCapability(id: "weekly", semantic: .usedQuota)],
            legacyThresholds: .init()
        )

        XCTAssertFalse(restored.alertRules.first?.isEnabled ?? true)
    }

    func test余额使用能力阈值和币种而状态生成健康规则() {
        let balanceMetric = NormalizedUsageMetric(
            id: "balance",
            label: "余额",
            value: 12,
            unit: .currency,
            presentation: .balance,
            semantic: .balance,
            currencyCode: "CNY"
        )
        let preferences = MetricAlertRuleResolver.reconcile(
            existing: .defaultValue,
            metrics: [
                balanceMetric,
                alertMetric(id: "availability", semantic: .status)
            ],
            capabilities: [
                alertCapability(
                    id: "balance",
                    semantic: .balance,
                    defaultAbsoluteAlertThreshold: 10
                ),
                alertCapability(id: "availability", semantic: .status)
            ],
            legacyThresholds: .init()
        )

        let balance = preferences.alertRules.first { $0.metricID == "balance" }
        XCTAssertEqual(balance?.valueSource, .absoluteValue)
        XCTAssertEqual(balance?.currencyCode, "CNY")
        XCTAssertEqual(balance?.thresholds.compactMap(\.value), [Decimal(10)])

        let availability = preferences.alertRules.first { $0.metricID == "availability" }
        XCTAssertEqual(availability?.comparator, .becomesUnhealthy)
        XCTAssertTrue(availability?.thresholds.isEmpty ?? false)
    }

    func test普通数值和禁用默认提醒不生成规则() {
        let valueMetric = NormalizedUsageMetric(
            id: "requests",
            label: "请求次数",
            value: 20,
            unit: .request,
            presentation: .value,
            semantic: .value
        )
        let preferences = MetricAlertRuleResolver.reconcile(
            existing: .defaultValue,
            metrics: [valueMetric, alertMetric(id: "monthly", semantic: .usedQuota)],
            capabilities: [
                alertCapability(id: "requests", semantic: .value, defaultAlertEnabled: false),
                alertCapability(id: "monthly", semantic: .usedQuota, defaultAlertEnabled: false)
            ],
            legacyThresholds: .init()
        )

        XCTAssertTrue(preferences.alertRules.isEmpty)
    }
}
