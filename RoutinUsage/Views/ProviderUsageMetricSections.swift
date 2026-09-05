import SwiftUI

struct VolcengineCodingPlanMetricsView: View {
    let metrics: [NormalizedUsageMetric]
    let now: Date

    private var session: NormalizedUsageMetric? { metric("fiveHour") }
    private var weekly: NormalizedUsageMetric? { metric("weekly") }
    private var monthly: NormalizedUsageMetric? { metric("monthly") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                codingQuotaCell(session, fallbackTitle: "session")
                codingQuotaCell(weekly, fallbackTitle: "weekly")
            }
            if let monthly {
                codingMonthlyCell(monthly)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codingQuotaCell(
        _ metric: NormalizedUsageMetric?,
        fallbackTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric?.label ?? fallbackTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(percentText(metric))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(color(metric))
                    .monospacedDigit()
            }
            UsageMetricProgressBar(percent: metric?.displayedPercent ?? 0)
            detailLines(metric)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func codingMonthlyCell(_ metric: NormalizedUsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(percentText(metric))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(color(metric))
                    .monospacedDigit()
            }
            UsageMetricProgressBar(percent: metric.displayedPercent ?? 0)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    amountText("已用", metric.used, metric.limit)
                    resetText(metric)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    amountText("剩余", metric.remaining, nil)
                    remainingText(metric)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailLines(_ metric: NormalizedUsageMetric?) -> some View {
        if let metric {
            amountText("已用", metric.used, metric.limit)
            amountText("剩余", metric.remaining, nil)
            resetText(metric)
            remainingText(metric)
        } else {
            Text("暂无数据")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func amountText(_ title: String, _ value: Decimal?, _ limit: Decimal?) -> some View {
        Text("\(title) \(decimalText(value))\(limit.map { " / \(decimalText($0))" } ?? "")")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func resetText(_ metric: NormalizedUsageMetric) -> some View {
        Text("重置 \(metric.windowEnd.map { UsageFormatter.resetTime($0, now: now) } ?? "—")")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func remainingText(_ metric: NormalizedUsageMetric) -> some View {
        Text("剩余 \(metric.windowEnd.map { UsageFormatter.remainingDurationText(until: $0, now: now) } ?? "—")")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ id: String) -> NormalizedUsageMetric? {
        metrics.first { $0.id == id }
    }

    private func percentText(_ metric: NormalizedUsageMetric?) -> String {
        guard let percent = metric?.displayedPercent else { return "—" }
        return "\(Int(percent.rounded()))%"
    }

    private func decimalText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private func color(_ metric: NormalizedUsageMetric?) -> Color {
        guard let metric else { return .secondary }
        switch metric.healthState {
        case .normal: return .green
        case .warning: return .orange
        case .critical, .unavailable: return .red
        case .stale, .unknown: return .secondary
        }
    }
}

/// 火山两个计划共用周期额度卡片；月度额度横跨整行，避免 Coding Plan 的第三项挤压前两项。
struct VolcenginePlanUsageMetricsView: View {
    let metrics: [NormalizedUsageMetric]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NormalizedUsageMetricGrid(
                metrics: metrics.filter { $0.presentation == .progress },
                columns: 2,
                resetTimeStyle: .relativeDuration,
                now: now
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// New API 的指标语义与订阅型供应商不同：额度有上限，消费和请求是活动统计。
struct NewAPIUsageMetricsView: View {
    let metrics: [NormalizedUsageMetric]
    let now: Date

    private var quotaMetric: NormalizedUsageMetric? {
        metric("quota-progress")
    }

    private var consumptionMetrics: [NormalizedUsageMetric] {
        [
            "today-token", "one-day-token",
            "seven-day-token", "thirty-day-token"
        ].compactMap(metric)
    }

    private var currencySymbol: String {
        quotaMetric?.currencyCode ?? consumptionMetrics.first?.currencyCode ?? "额度"
    }

    private var displaysRawQuota: Bool {
        currencySymbol == "额度"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let quotaMetric {
                quotaCard(quotaMetric)
            }

            if !consumptionMetrics.isEmpty {
                consumptionSection
            }

            activitySection
        }
    }

    private func quotaCard(_ metric: NormalizedUsageMetric) -> some View {
        let percent = metric.displayedPercent ?? 0
        let percentText = metric.limit == 0 ? "—" : "\(Int(percent.rounded()))%"

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                Text(percentText)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(healthColor(metric.healthState))
                    .monospacedDigit()
            }

            UsageMetricProgressBar(percent: percent)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("已用 \(quotaText(metric.used)) / \(quotaText(metric.limit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Text("剩余 \(quotaText(metric.remaining))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(metric.label)，已使用 \(percentText)，已用 \(quotaText(metric.used))，剩余 \(quotaText(metric.remaining))"
        )
    }

    private var consumptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Token 消耗")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                Text("单位 Token")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(consumptionMetrics.prefix(2))) { metric in
                        consumptionCell(metric)
                    }
                }

                GridRow {
                    ForEach(Array(consumptionMetrics.dropFirst(2))) { metric in
                        consumptionCell(metric)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func consumptionCell(_ metric: NormalizedUsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(UsageFormatter.exactTokenText(metric.value))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("≈ \(costText(for: metric))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label)，\(UsageFormatter.exactTokenText(metric.value))，约 \(costText(for: metric))")
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("请求活动")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    activityCell(
                        label: "RPM",
                        value: metric("rpm")?.value,
                        detail: "近 60 秒请求"
                    )

                    activityCell(
                        label: "TPM",
                        value: metric("tpm")?.value,
                        detail: "近 60 秒 Token"
                    )

                    activityCell(
                        label: "账户累计请求",
                        value: metric("request-count")?.value,
                        detail: "当前用户全部 API 请求"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityCell(
        label: String,
        value: Decimal?,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(UsageFormatter.compactMetricValue(value))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，\(UsageFormatter.compactMetricValue(value))，\(detail)")
    }

    private func costText(for metric: NormalizedUsageMetric) -> String {
        let costMetric = self.metric("\(metric.id)-cost")
        guard let costMetric else { return "—" }
        return UsageFormatter.currencyText(costMetric.value, symbol: costMetric.currencyCode ?? "¥")
    }

    private func quotaText(_ value: Decimal?) -> String {
        if displaysRawQuota {
            return UsageFormatter.compactMetricValue(value)
        }
        return UsageFormatter.currencyText(value, symbol: currencySymbol)
    }

    private func metric(_ id: String) -> NormalizedUsageMetric? {
        metrics.first(where: { $0.id == id })
    }

    private func healthColor(_ state: UsageMetricHealthState) -> Color {
        switch state {
        case .normal: return .green
        case .warning: return .orange
        case .critical, .unavailable: return .red
        case .stale, .unknown: return .secondary
        }
    }
}

/// GLM 的两个调用量是无上限统计，展示为标准“标签 + 右对齐数值”行。
struct GLMUsageMetricsView: View {
    let metrics: [NormalizedUsageMetric]
    let now: Date

    private var progressMetrics: [NormalizedUsageMetric] {
        metrics.filter { $0.presentation == .progress }
    }

    private var callMetrics: [NormalizedUsageMetric] {
        ["model-calls", "zcode-mcp"].compactMap { id in
            metrics.first(where: { $0.id == id && $0.presentation == .value })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !progressMetrics.isEmpty {
                NormalizedUsageMetricGrid(
                    metrics: progressMetrics,
                    columns: 2,
                    resetTimeStyle: .relativeDuration,
                    now: now,
                    showsAmountDetails: false
                )
            }

            if !callMetrics.isEmpty {
                Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        callCell(callMetrics[safe: 0])
                        callCell(callMetrics[safe: 1])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func callCell(_ metric: NormalizedUsageMetric?) -> some View {
        if let metric {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                Text("\(UsageFormatter.compactMetricValue(metric.value)) 次")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metric.label)，\(UsageFormatter.compactMetricValue(metric.value)) 次")
        } else {
            Color.clear
        }
    }
}

private extension Array {
    subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
