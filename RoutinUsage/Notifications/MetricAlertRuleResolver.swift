import Foundation

enum MetricAlertRuleResolver {
    static func reconcile(
        existing: CredentialUsagePreferences,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability],
        legacyThresholds: AlertThresholds
    ) -> CredentialUsagePreferences {
        var preferences = existing
        let capabilityByID = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.metricID, $0) })

        for metric in metrics {
            let capability = capabilityByID[metric.id]
            guard capability?.defaultAlertEnabled != false else { continue }

            let rule = defaultRule(
                for: metric,
                capability: capability,
                legacyThresholds: legacyThresholds
            )
            guard let rule else { continue }
            guard !preferences.alertRules.contains(where: { $0.id == rule.id }) else { continue }
            preferences.alertRules.append(rule)
        }

        return preferences
    }

    private static func defaultRule(
        for metric: NormalizedUsageMetric,
        capability: UsageMetricCapability?,
        legacyThresholds: AlertThresholds
    ) -> MetricAlertRule? {
        switch metric.semantic {
        case .usedQuota:
            return .usedPercent(
                metricID: metric.id,
                isEnabled: true,
                low: Decimal(legacyThresholds.low),
                high: Decimal(legacyThresholds.high)
            )
        case .remainingQuota:
            return .remainingPercent(
                metricID: metric.id,
                isEnabled: true,
                low: Decimal(100 - legacyThresholds.low),
                high: Decimal(100 - legacyThresholds.high)
            )
        case .balance:
            guard let threshold = capability?.defaultAbsoluteAlertThreshold else {
                return .unhealthyState(metricID: metric.id, isEnabled: true)
            }
            return .absoluteValue(
                metricID: metric.id,
                isEnabled: true,
                threshold: threshold,
                currencyCode: metric.currencyCode ?? ""
            )
        case .status:
            return .unhealthyState(metricID: metric.id, isEnabled: true)
        case .value:
            return nil
        }
    }
}
