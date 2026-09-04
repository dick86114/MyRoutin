import XCTest
@testable import RoutinUsage

final class UsagePresentationPolicyTests: XCTestCase {
    func test供应商栅格策略过滤GLMZCode并按供应商分栏() {
        func metric(_ id: String) -> NormalizedUsageMetric {
            NormalizedUsageMetric(
                id: id,
                label: id,
                unit: .request,
                presentation: .value
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
