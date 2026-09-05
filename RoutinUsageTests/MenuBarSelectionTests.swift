import XCTest
@testable import RoutinUsage

final class MenuBarSelectionTests: XCTestCase {
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

        let indicator = MenuBarIndicatorModel.make(state: state, descriptor: descriptor, dimension: .fiveHour)

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

        let indicator = MenuBarIndicatorModel.make(state: state, descriptor: descriptor, dimension: .fiveHour)

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

        let indicator = MenuBarIndicatorModel.make(state: state, descriptor: descriptor, dimension: .fiveHour)

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

        let indicator = MenuBarIndicatorModel.make(state: state, descriptor: descriptor, dimension: .fiveHour)

        XCTAssertEqual(indicator.percent, 20)
        XCTAssertTrue(indicator.accessibilityLabel.contains("已使用 20%"))
    }
}
