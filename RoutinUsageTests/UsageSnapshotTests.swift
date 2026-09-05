import XCTest
@testable import RoutinUsage

final class UsageSnapshotTests: XCTestCase {
    func test通用指标四种展示类型可编码解码() throws {
        let metrics = [
            NormalizedUsageMetric(id: "quota", label: "配额", used: 20, limit: 100, remaining: 80, unit: .token, presentation: .progress, semantic: .usedQuota),
            NormalizedUsageMetric(id: "balance", label: "余额", value: 12.36, unit: .currency, presentation: .balance, semantic: .balance, currencyCode: "CNY"),
            NormalizedUsageMetric(id: "availability", label: "状态", value: 1, unit: .boolean, presentation: .status, semantic: .status),
            NormalizedUsageMetric(id: "requests", label: "请求数", value: 42, unit: .request, presentation: .value, semantic: .value)
        ]
        let snapshot = UsageSnapshot(
            planName: "测试",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 100),
            metrics: metrics
        )

        let decoded = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.metrics, metrics)
    }

    func test旧Routin快照解码时通用字段使用默认值() throws {
        let json = """
        {"planName":"旧套餐","kind":"periodic","fiveHour":null,"weekly":null,"token":null,"allowedModels":[],"fetchedAt":0}
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: json)

        XCTAssertNil(snapshot.providerID)
        XCTAssertNil(snapshot.credentialID)
        XCTAssertEqual(snapshot.metrics, [])
    }

    func test旧Routin额度字段可以按通用指标读取() {
        let snapshot = UsageSnapshot(
            planName: "旧套餐",
            kind: .periodic,
            fiveHour: UsageMetric(used: 25, limit: 100, remaining: 75, percent: 25, unit: .usd, windowEnd: nil),
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.normalizedMetrics.map(\.id), ["fiveHour"])
        XCTAssertEqual(snapshot.normalizedMetrics.first?.presentation, .progress)
        XCTAssertEqual(snapshot.normalizedMetrics.first?.remaining, 75)
    }

    func test标准化指标编码保留显式语义() throws {
        let metric = NormalizedUsageMetric(
            id: "monthly",
            label: "近一月用量",
            used: 30,
            limit: 100,
            remaining: 70,
            unit: .token,
            presentation: .progress,
            semantic: .usedQuota
        )

        let data = try JSONEncoder().encode(metric)
        let decoded = try JSONDecoder().decode(NormalizedUsageMetric.self, from: data)

        XCTAssertEqual(decoded.semantic, .usedQuota)
    }

    func test旧缓存缺少语义时只在解码阶段执行兼容推断() throws {
        let json = #"{"id":"remaining","label":"剩余额度","remaining":20,"limit":100,"unit":"token","presentation":"progress","healthState":"normal"}"#

        let decoded = try JSONDecoder().decode(
            NormalizedUsageMetric.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.semantic, .remainingQuota)
    }

    func test剩余额度语义优先于不含剩余的标签展示百分比() {
        let metric = NormalizedUsageMetric(
            id: "quota",
            label: "本期用量",
            used: 20,
            limit: 100,
            remaining: 80,
            unit: .token,
            presentation: .progress,
            semantic: .remainingQuota
        )

        XCTAssertEqual(metric.displayedPercent, 80)
        XCTAssertTrue(metric.displaysRemainingPercent)
    }

    func test已用额度语义优先于包含剩余的标签展示百分比() {
        let metric = NormalizedUsageMetric(
            id: "quota",
            label: "剩余额度",
            used: 20,
            limit: 100,
            remaining: 80,
            unit: .token,
            presentation: .progress,
            semantic: .usedQuota
        )

        XCTAssertEqual(metric.displayedPercent, 20)
        XCTAssertFalse(metric.displaysRemainingPercent)
    }
}
