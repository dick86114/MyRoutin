import Foundation

enum UsageFormatter {
    struct GroupMultiplierSegment: Equatable, Sendable {
        let text: String
        let isHighlighted: Bool
    }
    static func menuBarText(
        state: KeyUsageState?,
        dimension: DisplayDimension
    ) -> String {
        menuBarText(state: state, dimension: dimension, style: .percent)
    }

    static func menuBarText(
        state: KeyUsageState?,
        dimension: DisplayDimension,
        style: MenuBarStyle
    ) -> String {
        guard let state else {
            return "--"
        }
        guard let snapshot = state.snapshot else {
            if state.error == .noSubscription {
                return "--"
            }
            if state.error != nil {
                return "!"
            }
            return "…"
        }
        guard let metric = metric(in: snapshot, dimension: dimension) else {
            return "--"
        }
        guard let percent = percentText(metric) else {
            return "!"
        }
        if snapshot.kind == .tokenPack {
            return percent
        }
        switch style {
        case .percent:
            return percent
        case .aliasPercent:
            return "\(truncatedMenuBarAlias(state.configuration.displayName)) \(percent)"
        case .aliasLogoProgress, .aliasVerticalBar:
            return truncatedMenuBarAlias(state.configuration.displayName)
        case .logoProgress:
            return ""
        }
    }

    static func truncatedMenuBarAlias(_ alias: String) -> String {
        guard alias.count > 5 else {
            return alias
        }
        return String(alias.prefix(5)) + "…"
    }

    static func amount(_ metric: UsageMetric) -> String {
        "\(formatted(metric.used, unit: metric.unit)) / "
            + formatted(metric.limit, unit: metric.unit)
    }

    static func remaining(_ metric: UsageMetric) -> String {
        formatted(metric.remaining, unit: metric.unit)
    }

    /// 用于额度、调用量等统一指标的紧凑展示，避免弹窗里出现过长数字。
    static func compactMetricValue(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return compactMetricValue(value)
    }

    static func fullAmount(_ metric: UsageMetric) -> String {
        guard metric.unit == .token else {
            return amount(metric)
        }
        return "\(fullToken(metric.used)) / \(fullToken(metric.limit)) Token"
    }

    static func resetTime(
        _ metric: UsageMetric,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        resetTime(metric.windowEnd, now: now, timeZone: timeZone)
    }

    static func resetTime(
        _ windowEnd: Date?,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        guard let windowEnd else {
            return "--"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.isDate(windowEnd, inSameDayAs: now)
            ? "HH:mm"
            : "MM-dd HH:mm"
        return formatter.string(from: windowEnd)
    }

    /// 将窗口绝对结束时间换算为从当前时刻起的剩余时长。
    static func remainingDurationText(until end: Date, now: Date) -> String {
        guard end > now else {
            return "已结束"
        }

        let totalMinutes = max(1, Int(end.timeIntervalSince(now) / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)天")
        }
        if hours > 0 {
            parts.append("\(hours)小时")
        }
        if minutes > 0 || parts.isEmpty {
            parts.append("\(minutes)分钟")
        }
        return parts.joined(separator: " ")
    }

    static func shouldHighlightRemainingDuration(
        for metric: UsageMetric,
        dimension: UsageDimension,
        now: Date
    ) -> Bool {
        guard let end = metric.windowEnd, end > now else {
            return false
        }
        switch dimension {
        case .fiveHour:
            return end.timeIntervalSince(now) < 60 * 60
        case .weekly:
            return end.timeIntervalSince(now) < 24 * 60 * 60
        case .token:
            return false
        case .balance:
            return false
        }
    }

    /// 通用指标没有显式维度，这里按供应商约定 ID 和中文标签识别周期。
    static func normalizedDimension(for metric: NormalizedUsageMetric) -> UsageDimension? {
        let identifier = metric.id
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        if identifier == "fivehour" || metric.label.contains("5 小时") || metric.label.contains("5小时") {
            return .fiveHour
        }
        if identifier == "weekly" || metric.label.contains("周") {
            return .weekly
        }
        return nil
    }

    static func shouldHighlightRemainingDuration(
        for metric: NormalizedUsageMetric,
        now: Date
    ) -> Bool {
        guard let end = metric.windowEnd, end > now else {
            return false
        }

        return end.timeIntervalSince(now) < 60 * 60
    }

    /// 在用量行中使用紧凑的本地订阅日期时间。
    static func subscriptionDateText(
        _ date: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 仅在订阅结束时间进入未来七天时显示到期提示。
    static func subscriptionExpiryText(until end: Date?, now: Date) -> String? {
        guard let end else {
            return nil
        }
        let interval = end.timeIntervalSince(now)
        if interval <= 0 {
            return "（已过期）"
        }
        if interval < 60 * 60 {
            let minutes = max(1, Int(interval / 60))
            return "（\(minutes)分钟后到期）"
        }
        if interval < 24 * 60 * 60 {
            let hours = max(1, Int(interval / (60 * 60)))
            return "（\(hours)小时后到期）"
        }
        let days = Int(interval / (24 * 60 * 60))
        guard days < 7 else {
            return nil
        }
        return "（\(max(days, 1))天后到期）"
    }

    /// 用于设置页和详情面板的完整本地时间；没有时间时统一显示占位符。
    static func fullDateTime(
        _ date: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 将已按名称配对的分组倍率合并为单行文本。
    static func groupMultiplierText(_ groups: [UsageGroupMultiplier]) -> String {
        groups.map { group in
            "\(group.name) ×\(NSDecimalNumber(decimal: group.multiplier).stringValue)"
        }
        .joined(separator: "、")
    }

    static func currentGroupMultiplier(
        in groups: [UsageGroupMultiplier],
        matching groupName: String?
    ) -> UsageGroupMultiplier? {
        guard let groupName else {
            return nil
        }
        return groups.first { $0.name == groupName }
    }

    static func groupMultiplierSegments(
        _ groups: [UsageGroupMultiplier],
        highlightedGroupName: String?
    ) -> [GroupMultiplierSegment] {
        groups.map { group in
            GroupMultiplierSegment(
                text: "\(group.name) ×\(NSDecimalNumber(decimal: group.multiplier).stringValue)",
                isHighlighted: group.name == highlightedGroupName
            )
        }
    }

    /// 以完整日期时间显示窗口结束时刻，便于跨天查看。
    static func windowEndDescription(
        _ metric: UsageMetric,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let windowEnd = metric.windowEnd else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: windowEnd)
    }

    static func metric(
        in snapshot: UsageSnapshot,
        dimension: DisplayDimension
    ) -> UsageMetric? {
        if snapshot.kind == .tokenPack {
            return snapshot.token
        }
        switch dimension {
        case .fiveHour:
            return snapshot.fiveHour
        case .weekly:
            return snapshot.weekly
        }
    }

    static func percentText(_ metric: UsageMetric) -> String? {
        guard metric.percent.isFinite,
              let roundedPercent = Int(exactly: metric.percent.rounded()) else {
            return nil
        }
        return "\(roundedPercent)%"
    }

    static func statusText(
        state: KeyUsageState,
        dimension: DisplayDimension? = nil
    ) -> String {
        if let dimension,
           let snapshot = state.snapshot,
           let metric = metric(in: snapshot, dimension: dimension),
           percentText(metric) == nil {
            return "用量数据异常"
        }
        if state.isRefreshing {
            return state.snapshot == nil ? "正在加载" : "正在刷新，当前显示上次数据"
        }
        if state.isStale, state.snapshot != nil {
            guard let error = state.error else {
                return "缓存已过期"
            }
            return "缓存已过期，\(errorText(error))"
        }
        if let error = state.error {
            if state.snapshot != nil {
                return "刷新失败，暂显示上次数据：\(errorText(error))"
            }
            return errorText(error)
        }
        return state.snapshot == nil ? "等待首次刷新" : "用量数据可用"
    }

    /// New API 站点可能把内部 quota 换算为 CNY/USD 等展示单位；这里统一保留两位小数。
    static func currencyText(_ value: Decimal?, symbol: String) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
        return symbol + text
    }

    /// Token 消耗需要保留完整数值，避免 compact 格式让用户无法核对后台总量。
    static func exactTokenText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
        return text
    }
}

private extension UsageFormatter {
    static let stableLocale = Locale(identifier: "en_US_POSIX")

    static func formatted(_ value: Decimal, unit: UsageUnit) -> String {
        switch unit {
        case .usd:
            return String(
                format: "$%.2f",
                locale: stableLocale,
                NSDecimalNumber(decimal: value).doubleValue
            )
        case .token:
            return compactToken(value)
        }
    }

    static func compactToken(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let absolute = abs(number)
        let scaled: Double
        let suffix: String
        if absolute >= 1_000_000_000 {
            scaled = number / 1_000_000_000
            suffix = "B"
        } else if absolute >= 1_000_000 {
            scaled = number / 1_000_000
            suffix = "M"
        } else if absolute >= 1_000 {
            scaled = number / 1_000
            suffix = "K"
        } else {
            scaled = number
            suffix = ""
        }
        let text = String(format: "%.1f", locale: stableLocale, scaled)
        return text.replacingOccurrences(of: ".0", with: "") + suffix
    }

    static func compactMetricValue(_ value: Decimal) -> String {
        compactToken(value)
    }

    static func fullToken(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = stableLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func errorText(_ error: UsageDisplayError) -> String {
        switch error {
        case .noSubscription:
            return "当前没有可用订阅"
        case .invalidKey:
            return "Key 无效"
        case .network:
            return "网络错误，将自动重试"
        case .invalidResponse:
            return "接口数据异常，请刷新重试"
        case let .server(statusCode):
            return "服务器错误（\(statusCode)），请稍后重试"
        }
    }
}
