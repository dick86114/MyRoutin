import SwiftUI

struct CommandCodeMetricLayout: Equatable {
    let fiveHour: NormalizedUsageMetric?
    let weekly: NormalizedUsageMetric?
    let monthly: NormalizedUsageMetric?
    let requestCount: NormalizedUsageMetric?
    let purchasedRemaining: NormalizedUsageMetric?
    let freeRemaining: NormalizedUsageMetric?

    var displayedMetrics: [NormalizedUsageMetric] {
        [
            fiveHour,
            weekly,
            monthly,
            requestCount,
            purchasedRemaining,
            freeRemaining
        ].compactMap { $0 }
    }
}

enum CommandCodeMetricLayoutPolicy {
    struct ProgressDetailLine: Equatable {
        let text: String
        let highlights: Bool

        init(text: String, highlights: Bool = false) {
            self.text = text
            self.highlights = highlights
        }
    }

    static func progressDetailLines(
        for metric: NormalizedUsageMetric,
        now: Date
    ) -> [ProgressDetailLine] {
        var lines = [
            ProgressDetailLine(
                text: "已用 \(CommandCodeMetricFormatter.amount(metric.used)) / \(CommandCodeMetricFormatter.amount(metric.limit))"
            ),
            ProgressDetailLine(
                text: "剩余 \(CommandCodeMetricFormatter.amount(metric.remaining))"
            )
        ]
        if let windowEnd = metric.windowEnd {
            lines.append(ProgressDetailLine(
                text: "重置 \(UsageFormatter.resetTime(windowEnd, now: now))"
            ))
            lines.append(ProgressDetailLine(
                text: "剩余 \(UsageFormatter.remainingDurationText(until: windowEnd, now: now))",
                highlights: UsageFormatter.shouldHighlightRemainingDuration(
                    for: metric,
                    now: now
                )
            ))
        }
        return lines
    }

    static func layout(metrics: [NormalizedUsageMetric]) -> CommandCodeMetricLayout {
        CommandCodeMetricLayout(
            fiveHour: metric(id: "five-hour", in: metrics),
            weekly: metric(id: "weekly", in: metrics),
            monthly: metric(id: "credit-progress", in: metrics),
            requestCount: metric(id: "request-count", in: metrics),
            purchasedRemaining: metric(id: "purchased-remaining", in: metrics),
            freeRemaining: metric(id: "free-remaining", in: metrics)
        )
    }

    private static func metric(
        id: String,
        in metrics: [NormalizedUsageMetric]
    ) -> NormalizedUsageMetric? {
        metrics.first { $0.id == id }
    }
}

enum CommandCodeMetricFormatter {
    static func amount(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return formatted(value, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    static func number(_ value: Decimal?) -> String {
        UsageFormatter.numberText(value)
    }

    private static func formatted(
        _ value: Decimal,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

struct CommandCodeUsageMetricsView: View {
    let metrics: [NormalizedUsageMetric]
    let now: Date

    private var layout: CommandCodeMetricLayout {
        CommandCodeMetricLayoutPolicy.layout(metrics: metrics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                progressCell(layout.fiveHour, fallbackLabel: "5 小时")
                progressCell(layout.weekly, fallbackLabel: "周")
            }

            HStack(alignment: .top, spacing: 16) {
                monthlyCell(layout.monthly)
                summaryMetricsCell
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryMetricsCell: some View {
        HStack(alignment: .top, spacing: 12) {
            requestCountCell(layout.requestCount)
            valueCell(layout.purchasedRemaining, fallbackLabel: "购买剩余")
            valueCell(layout.freeRemaining, fallbackLabel: "赠送剩余")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func progressCell(
        _ metric: NormalizedUsageMetric?,
        fallbackLabel: String
    ) -> some View {
        if let metric {
            VStack(alignment: .leading, spacing: 5) {
                cellHeader(metric, fallbackLabel: fallbackLabel)
                UsageMetricProgressBar(percent: metric.displayedPercent ?? 0)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(CommandCodeMetricLayoutPolicy.progressDetailLines(for: metric, now: now), id: \.text) { line in
                        Text(line.text)
                            .foregroundStyle(line.highlights ? Color.green : Color.secondary)
                    }
                }
                .font(.caption2)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            placeholderCell(label: fallbackLabel)
        }
    }

    @ViewBuilder
    private func monthlyCell(_ metric: NormalizedUsageMetric?) -> some View {
        if let metric {
            VStack(alignment: .leading, spacing: 5) {
                cellHeader(metric, fallbackLabel: "月")
                UsageMetricProgressBar(percent: metric.displayedPercent ?? 0)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("已用 \(amountText(metric.used))")
                    Spacer(minLength: 12)
                    Text("剩余 \(amountText(metric.remaining))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            placeholderCell(label: "月")
        }
    }

    @ViewBuilder
    private func requestCountCell(_ metric: NormalizedUsageMetric?) -> some View {
        if let metric {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.label.isEmpty ? "累计请求" : metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(numberText(metric.value)) 次")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(metric.label)，\(numberText(metric.value)) 次"
            )
        } else {
            placeholderCell(label: "累计请求")
        }
    }

    @ViewBuilder
    private func valueCell(
        _ metric: NormalizedUsageMetric?,
        fallbackLabel: String
    ) -> some View {
        if let metric {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.label.isEmpty ? fallbackLabel : metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(amountText(metric.value)) \(currencyText(metric))")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(color(metric.healthState))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(metric.label)，\(amountText(metric.value)) \(currencyText(metric))"
            )
        } else {
            placeholderCell(label: fallbackLabel)
        }
    }

    private func cellHeader(
        _ metric: NormalizedUsageMetric,
        fallbackLabel: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(metric.label.isEmpty ? fallbackLabel : metric.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            Text(percentText(metric))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(color(metric.healthState))
                .monospacedDigit()
        }
    }

    private func placeholderCell(label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("—")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentText(_ metric: NormalizedUsageMetric) -> String {
        UsageFormatter.displayPercentText(metric.displayedPercent)
    }

    private func amountText(_ value: Decimal?) -> String {
        CommandCodeMetricFormatter.amount(value)
    }

    private func numberText(_ value: Decimal?) -> String {
        CommandCodeMetricFormatter.number(value)
    }

    private func currencyText(_ metric: NormalizedUsageMetric) -> String {
        metric.currencyCode ?? "元"
    }

    private func color(_ state: UsageMetricHealthState) -> Color {
        switch state {
        case .normal: return .green
        case .warning: return .orange
        case .critical, .unavailable: return .red
        case .stale, .unknown: return .secondary
        }
    }
}
