import SwiftUI

struct UsageMetricGridLayout: Equatable {
    let metrics: [NormalizedUsageMetric]
    let columns: Int
    var showsAmountDetails: Bool = true
}

enum NormalizedUsageMetricResetStyle {
    case fullDateTime
    case relativeDuration
}

enum UsageMetricGridPolicy {
    static func layout(
        providerID: ProviderID,
        metrics: [NormalizedUsageMetric]
    ) -> UsageMetricGridLayout {
        switch providerID {
        case .glm:
            return UsageMetricGridLayout(
                metrics: metrics,
                columns: 2,
                showsAmountDetails: false
            )
        case .volcengine:
            return UsageMetricGridLayout(metrics: metrics, columns: 2)
        case .deepseek:
            return UsageMetricGridLayout(metrics: metrics, columns: 2)
        case .routin:
            return UsageMetricGridLayout(metrics: metrics, columns: 2)
        case .newAPI:
            return UsageMetricGridLayout(metrics: metrics, columns: 2)
        case .commandCode:
            return UsageMetricGridLayout(metrics: metrics, columns: 2)
        }
    }
}

struct NormalizedUsageMetricGrid: View {
    let metrics: [NormalizedUsageMetric]
    let columns: Int
    var resetTimeStyle: NormalizedUsageMetricResetStyle = .fullDateTime
    var now: Date = .now
    var showsAmountDetails: Bool = true

    var body: some View {
        let rows = stride(from: 0, to: metrics.count, by: columns).map {
            Array(metrics[$0..<min($0 + columns, metrics.count)])
        }

        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.count == 1, let metric = row.first, metric.id == "monthly" {
                    NormalizedUsageMetricCell(
                        metric: metric,
                        resetTimeStyle: resetTimeStyle,
                        now: now,
                        showsAmountDetails: showsAmountDetails,
                        spansAllColumns: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<columns, id: \.self) { columnIndex in
                            if columnIndex < row.count {
                                NormalizedUsageMetricCell(
                                    metric: row[columnIndex],
                                    resetTimeStyle: resetTimeStyle,
                                    now: now,
                                    showsAmountDetails: showsAmountDetails
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct NormalizedUsageMetricCell: View {
    let metric: NormalizedUsageMetric
    let resetTimeStyle: NormalizedUsageMetricResetStyle
    let now: Date
    var showsAmountDetails: Bool = true
    var spansAllColumns: Bool = false

    var body: some View {
        switch metric.presentation {
        case .progress:
            progressCell
        case .balance:
            balanceCell
        case .status:
            statusCell
        case .value:
            valueCell
        }
    }

    private var progressCell: some View {
        let percent = metric.displayedPercent ?? 0
        let percentText = "\(Int(percent.rounded()))%"
        let usesFullWidthDetails = spansAllColumns || metric.id == "monthly"

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text(percentText)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(healthColor)
                    .monospacedDigit()
            }

            UsageMetricProgressBar(percent: percent)

            if showsAmountDetails, let used = metric.used, let limit = metric.limit {
                if usesFullWidthDetails {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("已用 \(decimalText(used)) / \(decimalText(limit))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        if let remaining = metric.remaining {
                            Text("剩余 \(decimalText(remaining))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("已用 \(decimalText(used)) / \(decimalText(limit))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)

                    if let remaining = metric.remaining {
                        Text("剩余 \(decimalText(remaining))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            if let windowEnd = metric.windowEnd {
                switch resetTimeStyle {
                case .fullDateTime:
                    Text("重置 \(UsageFormatter.fullDateTime(windowEnd))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                case .relativeDuration:
                    if usesFullWidthDetails {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("重置 \(UsageFormatter.resetTime(windowEnd, now: now))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                                .help("重置 \(UsageFormatter.fullDateTime(windowEnd))")

                            Spacer(minLength: 12)

                            Text("剩余 \(UsageFormatter.remainingDurationText(until: windowEnd, now: now))")
                                .font(.caption2)
                                .foregroundStyle(
                                    UsageFormatter.shouldHighlightRemainingDuration(
                                        for: metric,
                                        now: now
                                    ) ? Color.green : Color.secondary
                                )
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("重置 \(UsageFormatter.resetTime(windowEnd, now: now))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .help("重置 \(UsageFormatter.fullDateTime(windowEnd))")

                        Text("剩余 \(UsageFormatter.remainingDurationText(until: windowEnd, now: now))")
                            .font(.caption2)
                            .foregroundStyle(
                                UsageFormatter.shouldHighlightRemainingDuration(
                                    for: metric,
                                    now: now
                                ) ? Color.green : Color.secondary
                            )
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.label)，已使用 \(percentText)，剩余 \(decimalText(metric.remaining))"
        )
    }

    @ViewBuilder
    private var balanceCell: some View {
        if isDeepSeekSummary {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(decimalText(metric.value)) \(metric.currencyCode ?? "元")")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(healthColor)
                    .monospacedDigit()
                    .lineLimit(1)

                Text("账户余额")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("账户余额，\(decimalText(metric.value)) \(metric.currencyCode ?? "元")")
        } else {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text("\(decimalText(metric.value)) \(metric.currencyCode ?? "元")")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(healthColor)
                    .monospacedDigit()
            }
            Text("账户余额")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.label)，\(decimalText(metric.value)) \(metric.currencyCode ?? "元")"
        )
        }
    }

    @ViewBuilder
    private var statusCell: some View {
        if isDeepSeekSummary {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.healthState == .unavailable ? "不可用" : "可用")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(metric.healthState == .unavailable ? Color.red : Color.primary)
                    .lineLimit(1)

                Text("账户状态")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("账户状态，\(metric.healthState == .unavailable ? "不可用" : "可用")")
        } else {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text(metric.healthState == .unavailable ? "不可用" : "可用")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(healthColor)
            }
            Text("账户状态")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.label)，\(metric.healthState == .unavailable ? "不可用" : "可用")"
        )
        }
    }

    @ViewBuilder
    private var valueCell: some View {
        if isDeepSeekSummary {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(decimalText(metric.value))\(valueSuffix)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(healthColor)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(metric.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text("\(decimalText(metric.value))\(valueSuffix)")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metric.label)，\(decimalText(metric.value))\(valueSuffix)")
        }
    }

    private var valueSuffix: String {
        switch metric.unit {
        case .request:
            return " 次"
        case .currency:
            return " \(metric.currencyCode ?? "元")"
        case .token, .boolean, .text:
            return ""
        }
    }

    private var isDeepSeekSummary: Bool {
        ["balance", "grantedBalance", "toppedUpBalance", "availability"].contains(metric.id)
    }

    private var healthColor: Color {
        switch metric.healthState {
        case .normal: return .green
        case .warning: return .orange
        case .critical, .unavailable: return .red
        case .stale, .unknown: return .secondary
        }
    }

    private func decimalText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return NSDecimalNumber(decimal: value).stringValue
    }
}
