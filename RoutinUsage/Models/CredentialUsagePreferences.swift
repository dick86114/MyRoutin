import Foundation

struct CredentialUsagePreferences: Codable, Equatable, Sendable {
    var menuBarMetricID: String?
    var notificationsEnabled: Bool
    var alertRules: [MetricAlertRule]

    static let defaultValue = Self(
        menuBarMetricID: nil,
        notificationsEnabled: true,
        alertRules: []
    )
}

enum MetricAlertValueSource: String, Codable, Equatable, Sendable {
    case usedPercent
    case remainingPercent
    case absoluteValue
    case healthState
}

enum MetricAlertComparator: String, Codable, Equatable, Sendable {
    case greaterThanOrEqual
    case lessThanOrEqual
    case becomesUnhealthy
}

struct MetricAlertThreshold: Codable, Equatable, Sendable {
    var level: AlertLevel
    var value: Decimal?
}

struct MetricAlertRule: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var metricID: String
    var isEnabled: Bool
    var valueSource: MetricAlertValueSource
    var comparator: MetricAlertComparator
    var thresholds: [MetricAlertThreshold]
    var currencyCode: String?

    static func ruleID(metricID: String, valueSource: MetricAlertValueSource) -> String {
        "\(metricID):\(valueSource.rawValue)"
    }
}

extension MetricAlertRule {
    static func usedPercent(
        metricID: String,
        isEnabled: Bool,
        low: Decimal,
        high: Decimal
    ) -> Self {
        Self(
            id: ruleID(metricID: metricID, valueSource: .usedPercent),
            metricID: metricID,
            isEnabled: isEnabled,
            valueSource: .usedPercent,
            comparator: .greaterThanOrEqual,
            thresholds: percentThresholds(low: low, high: high),
            currencyCode: nil
        )
    }

    static func remainingPercent(
        metricID: String,
        isEnabled: Bool,
        low: Decimal,
        high: Decimal
    ) -> Self {
        Self(
            id: ruleID(metricID: metricID, valueSource: .remainingPercent),
            metricID: metricID,
            isEnabled: isEnabled,
            valueSource: .remainingPercent,
            comparator: .lessThanOrEqual,
            thresholds: percentThresholds(low: low, high: high),
            currencyCode: nil
        )
    }

    static func absoluteValue(
        metricID: String,
        isEnabled: Bool,
        threshold: Decimal,
        currencyCode: String
    ) -> Self {
        Self(
            id: ruleID(metricID: metricID, valueSource: .absoluteValue),
            metricID: metricID,
            isEnabled: isEnabled,
            valueSource: .absoluteValue,
            comparator: .lessThanOrEqual,
            thresholds: [MetricAlertThreshold(level: .low, value: threshold)],
            currencyCode: currencyCode
        )
    }

    static func unhealthyState(metricID: String, isEnabled: Bool) -> Self {
        Self(
            id: ruleID(metricID: metricID, valueSource: .healthState),
            metricID: metricID,
            isEnabled: isEnabled,
            valueSource: .healthState,
            comparator: .becomesUnhealthy,
            thresholds: [],
            currencyCode: nil
        )
    }

    private static func percentThresholds(
        low: Decimal,
        high: Decimal
    ) -> [MetricAlertThreshold] {
        [
            MetricAlertThreshold(level: .low, value: low),
            MetricAlertThreshold(level: .high, value: high)
        ]
    }
}
