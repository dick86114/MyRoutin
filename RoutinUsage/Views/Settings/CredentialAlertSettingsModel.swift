import Foundation
import Observation

@MainActor
@Observable
final class CredentialAlertSettingsModel {
    let credentialID: UUID
    let metrics: [NormalizedUsageMetric]
    private let save: (CredentialUsagePreferences) -> Void
    var preferences: CredentialUsagePreferences {
        didSet { persist() }
    }

    init(
        credentialID: UUID,
        preferences: CredentialUsagePreferences,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability],
        save: @escaping (CredentialUsagePreferences) -> Void = { _ in }
    ) {
        self.credentialID = credentialID
        self.metrics = metrics
        self.save = save
        self.preferences = MetricAlertRuleResolver.reconcile(
            existing: preferences,
            metrics: metrics,
            capabilities: capabilities,
            legacyThresholds: .init()
        )
    }

    var notificationsEnabled: Bool {
        get { preferences.notificationsEnabled }
        set { preferences.notificationsEnabled = newValue }
    }

    var rules: [MetricAlertRule] {
        preferences.alertRules.filter { rule in
            metrics.contains { $0.id == rule.metricID }
        }
    }

    func metric(for rule: MetricAlertRule) -> NormalizedUsageMetric? {
        metrics.first { $0.id == rule.metricID }
    }

    func updateRule(_ updatedRule: MetricAlertRule) {
        guard let index = preferences.alertRules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        preferences.alertRules[index] = updatedRule
    }

    private func persist() {
        save(preferences)
    }
}
