import AppKit
import Foundation
import XCTest
@testable import RoutinUsage

final class UsageFormatterTests: XCTestCase {
    func test统一指标数值使用紧凑格式() {
        XCTAssertEqual(UsageFormatter.compactMetricValue(120_000), "120K")
        XCTAssertEqual(UsageFormatter.compactMetricValue(4_500), "4.5K")
        XCTAssertEqual(UsageFormatter.compactMetricValue(42), "42")
        XCTAssertEqual(UsageFormatter.compactMetricValue(nil), "—")
    }

    func testNewAPI货币单位保留两位小数() {
        XCTAssertEqual(
            UsageFormatter.currencyText(Decimal(string: "1000.602"), symbol: "¥"),
            "¥1000.60"
        )
        XCTAssertEqual(
            UsageFormatter.currencyText(Decimal(string: "43607.129"), symbol: "¥"),
            "¥43607.13"
        )
    }

    func testToken统计保留千分位完整数值() {
        XCTAssertEqual(
            UsageFormatter.exactTokenText(7_362_665),
            "7,362,665"
        )
        XCTAssertEqual(UsageFormatter.exactTokenText(nil), "—")
    }

    func test分组倍率分段仅精确匹配检测分组() {
        let segments = UsageFormatter.groupMultiplierSegments(
            [
                UsageGroupMultiplier(name: "Codex", multiplier: 1.5),
                UsageGroupMultiplier(name: "Codex Pro", multiplier: 2)
            ],
            highlightedGroupName: "Codex"
        )

        XCTAssertEqual(segments.map(\.text), ["Codex ×1.5", "Codex Pro ×2"])
        XCTAssertEqual(segments.map(\.isHighlighted), [true, false])
    }

    func test仅返回检测到的当前分组倍率() {
        let groups = [
            UsageGroupMultiplier(name: "XAI 低价", multiplier: 0.5),
            UsageGroupMultiplier(name: "Codex", multiplier: 1),
            UsageGroupMultiplier(name: "Codex Pro", multiplier: 2)
        ]

        XCTAssertEqual(
            UsageFormatter.currentGroupMultiplier(in: groups, matching: "Codex"),
            UsageGroupMultiplier(name: "Codex", multiplier: 1)
        )
        XCTAssertNil(UsageFormatter.currentGroupMultiplier(in: groups, matching: nil))
        XCTAssertNil(UsageFormatter.currentGroupMultiplier(in: groups, matching: "不存在"))
    }

    func test临近重置的窗口将剩余时间标为绿色() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let fiveHour = makeMetric(
            used: 1,
            limit: 10,
            remaining: 9,
            unit: .usd,
            windowEnd: now.addingTimeInterval(59 * 60)
        )
        let weekly = makeMetric(
            used: 1,
            limit: 10,
            remaining: 9,
            unit: .usd,
            windowEnd: now.addingTimeInterval(23 * 60 * 60)
        )

        XCTAssertTrue(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: fiveHour,
                dimension: .fiveHour,
                now: now
            )
        )
        XCTAssertTrue(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: weekly,
                dimension: .weekly,
                now: now
            )
        )
        XCTAssertFalse(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: makeMetric(
                    used: 1,
                    limit: 10,
                    remaining: 9,
                    unit: .usd,
                    windowEnd: now.addingTimeInterval(60 * 60)
                ),
                dimension: .fiveHour,
                now: now
            )
        )
        XCTAssertFalse(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: makeMetric(
                    used: 1,
                    limit: 10,
                    remaining: 9,
                    unit: .usd,
                    windowEnd: now.addingTimeInterval(24 * 60 * 60)
                ),
                dimension: .weekly,
                now: now
            )
        )
    }
    @MainActor
    func test菜单栏独立竖条图像有效渲染() {
        let image = MenuBarVerticalUsageIcon.image(percent: 35)

        XCTAssertEqual(image.size.width, 7)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertTrue(image.isTemplate)
    }

    @MainActor
    func test菜单栏Logo进度图标使用品牌轮廓和填充蒙版() {
        let image = MenuBarLogoUsageIcon.image(percent: 35)

        XCTAssertEqual(image.size.width, 18)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertTrue(image.isTemplate)
        XCTAssertNotNil(NSImage(named: "MenuBarLogoOutline"))
        XCTAssertNotNil(NSImage(named: "MenuBarLogoMask"))
    }

    @MainActor
    func test菜单栏把百分比四舍五入为整数() {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "68%"
        )
    }

    func test首次加载显示省略号() {
        let state = makeState(snapshot: nil, isRefreshing: true)

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "…"
        )
    }

    func test无订阅显示双短横线() {
        let state = makeState(snapshot: nil, error: .noSubscription)

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "--"
        )
    }

    func test无缓存请求错误显示感叹号() {
        let state = makeState(snapshot: nil, error: .network)

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "!"
        )
    }

    func test资源包在周维度仍显示Token百分比() {
        let state = makeState(snapshot: makeTokenSnapshot(percent: 92.4))

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .weekly),
            "92%"
        )
    }

    func test菜单栏别名超长时截断为前五个字符加省略号() {
        XCTAssertEqual(UsageFormatter.truncatedMenuBarAlias("主账号名称很长"), "主账号名称…")
        XCTAssertEqual(UsageFormatter.truncatedMenuBarAlias("主账号"), "主账号")
    }

    func test菜单栏别名百分比样式返回别名和百分比() {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))

        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: state,
                dimension: .fiveHour,
                style: .aliasPercent
            ),
            "主账号 68%"
        )
    }

    func test菜单栏别名竖线样式有效时返回别名加载时返回省略号() {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))
        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: state,
                dimension: .fiveHour,
                style: .aliasVerticalBar
            ),
            "主账号"
        )

        let loadingState = makeState(snapshot: nil, isRefreshing: true)
        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: loadingState,
                dimension: .fiveHour,
                style: .aliasVerticalBar
            ),
            "…"
        )
    }

    func test菜单栏别名Logo进度样式有效时返回别名加载时返回省略号() {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))
        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: state,
                dimension: .fiveHour,
                style: .aliasLogoProgress
            ),
            "主账号"
        )

        let loadingState = makeState(snapshot: nil, isRefreshing: true)
        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: loadingState,
                dimension: .fiveHour,
                style: .aliasLogoProgress
            ),
            "…"
        )
    }

    func test菜单栏仅Logo进度样式有效时不显示别名() {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))

        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: state,
                dimension: .fiveHour,
                style: .logoProgress
            ),
            ""
        )
    }

    func test菜单栏别名竖线样式资源包仍返回Token百分比() {
        let state = makeState(snapshot: makeTokenSnapshot(percent: 92.4))

        XCTAssertEqual(
            UsageFormatter.menuBarText(
                state: state,
                dimension: .weekly,
                style: .aliasVerticalBar
            ),
            "92%"
        )
    }

    func test菜单栏竖条风险等级在50和80分界() {
        XCTAssertEqual(MenuBarUsageRisk.level(for: 49.9), .normal)
        XCTAssertEqual(MenuBarUsageRisk.level(for: 50), .warning)
        XCTAssertEqual(MenuBarUsageRisk.level(for: 79.9), .warning)
        XCTAssertEqual(MenuBarUsageRisk.level(for: 80), .critical)
    }

    func test菜单栏为竖条和Logo进度样式提供有效周期指标() throws {
        let periodicState = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))

        XCTAssertEqual(
            try XCTUnwrap(
                MenuBarVerticalUsage.metric(
                    state: periodicState,
                    dimension: .fiveHour,
                    style: .aliasVerticalBar
                )
            ).percent,
            67.5
        )
        XCTAssertEqual(
            try XCTUnwrap(
                MenuBarVerticalUsage.metric(
                    state: periodicState,
                    dimension: .fiveHour,
                    style: .logoProgress
                )
            ).percent,
            67.5
        )
        XCTAssertNil(
            MenuBarVerticalUsage.metric(
                state: periodicState,
                dimension: .fiveHour,
                style: .percent
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                MenuBarVerticalUsage.metric(
                    state: periodicState,
                    dimension: .fiveHour,
                    style: .aliasLogoProgress
                )
            ).percent,
            67.5
        )
        XCTAssertNil(
            MenuBarVerticalUsage.metric(
                state: makeState(snapshot: nil, isRefreshing: true),
                dimension: .fiveHour,
                style: .aliasVerticalBar
            )
        )
        XCTAssertNil(
            MenuBarVerticalUsage.metric(
                state: makeState(snapshot: nil, error: .network),
                dimension: .fiveHour,
                style: .aliasVerticalBar
            )
        )
        XCTAssertNil(
            MenuBarVerticalUsage.metric(
                state: makeState(snapshot: makeTokenSnapshot(percent: 92.4)),
                dimension: .weekly,
                style: .aliasVerticalBar
            )
        )
    }

    func test分组倍率合并为一行() {
        XCTAssertEqual(
            UsageFormatter.groupMultiplierText([
                UsageGroupMultiplier(name: "Codex", multiplier: 1),
                UsageGroupMultiplier(name: "Codex Pro", multiplier: 2),
            ]),
            "Codex ×1、Codex Pro ×2"
        )
    }

    func test倒计时在一分钟后使用新时刻更新文本() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let end = now.addingTimeInterval(3 * 60 * 60 + 45 * 60)

        XCTAssertEqual(UsageFormatter.remainingDurationText(until: end, now: now), "3小时 45分钟")
        XCTAssertEqual(
            UsageFormatter.remainingDurationText(until: end, now: now.addingTimeInterval(60)),
            "3小时 44分钟"
        )
    }

    func test存在缓存且刷新失败继续显示缓存百分比() {
        let state = makeState(
            snapshot: makePeriodicSnapshot(fiveHourPercent: 81.2),
            isStale: true,
            error: .network
        )

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "81%"
        )
    }

    func test缓存仍新鲜但刷新失败时说明暂显示上次数据() {
        let state = makeState(
            snapshot: makePeriodicSnapshot(fiveHourPercent: 81.2),
            error: .network
        )

        XCTAssertEqual(
            UsageFormatter.statusText(state: state),
            "刷新失败，暂显示上次数据：网络错误，将自动重试"
        )
    }

    func test刷新进行中优先说明当前显示上次数据() {
        let state = makeState(
            snapshot: makePeriodicSnapshot(fiveHourPercent: 81.2),
            isRefreshing: true,
            isStale: true,
            error: .network
        )

        XCTAssertEqual(
            UsageFormatter.statusText(state: state),
            "正在刷新，当前显示上次数据"
        )
    }

    func test美元金额固定显示两位小数() {
        let metric = makeMetric(used: 6.8, limit: 10, remaining: 3.2, unit: .usd)

        XCTAssertEqual(UsageFormatter.amount(metric), "$6.80 / $10.00")
        XCTAssertEqual(UsageFormatter.remaining(metric), "$3.20")
    }

    func testToken金额使用紧凑缩写且去除无意义小数() {
        let metric = makeMetric(
            used: 9_200_000,
            limit: 10_000_000,
            remaining: 800_000,
            unit: .token
        )

        XCTAssertEqual(UsageFormatter.amount(metric), "9.2M / 10M")
        XCTAssertEqual(UsageFormatter.remaining(metric), "800K")
        XCTAssertEqual(
            UsageFormatter.fullAmount(metric),
            "9,200,000 / 10,000,000 Token"
        )
    }

    func test重置时间在同一天使用显式时区仅显示时分() {
        let 时区 = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let metric = makeMetric(
            used: 1,
            limit: 10,
            remaining: 9,
            unit: .usd,
            windowEnd: Date(timeIntervalSince1970: 1_786_341_600)
        )

        XCTAssertEqual(UsageFormatter.resetTime(metric, now: now, timeZone: 时区), "14:00")
    }

    func test重置时间跨日时显示日期和时分() {
        let 时区 = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let metric = makeMetric(
            used: 1,
            limit: 10,
            remaining: 9,
            unit: .usd,
            windowEnd: Date(timeIntervalSince1970: 1_786_406_400)
        )

        XCTAssertEqual(
            UsageFormatter.resetTime(metric, now: now, timeZone: 时区),
            "08-11 08:00"
        )
    }

    func test缺少重置时间显示双短横线() {
        let metric = makeMetric(used: 1, limit: 10, remaining: 9, unit: .usd)

        XCTAssertEqual(UsageFormatter.resetTime(metric), "--")
    }

    func test剩余时长在一天内显示小时和分钟() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let interval: TimeInterval = 13_500
        let end = now.addingTimeInterval(interval)

        XCTAssertEqual(
            UsageFormatter.remainingDurationText(until: end, now: now),
            "3小时 45分钟"
        )
    }

    func test剩余时长跨天显示天小时和分钟() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let interval: TimeInterval = 359_100
        let end = now.addingTimeInterval(interval)

        XCTAssertEqual(
            UsageFormatter.remainingDurationText(until: end, now: now),
            "4天 3小时 45分钟"
        )
    }

    func test剩余时长在结束或过期时显示已结束() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)

        XCTAssertEqual(
            UsageFormatter.remainingDurationText(until: now, now: now),
            "已结束"
        )
        XCTAssertEqual(
            UsageFormatter.remainingDurationText(
                until: now.addingTimeInterval(-60),
                now: now
            ),
            "已结束"
        )
    }

    func test剩余时长按绝对时间计算而不受时区影响() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let end = Date(timeIntervalSince1970: 1_786_333_500)

        XCTAssertEqual(
            UsageFormatter.remainingDurationText(until: end, now: now),
            "3小时 45分钟"
        )
    }

    func test通用指标剩余不足一小时时变绿() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)

        func normalizedMetric(id: String, label: String, remainingInterval: TimeInterval) -> NormalizedUsageMetric {
            NormalizedUsageMetric(
                id: id,
                label: label,
                used: 1,
                limit: 100,
                remaining: 99,
                unit: .request,
                windowEnd: now.addingTimeInterval(remainingInterval),
                presentation: .progress,
                semantic: .usedQuota,
                healthState: .normal
            )
        }

        XCTAssertTrue(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: normalizedMetric(
                    id: "five-hour",
                    label: "5 小时用量",
                    remainingInterval: 59 * 60 - 1
                ),
                now: now
            )
        )
        XCTAssertFalse(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: normalizedMetric(
                    id: "five-hour",
                    label: "5 小时用量",
                    remainingInterval: 60 * 60
                ),
                now: now
            )
        )
        XCTAssertTrue(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: normalizedMetric(
                    id: "fiveHour",
                    label: "近 5 小时用量",
                    remainingInterval: 30 * 60
                ),
                now: now
            )
        )
        XCTAssertFalse(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: normalizedMetric(
                    id: "weekly",
                    label: "近一周用量",
                    remainingInterval: 2 * 60 * 60
                ),
                now: now
            )
        )
        XCTAssertFalse(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: normalizedMetric(
                    id: "weekly",
                    label: "近一周用量",
                    remainingInterval: 60 * 60
                ),
                now: now
            )
        )
        XCTAssertTrue(
            UsageFormatter.shouldHighlightRemainingDuration(
                for: normalizedMetric(
                    id: "monthly",
                    label: "近一月用量",
                    remainingInterval: 30 * 60
                ),
                now: now
            )
        )
    }

    func test订阅日期使用紧凑本地格式() {
        let 时区 = TimeZone(secondsFromGMT: 8 * 60 * 60)!

        XCTAssertEqual(
            UsageFormatter.subscriptionDateText(
                Date(timeIntervalSince1970: 1_786_341_600),
                timeZone: 时区
            ),
            "2026-08-10 14:00"
        )
        XCTAssertEqual(UsageFormatter.subscriptionDateText(nil, timeZone: 时区), "—")
    }

    func test订阅结束七天内显示到期提示超过七天不显示并识别已过期() {
        let now = Date(timeIntervalSince1970: 1_786_320_000)

        XCTAssertNil(
            UsageFormatter.subscriptionExpiryText(
                until: now.addingTimeInterval(7 * 24 * 60 * 60),
                now: now
            )
        )
        XCTAssertEqual(
            UsageFormatter.subscriptionExpiryText(
                until: now.addingTimeInterval(2 * 24 * 60 * 60 + 15 * 60),
                now: now
            ),
            "（2天后到期）"
        )
        XCTAssertEqual(
            UsageFormatter.subscriptionExpiryText(
                until: now.addingTimeInterval(23 * 60 * 60),
                now: now
            ),
            "（23小时后到期）"
        )
        XCTAssertEqual(
            UsageFormatter.subscriptionExpiryText(
                until: now.addingTimeInterval(45 * 60),
                now: now
            ),
            "（45分钟后到期）"
        )
        XCTAssertEqual(
            UsageFormatter.subscriptionExpiryText(
                until: now.addingTimeInterval(-60),
                now: now
            ),
            "（已过期）"
        )
    }

    func test完整时间使用统一的本地日期格式() {
        let 时区 = TimeZone(secondsFromGMT: 8 * 60 * 60)!

        XCTAssertEqual(
            UsageFormatter.fullDateTime(
                Date(timeIntervalSince1970: 1_786_341_600),
                timeZone: 时区
            ),
            "2026年08月10日 14:00:00"
        )
        XCTAssertEqual(UsageFormatter.fullDateTime(nil), "—")
    }

    func test过期缓存同时说明具体请求错误() {
        let state = makeState(
            snapshot: makePeriodicSnapshot(fiveHourPercent: 68),
            isStale: true,
            error: .invalidKey
        )

        XCTAssertEqual(
            UsageFormatter.statusText(state: state),
            "缓存已过期，Key 无效"
        )
    }

    func test无缓存网络错误提供可操作文案() {
        let state = makeState(snapshot: nil, error: .network)

        XCTAssertEqual(UsageFormatter.statusText(state: state), "网络错误，将自动重试")
    }

    func test非有限百分比显示安全错误状态() {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: .nan))

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "!"
        )
        XCTAssertEqual(
            UsageFormatter.statusText(state: state, dimension: .fiveHour),
            "用量数据异常"
        )
    }

    func test超出整数范围的百分比显示安全错误状态() {
        let state = makeState(
            snapshot: makePeriodicSnapshot(fiveHourPercent: .greatestFiniteMagnitude)
        )

        XCTAssertEqual(
            UsageFormatter.menuBarText(state: state, dimension: .fiveHour),
            "!"
        )
        XCTAssertEqual(
            UsageFormatter.statusText(state: state, dimension: .fiveHour),
            "用量数据异常"
        )
    }

    func testKey的可访问性提示不再表达选中状态() throws {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))
        let metric = try XCTUnwrap(state.snapshot?.fiveHour)

        XCTAssertEqual(
            UsageRowAccessibility.label(
                state: state,
                metric: metric,
                dimension: .fiveHour,
            ),
            "主账号，已使用 68%，$6.80 / $10.00，5 小时剩余 —，周剩余 —"
        )
        XCTAssertEqual(
            UsageRowAccessibility.hint(),
            ""
        )
    }

    func test非当前Key不提供设为当前提示() throws {
        let state = makeState(snapshot: makePeriodicSnapshot(fiveHourPercent: 67.5))
        let metric = try XCTUnwrap(state.snapshot?.fiveHour)

        XCTAssertEqual(
            UsageRowAccessibility.label(
                state: state,
                metric: metric,
                dimension: .fiveHour,
            ),
            "主账号，已使用 68%，$6.80 / $10.00，5 小时剩余 —，周剩余 —"
        )
        XCTAssertEqual(
            UsageRowAccessibility.hint(),
            ""
        )
    }

    func test无周期窗口的可访问性标签省略窗口倒计时() throws {
        let snapshot = UsageSnapshot(
            planName: "Provider",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 1_786_320_000),
            metrics: [NormalizedUsageMetric(
                id: "credit-progress",
                label: "账户额度",
                used: 5,
                limit: 15,
                remaining: 10,
                unit: .currency,
                presentation: .progress,
                semantic: .usedQuota,
                currencyCode: "$"
            )]
        )
        let state = makeState(snapshot: snapshot)
        let label = UsageRowAccessibility.label(
            state: state,
            metric: nil,
            dimension: .fiveHour
        )

        XCTAssertFalse(label.contains("5 小时剩余"))
        XCTAssertFalse(label.contains("周剩余"))
    }

    func test周期套餐可访问性标签包含两个倒计时与分组倍率() throws {
        let now = Date(timeIntervalSince1970: 1_786_320_000)
        let snapshot = UsageSnapshot(
            planName: "Pro",
            kind: .periodic,
            fiveHour: makeMetric(
                used: 6.8,
                limit: 10,
                remaining: 3.2,
                unit: .usd,
                windowEnd: now.addingTimeInterval(3 * 60 * 60 + 45 * 60)
            ),
            weekly: makeMetric(
                used: 20,
                limit: 50,
                remaining: 30,
                percent: 40,
                unit: .usd,
                windowEnd: now.addingTimeInterval(2 * 24 * 60 * 60 + 15 * 60)
            ),
            token: nil,
            allowedModels: [],
            fetchedAt: now,
            groupMultipliers: [
                UsageGroupMultiplier(name: "Codex", multiplier: 1),
                UsageGroupMultiplier(name: "Codex Pro", multiplier: 2),
            ]
        )
        let state = makeState(snapshot: snapshot)
        let metric = try XCTUnwrap(snapshot.fiveHour)

        XCTAssertEqual(
            UsageRowAccessibility.label(
                state: state,
                metric: metric,
                dimension: .fiveHour,
                now: now
            ),
            "主账号，已使用 68%，$6.80 / $10.00，5 小时剩余 3小时 45分钟，周剩余 2天 15分钟，Codex ×1、Codex Pro ×2"
        )
    }

    func testToken资源包可访问性标签朗读倍率但省略周期倒计时() throws {
        let snapshot = UsageSnapshot(
            planName: "资源包",
            kind: .tokenPack,
            fiveHour: nil,
            weekly: nil,
            token: makeMetric(
                used: 9_200_000,
                limit: 10_000_000,
                remaining: 800_000,
                percent: 92.4,
                unit: .token
            ),
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 1_786_320_000),
            groupMultipliers: [UsageGroupMultiplier(name: "Fast", multiplier: 1.5)]
        )
        let state = makeState(snapshot: snapshot)
        let metric = try XCTUnwrap(snapshot.token)

        let label = UsageRowAccessibility.label(
            state: state,
            metric: metric,
            dimension: .fiveHour,
        )

        XCTAssertTrue(label.contains("Fast ×1.5"))
        XCTAssertFalse(label.contains("5 小时剩余"))
        XCTAssertFalse(label.contains("周剩余"))
    }
}

private extension UsageFormatterTests {
    func makeState(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool = false,
        isStale: Bool = false,
        error: UsageDisplayError? = nil
    ) -> KeyUsageState {
        KeyUsageState(
            configuration: KeyConfiguration(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "主账号",
                keySuffix: "8F2A",
                sortOrder: 0
            ),
            snapshot: snapshot,
            lastSuccessAt: snapshot?.fetchedAt,
            isRefreshing: isRefreshing,
            isStale: isStale,
            error: error
        )
    }

    func makePeriodicSnapshot(fiveHourPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            planName: "Pro",
            kind: .periodic,
            fiveHour: makeMetric(
                used: 6.8,
                limit: 10,
                remaining: 3.2,
                percent: fiveHourPercent,
                unit: .usd
            ),
            weekly: makeMetric(
                used: 20,
                limit: 50,
                remaining: 30,
                percent: 40,
                unit: .usd
            ),
            token: nil,
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 1_786_370_400)
        )
    }

    func makeTokenSnapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            planName: "资源包",
            kind: .tokenPack,
            fiveHour: nil,
            weekly: nil,
            token: makeMetric(
                used: 9_200_000,
                limit: 10_000_000,
                remaining: 800_000,
                percent: percent,
                unit: .token
            ),
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 1_786_370_400)
        )
    }

    func makeMetric(
        used: Decimal,
        limit: Decimal,
        remaining: Decimal,
        percent: Double = 68,
        unit: UsageUnit,
        windowEnd: Date? = nil
    ) -> UsageMetric {
        UsageMetric(
            used: used,
            limit: limit,
            remaining: remaining,
            percent: percent,
            unit: unit,
            windowEnd: windowEnd
        )
    }
}
