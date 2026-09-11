import XCTest
@testable import RoutinUsage

@MainActor
final class CredentialAlertSettingsViewTests: XCTestCase {
    func test凭证提醒设置默认开启并只展示可预警指标() {
        let usedMetric = NormalizedUsageMetric(
            id: "weekly",
            label: "周用量",
            used: 40,
            limit: 100,
            remaining: 60,
            unit: .token,
            presentation: .progress,
            semantic: .usedQuota
        )
        let valueMetric = NormalizedUsageMetric(
            id: "requests",
            label: "请求次数",
            value: 20,
            unit: .request,
            presentation: .value,
            semantic: .value
        )
        let capabilities = [
            UsageMetricCapability(
                metricID: "weekly",
                label: "周用量",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 0,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            ),
            UsageMetricCapability(
                metricID: "requests",
                label: "请求次数",
                presentation: .value,
                semantic: .value,
                isMenuBarSelectable: false,
                menuBarPriority: nil,
                defaultAlertEnabled: false,
                defaultAbsoluteAlertThreshold: nil
            )
        ]
        var saved: CredentialUsagePreferences?
        let model = CredentialAlertSettingsModel(
            credentialID: UUID(),
            preferences: .defaultValue,
            metrics: [usedMetric, valueMetric],
            capabilities: capabilities
        ) { saved = $0 }

        XCTAssertTrue(model.notificationsEnabled)
        XCTAssertEqual(model.rules.map(\.metricID), [usedMetric.id])
        XCTAssertNil(saved)

        var rule = try! XCTUnwrap(model.rules.first)
        rule.isEnabled = false
        model.updateRule(rule)

        XCTAssertFalse(model.preferences.alertRules.first?.isEnabled ?? true)
        XCTAssertFalse(saved?.alertRules.first?.isEnabled ?? true)
    }

    func test凭证提醒设置窗口右上角提供关闭按钮() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("RoutinUsage")
                .appendingPathComponent("Views")
                .appendingPathComponent("Settings")
                .appendingPathComponent("CredentialAlertSettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@Environment(\\.dismiss)"))
        XCTAssertTrue(source.contains("Image(systemName: \"xmark\")"))
        XCTAssertTrue(source.contains("Text(title).font(.title3.weight(.semibold))"))
        XCTAssertTrue(source.contains("Spacer()"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertFalse(source.contains("Button(\"关闭\")"))
        XCTAssertTrue(source.contains("LazyVGrid("))
        XCTAssertTrue(source.contains(".frame(width: 680)"))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(source.contains("Form {"))
        XCTAssertFalse(source.contains("ScrollView"))
    }
}
