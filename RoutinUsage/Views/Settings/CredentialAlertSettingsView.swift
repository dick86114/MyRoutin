import SwiftUI

struct CredentialAlertSettingsView: View {
    let title: String
    @Bindable var model: CredentialAlertSettingsModel

    var body: some View {
        Form {
            Section("凭证提醒") {
                Toggle("提醒此凭证", isOn: $model.notificationsEnabled)
                    .accessibilityLabel("提醒此凭证")
            }

            ForEach(model.rules) { rule in
                MetricAlertRuleEditor(
                    rule: Binding(
                        get: { rule },
                        set: { model.updateRule($0) }
                    ),
                    metric: model.metric(for: rule)
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 480)
        .navigationTitle(title)
    }
}

private struct MetricAlertRuleEditor: View {
    @Binding var rule: MetricAlertRule
    let metric: NormalizedUsageMetric?

    var body: some View {
        Section(metric?.label ?? rule.metricID) {
            Toggle("启用提醒", isOn: $rule.isEnabled)
                .accessibilityLabel("\(metric?.label ?? rule.metricID)提醒")

            if rule.isEnabled {
                MetricAlertThresholdControls(rule: $rule, metric: metric)
            }
        }
    }
}

private struct MetricAlertThresholdControls: View {
    @Binding var rule: MetricAlertRule
    let metric: NormalizedUsageMetric?

    var body: some View {
        switch rule.valueSource {
        case .usedPercent:
            ForEach(rule.thresholds.indices, id: \.self) { index in
                Stepper(value: percentBinding(at: index), in: 1...100) {
                    Text("\(index == 0 ? "提醒达到" : "严重达到") \(percent(at: index))%")
                }
            }
        case .remainingPercent:
            ForEach(rule.thresholds.indices, id: \.self) { index in
                Stepper(value: percentBinding(at: index), in: 1...100) {
                    Text("剩余低于 \(percent(at: index))%")
                }
            }
        case .absoluteValue:
            if !rule.thresholds.isEmpty {
                TextField(
                    "余额低于",
                    value: amountBinding,
                    format: .number
                )
                Text(metric?.currencyCode ?? "未提供币种")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .healthState:
            Text("账户状态变为异常时提醒")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func percent(at index: Int) -> Int {
        NSDecimalNumber(decimal: rule.thresholds[index].value ?? 0).intValue
    }

    private func percentBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: { percent(at: index) },
            set: { rule.thresholds[index].value = Decimal($0) }
        )
    }

    private var amountBinding: Binding<Decimal> {
        Binding(
            get: { rule.thresholds[0].value ?? 0 },
            set: { rule.thresholds[0].value = $0 }
        )
    }
}
