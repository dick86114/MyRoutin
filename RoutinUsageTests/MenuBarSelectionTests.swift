import XCTest
@testable import RoutinUsage

final class MenuBarSelectionTests: XCTestCase {
    private func menuMetric(id: String, label: String) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: label,
            used: 40,
            limit: 100,
            remaining: 60,
            unit: .token,
            presentation: .progress,
            semantic: .usedQuota
        )
    }

    private func menuCapability(
        id: String,
        label: String,
        priority: Int?
    ) -> UsageMetricCapability {
        UsageMetricCapability(
            metricID: id,
            label: label,
            presentation: .progress,
            semantic: .usedQuota,
            isMenuBarSelectable: true,
            menuBarPriority: priority,
            defaultAlertEnabled: true,
            defaultAbsoluteAlertThreshold: nil
        )
    }

    func test自动菜单栏指标优先使用供应商首选进度指标() {
        let resolution = MenuBarMetricResolver.resolve(
            selectedMetricID: nil,
            metrics: [menuMetric(id: "weekly", label: "周"), menuMetric(id: "fiveHour", label: "5 小时")],
            capabilities: [
                menuCapability(id: "fiveHour", label: "5 小时", priority: 0),
                menuCapability(id: "weekly", label: "周", priority: 1)
            ]
        )

        XCTAssertEqual(resolution.metric?.id, "fiveHour")
        XCTAssertNil(resolution.selectedMetricID)
        XCTAssertFalse(resolution.isFallback)
    }

    func test手动菜单栏指标使用匹配的运行时指标() {
        let resolution = MenuBarMetricResolver.resolve(
            selectedMetricID: "weekly",
            metrics: [
                menuMetric(id: "fiveHour", label: "5 小时"),
                menuMetric(id: "weekly", label: "周")
            ],
            capabilities: [
                menuCapability(id: "fiveHour", label: "5 小时", priority: 0),
                menuCapability(id: "weekly", label: "周", priority: 1)
            ]
        )

        XCTAssertEqual(resolution.metric?.id, "weekly")
        XCTAssertEqual(resolution.selectedMetricID, "weekly")
        XCTAssertFalse(resolution.isFallback)
    }

    func test手动指标失效时回退自动但保留原选择() {
        let resolution = MenuBarMetricResolver.resolve(
            selectedMetricID: "monthly",
            metrics: [menuMetric(id: "weekly", label: "周")],
            capabilities: [menuCapability(id: "weekly", label: "周", priority: 0)]
        )

        XCTAssertEqual(resolution.metric?.id, "weekly")
        XCTAssertTrue(resolution.isFallback)
        XCTAssertEqual(resolution.selectedMetricID, "monthly")
    }

    func test选项合并运行时指标并排除不可选普通数值() {
        let runtimeValue = NormalizedUsageMetric(
            id: "requests",
            label: "请求次数",
            value: 20,
            unit: .request,
            presentation: .value,
            semantic: .value
        )
        let runtimeQuota = menuMetric(id: "monthly", label: "月用量")
        let disabledCapability = UsageMetricCapability(
            metricID: "disabled",
            label: "已禁用",
            presentation: .progress,
            semantic: .usedQuota,
            isMenuBarSelectable: false,
            menuBarPriority: 0,
            defaultAlertEnabled: true,
            defaultAbsoluteAlertThreshold: nil
        )

        let options = MenuBarMetricResolver.options(
            metrics: [runtimeQuota, runtimeValue],
            capabilities: [disabledCapability, menuCapability(id: "weekly", label: "周", priority: 1)]
        )

        XCTAssertEqual(options.map(\.metricID), ["monthly", "weekly"])
    }

    func test无供应商优先级的运行时指标排序不溢出() {
        let resolution = MenuBarMetricResolver.resolve(
            selectedMetricID: nil,
            metrics: [menuMetric(id: "balance", label: "余额")],
            capabilities: []
        )

        XCTAssertEqual(resolution.metric?.id, "balance")
        XCTAssertFalse(resolution.isFallback)
    }

    func test进度型凭证生成真实百分比指标() {
        let state = KeyUsageState(
            configuration: KeyConfiguration(id: UUID(), name: "GLM", keySuffix: "", sortOrder: 0, providerID: .glm, credentialKind: .apiKey),
            snapshot: UsageSnapshot(
                planName: "Coding Plan", kind: .periodic, fiveHour: nil, weekly: nil, token: nil,
                allowedModels: [], fetchedAt: .now,
                metrics: [NormalizedUsageMetric(id: "quota", label: "配额", used: 68, limit: 100, remaining: 32, unit: .token, presentation: .progress, semantic: .usedQuota, healthState: .warning)]
            ),
            lastSuccessAt: .now, isRefreshing: false, isStale: false, error: nil
        )
        let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .glm })!

        let indicator = MenuBarIndicatorModel.make(
            state: state,
            descriptor: descriptor,
            metric: state.snapshot?.metrics.first
        )

        XCTAssertEqual(indicator.shortCode, "GLM")
        XCTAssertEqual(indicator.percent, 68)
        XCTAssertEqual(indicator.healthState, .warning)
    }

    func test余额型凭证不生成百分比并保留余额语义() {
        let state = KeyUsageState(
            configuration: KeyConfiguration(id: UUID(), name: "DeepSeek", keySuffix: "", sortOrder: 0, providerID: .deepseek, credentialKind: .apiKey),
            snapshot: UsageSnapshot(
                planName: "API 余额", kind: .periodic, fiveHour: nil, weekly: nil, token: nil,
                allowedModels: [], fetchedAt: .now,
                metrics: [NormalizedUsageMetric(id: "balance", label: "余额", value: 12.36, unit: .currency, presentation: .balance, semantic: .balance, currencyCode: "CNY", healthState: .normal)]
            ),
            lastSuccessAt: .now, isRefreshing: false, isStale: false, error: nil
        )
        let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .deepseek })!

        let indicator = MenuBarIndicatorModel.make(
            state: state,
            descriptor: descriptor,
            metric: state.snapshot?.metrics.first
        )

        XCTAssertNil(indicator.percent)
        XCTAssertTrue(indicator.accessibilityLabel.contains("余额"))
    }

    func test菜单栏剩余额度语义优先于不含剩余的标签() {
        let state = KeyUsageState(
            configuration: KeyConfiguration(id: UUID(), name: "GLM", keySuffix: "", sortOrder: 0, providerID: .glm, credentialKind: .apiKey),
            snapshot: UsageSnapshot(
                planName: "Coding Plan", kind: .periodic, fiveHour: nil, weekly: nil, token: nil,
                allowedModels: [], fetchedAt: .now,
                metrics: [NormalizedUsageMetric(id: "quota", label: "本期用量", used: 20, limit: 100, remaining: 80, unit: .token, presentation: .progress, semantic: .remainingQuota)]
            ),
            lastSuccessAt: .now, isRefreshing: false, isStale: false, error: nil
        )
        let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .glm })!

        let indicator = MenuBarIndicatorModel.make(
            state: state,
            descriptor: descriptor,
            metric: state.snapshot?.metrics.first
        )

        XCTAssertEqual(indicator.percent, 80)
        XCTAssertTrue(indicator.accessibilityLabel.contains("剩余 80%"))
    }

    func test菜单栏已用额度语义优先于包含剩余的标签() {
        let state = KeyUsageState(
            configuration: KeyConfiguration(id: UUID(), name: "GLM", keySuffix: "", sortOrder: 0, providerID: .glm, credentialKind: .apiKey),
            snapshot: UsageSnapshot(
                planName: "Coding Plan", kind: .periodic, fiveHour: nil, weekly: nil, token: nil,
                allowedModels: [], fetchedAt: .now,
                metrics: [NormalizedUsageMetric(id: "quota", label: "剩余额度", used: 20, limit: 100, remaining: 80, unit: .token, presentation: .progress, semantic: .usedQuota)]
            ),
            lastSuccessAt: .now, isRefreshing: false, isStale: false, error: nil
        )
        let descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .glm })!

        let indicator = MenuBarIndicatorModel.make(
            state: state,
            descriptor: descriptor,
            metric: state.snapshot?.metrics.first
        )

        XCTAssertEqual(indicator.percent, 20)
        XCTAssertTrue(indicator.accessibilityLabel.contains("已使用 20%"))
    }
}
