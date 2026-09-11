import SwiftUI

struct CredentialAlertSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Bindable var model: CredentialAlertSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            masterToggle
            ruleGrid
        }
        .padding(24)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var ruleGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 14),
                count: model.rules.count > 1 ? 2 : 1
            ),
            alignment: .leading,
            spacing: 14
        ) {
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                Text("控制此凭证的额度与状态提醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭")
            .accessibilityLabel("关闭")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var masterToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("提醒此凭证")
                Text("关闭后将暂停此凭证的全部提醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("提醒此凭证", isOn: $model.notificationsEnabled)
                .labelsHidden()
                .accessibilityLabel("提醒此凭证")
        }
        .padding(14)
        .liquidGlassControlSurface()
    }
}

private struct MetricAlertRuleEditor: View {
    @Binding var rule: MetricAlertRule
    let metric: NormalizedUsageMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric?.label ?? rule.metricID)
                        .font(.headline)
                    if let metric {
                        Text(metricSummary(metric))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Toggle("启用提醒", isOn: $rule.isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("\(metric?.label ?? rule.metricID)提醒")
            }

            Divider()

            if rule.isEnabled {
                MetricAlertThresholdControls(rule: $rule, metric: metric)
            } else {
                Label("已暂停此类提醒", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .liquidGlassControlSurface()
    }

    private func metricSummary(_ metric: NormalizedUsageMetric) -> String {
        switch metric.semantic {
        case .usedQuota:
            return "按已用百分比提醒"
        case .remainingQuota:
            return "按剩余百分比提醒"
        case .balance:
            return "按余额阈值提醒"
        case .status:
            return "账户异常时提醒"
        case .value:
            return "数值提醒"
        }
    }
}

private struct MetricAlertThresholdControls: View {
    @Binding var rule: MetricAlertRule
    let metric: NormalizedUsageMetric?

    var body: some View {
        switch rule.valueSource {
        case .usedPercent:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rule.thresholds.indices, id: \.self) { index in
                    thresholdRow(
                        label: index == 0 ? "提醒达到" : "严重达到",
                        index: index
                    )
                }
            }
        case .remainingPercent:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rule.thresholds.indices, id: \.self) { index in
                    thresholdRow(label: "剩余低于", index: index)
                }
            }
        case .absoluteValue:
            if !rule.thresholds.isEmpty {
                HStack(spacing: 10) {
                    Text("余额低于")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    TextField("余额", value: amountBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    Text(metric?.currencyCode ?? "未提供币种")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .healthState:
            Label("账户状态变为异常时提醒", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func thresholdRow(label: String, index: Int) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(percent(at: index))%")
                .monospacedDigit()
            Stepper(
                "",
                value: percentBinding(at: index),
                in: 1...100
            )
            .labelsHidden()
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
