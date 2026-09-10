import XCTest
@testable import RoutinUsage

final class UsagePresentationPolicyTests: XCTestCase {
    func test供应商栅格策略过滤GLMZCode并按供应商分栏() {
        func metric(_ id: String) -> NormalizedUsageMetric {
            NormalizedUsageMetric(
                id: id,
                label: id,
                unit: .request,
                presentation: .value,
                semantic: .value
            )
        }

        let metrics = [
            metric("five-hour"),
            metric("weekly"),
            metric("model-calls"),
            metric("zcode-mcp")
        ]

        XCTAssertEqual(
            UsageMetricGridPolicy.layout(providerID: .glm, metrics: metrics),
            UsageMetricGridLayout(
                metrics: [
                    metric("five-hour"),
                    metric("weekly"),
                    metric("model-calls"),
                    metric("zcode-mcp")
                ],
                columns: 2,
                showsAmountDetails: false
            )
        )
        XCTAssertEqual(UsageMetricGridPolicy.layout(providerID: .volcengine, metrics: metrics).columns, 2)
        XCTAssertEqual(UsageMetricGridPolicy.layout(providerID: .deepseek, metrics: metrics).columns, 2)
        XCTAssertEqual(UsageMetricGridPolicy.layout(providerID: .routin, metrics: metrics).columns, 2)
        XCTAssertEqual(UsageMetricGridPolicy.layout(providerID: .newAPI, metrics: metrics).columns, 2)
    }

    func test弹窗为CommandCode接入专用指标视图() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("UsageRowView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("providerID == .commandCode"))
        XCTAssertTrue(source.contains("CommandCodeUsageMetricsView("))
        let detailSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("Settings")
                .appendingPathComponent("CredentialDetailsView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(detailSource.contains("CommandCodeUsageMetricsView("))
        XCTAssertTrue(detailSource.contains("providerID == .commandCode"))
    }

    func testCommandCode指标按三行布局排列并隐藏额外摘要() {
        let metrics = [
            "credit-progress", "credit-balance", "monthly-remaining",
            "purchased-remaining", "free-remaining", "period-spent",
            "request-count", "five-hour", "weekly"
        ].map { id in
            NormalizedUsageMetric(
                id: id,
                label: id,
                unit: .currency,
                presentation: .value,
                semantic: .value
            )
        }

        let layout = CommandCodeMetricLayoutPolicy.layout(metrics: metrics)

        XCTAssertEqual(layout.fiveHour?.id, "five-hour")
        XCTAssertEqual(layout.weekly?.id, "weekly")
        XCTAssertEqual(layout.monthly?.id, "credit-progress")
        XCTAssertEqual(layout.requestCount?.id, "request-count")
        XCTAssertEqual(layout.purchasedRemaining?.id, "purchased-remaining")
        XCTAssertEqual(layout.freeRemaining?.id, "free-remaining")
        XCTAssertEqual(layout.displayedMetrics.map(\.id), [
            "five-hour", "weekly", "credit-progress", "request-count",
            "purchased-remaining", "free-remaining"
        ])
    }

    func testCommandCode周期详情按纵向顺序输出四行() throws {
        let now = Date(timeIntervalSince1970: 1_789_048_800)
        let metric = NormalizedUsageMetric(
            id: "five-hour",
            label: "5 小时",
            used: 2.56,
            limit: 14,
            remaining: 11.44,
            unit: .currency,
            windowEnd: now.addingTimeInterval(23 * 60),
            presentation: .progress,
            semantic: .usedQuota,
            currencyCode: "$"
        )

        let lines = CommandCodeMetricLayoutPolicy.progressDetailLines(for: metric, now: now)

        XCTAssertEqual(lines.map(\.text), [
            "已用 2.56 / 14.00",
            "剩余 11.44",
            "重置 \(UsageFormatter.resetTime(metric.windowEnd!, now: now))",
            "剩余 23分钟"
        ])
        XCTAssertTrue(lines.last?.highlights == true)
    }

    func testCommandCode累计请求采用左标签右值() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("CommandCodeUsageMetricsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Spacer(minLength: 4)"))
        XCTAssertTrue(source.contains("numberText(metric.value)"))
    }

    func testCommandCode金额四舍五入保留两位小数() {
        XCTAssertEqual(
            CommandCodeMetricFormatter.amount(Decimal(string: "12.345")),
            "12.35"
        )
        XCTAssertEqual(
            CommandCodeMetricFormatter.amount(Decimal(string: "7.2")),
            "7.20"
        )
    }

    func test弹窗按供应商使用统一栅格并隐藏GLMZCode指标() throws {
        let popoverRow = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("UsageRowView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(popoverRow.contains("UsageMetricGridPolicy.layout("))
        XCTAssertTrue(popoverRow.contains("NormalizedUsageMetricGrid("))
        XCTAssertFalse(popoverRow.contains("ForEach(snapshot.normalizedMetrics)"))
    }

    func test凭证管理页保持轻量且不复制完整用量栅格() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("Settings")
                .appendingPathComponent("CredentialManagementView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("UsageMetricGridPolicy.layout("))
        XCTAssertFalse(source.contains("NormalizedUsageMetricGrid("))
    }

    func test通用用量卡片使用Routin小字号并完整单独显示重置时间() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("NormalizedUsageMetricGrid.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("Text(metric.label)\n                    .font(.caption)")
        )
        XCTAssertFalse(source.contains(".font(.body)"))
        XCTAssertTrue(
            source.contains("Text(\"重置 \\(UsageFormatter.fullDateTime(windowEnd))\")")
        )
        XCTAssertTrue(source.contains("case .relativeDuration"))
        XCTAssertTrue(
            source.contains("UsageFormatter.remainingDurationText(until: windowEnd, now: now)")
        )
        XCTAssertTrue(
            source.contains("UsageFormatter.shouldHighlightRemainingDuration(")
        )
        XCTAssertTrue(
            source.contains("? Color.green : Color.secondary")
        )
    }

    func test弹窗通用卡片按Routin逻辑显示重置剩余时长() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("UsageRowView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("normalizedMetricsContent(snapshot: snapshot, now: now)"))
        XCTAssertTrue(source.contains("resetTimeStyle: .relativeDuration"))
        XCTAssertTrue(source.contains("now: now"))
    }

    func test弹窗供应商信息显示供应商与套餐() throws {
        XCTAssertEqual(
            UsageRowPresentation.subscriptionDescription(providerID: .glm, planName: "Coding Plan"),
            "GLM · Coding Plan"
        )
        XCTAssertEqual(
            UsageRowPresentation.subscriptionDescription(providerID: .routin, planName: "成长版"),
            "Routin · 成长版"
        )
        XCTAssertEqual(
            UsageRowPresentation.subscriptionDescription(providerID: .routin, planName: ""),
            "Routin"
        )
    }

    func test设置窗口存在时显示Dock图标关闭后恢复菜单栏形态() throws {
        let coordinator = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("App")
                .appendingPathComponent("SettingsWindowActivationPolicy.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("App")
                .appendingPathComponent("RoutinUsageApp.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("Settings")
                .appendingPathComponent("SettingsWindowView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(coordinator.contains(".regular : .accessory"))
        XCTAssertTrue(app.contains("SettingsWindowActivationPolicy.refresh()"))
        XCTAssertTrue(settings.contains("SettingsWindowDockIconAnchor()"))
    }
}
