import XCTest
@testable import RoutinUsage

final class UsageMapperTests: XCTestCase {
    func test映射接口窗口时间订阅时间与分组倍率配对() throws {
        let dto = UsageResponseDTO(
            subscriptionId: "sub-1",
            planId: "plan-1",
            planName: "Pro",
            type: 1,
            status: 1,
            startAt: "2026-08-01T00:00:00.123Z",
            endAt: "2026-09-01T00:00:00.456Z",
            dailyLimitUsd: 10, weeklyLimitUsd: 50,
            dailyUsedUsd: 2, weeklyUsedUsd: 10,
            dailyRemainingUsd: 8, weeklyRemainingUsd: 40,
            dayWindowEndAt: "2026-08-10T14:00:00.789Z",
            weekWindowEndAt: "2026-08-15T00:00:00.321Z",
            totalTokens: nil, consumedTokens: nil, remainingTokens: nil,
            allowedModels: [],
            groupNames: ["Codex", "Codex Pro", "未配对名称"],
            groupMultipliers: [1, 2]
        )

        let snapshot = try UsageMapper().map(dto, fetchedAt: .now)

        XCTAssertEqual(snapshot.subscriptionId, "sub-1")
        XCTAssertEqual(snapshot.planId, "plan-1")
        XCTAssertEqual(snapshot.status, 1)
        XCTAssertEqual(snapshot.groupMultipliers, [
            UsageGroupMultiplier(name: "Codex", multiplier: 1),
            UsageGroupMultiplier(name: "Codex Pro", multiplier: 2)
        ])
        XCTAssertEqual(
            try XCTUnwrap(snapshot.fiveHour?.windowEnd).timeIntervalSince1970,
            1_786_370_400.789,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(snapshot.weekly?.windowEnd).timeIntervalSince1970,
            1_786_752_000.321,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(snapshot.subscriptionStartAt).timeIntervalSince1970,
            1_785_542_400.123,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(snapshot.subscriptionEndAt).timeIntervalSince1970,
            1_788_220_800.456,
            accuracy: 0.0001
        )
    }

    func test周期订阅把Daily映射为五小时窗口() throws {
        let dto = UsageResponseDTO(
            planName: "Pro", type: 1,
            dailyLimitUsd: 10, weeklyLimitUsd: 50,
            dailyUsedUsd: 6.8, weeklyUsedUsd: 21,
            dailyRemainingUsd: 3.2, weeklyRemainingUsd: 29,
            dayWindowEndAt: "2026-08-10T14:00:00Z",
            weekWindowEndAt: "2026-08-15T00:00:00Z",
            totalTokens: nil, consumedTokens: nil, remainingTokens: nil,
            allowedModels: ["gpt-4.1"]
        )

        let result = try UsageMapper().map(dto, fetchedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(result.kind, .periodic)
        XCTAssertEqual(try XCTUnwrap(result.fiveHour).percent, 68, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.weekly).percent, 42, accuracy: 0.001)
        XCTAssertEqual(result.fiveHour?.windowEnd, Date(timeIntervalSince1970: 1_786_370_400))
        XCTAssertEqual(result.metrics.map(\.semantic), [.usedQuota, .usedQuota])
    }

    func test资源包映射总Token使用率() throws {
        let dto = UsageResponseDTO(
            planName: "资源包", type: 2,
            dailyLimitUsd: nil, weeklyLimitUsd: nil,
            dailyUsedUsd: nil, weeklyUsedUsd: nil,
            dailyRemainingUsd: nil, weeklyRemainingUsd: nil,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: 10_000_000, consumedTokens: 9_200_000,
            remainingTokens: 800_000, allowedModels: []
        )

        let result = try UsageMapper().map(dto, fetchedAt: .distantPast)

        XCTAssertEqual(result.kind, .tokenPack)
        XCTAssertEqual(try XCTUnwrap(result.token).percent, 92, accuracy: 0.001)
        XCTAssertEqual(result.token?.unit, .token)
    }

    func test零周期额度抛出无效额度错误() {
        let dto = UsageResponseDTO(
            planName: "Pro", type: 1,
            dailyLimitUsd: 0, weeklyLimitUsd: 0,
            dailyUsedUsd: 0, weeklyUsedUsd: 0,
            dailyRemainingUsd: 0, weeklyRemainingUsd: 0,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: nil, consumedTokens: nil, remainingTokens: nil,
            allowedModels: []
        )

        XCTAssertThrowsError(try UsageMapper().map(dto, fetchedAt: .now)) { error in
            XCTAssertEqual(error as? UsageMapperError, .invalidLimit)
        }
    }

    func test超额使用保留真实百分比() throws {
        let dto = UsageResponseDTO(
            planName: "Pro", type: 1,
            dailyLimitUsd: 10, weeklyLimitUsd: nil,
            dailyUsedUsd: 12, weeklyUsedUsd: nil,
            dailyRemainingUsd: -2, weeklyRemainingUsd: nil,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: nil, consumedTokens: nil, remainingTokens: nil,
            allowedModels: []
        )

        let result = try UsageMapper().map(dto, fetchedAt: .now)

        XCTAssertEqual(try XCTUnwrap(result.fiveHour).percent, 120, accuracy: 0.001)
    }

    func test资源包缺失剩余Token时由总量与已用量计算() throws {
        let dto = UsageResponseDTO(
            planName: "资源包", type: 2,
            dailyLimitUsd: nil, weeklyLimitUsd: nil,
            dailyUsedUsd: nil, weeklyUsedUsd: nil,
            dailyRemainingUsd: nil, weeklyRemainingUsd: nil,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: 1_000, consumedTokens: 250, remainingTokens: nil,
            allowedModels: []
        )

        let result = try UsageMapper().map(dto, fetchedAt: .now)

        XCTAssertEqual(result.token?.remaining, 750)
        XCTAssertEqual(try XCTUnwrap(result.token).percent, 25, accuracy: 0.001)
    }

    func test五小时缺少已用与剩余量时不生成指标且保留周指标() throws {
        let dto = UsageResponseDTO(
            planName: "Pro", type: 1,
            dailyLimitUsd: 10, weeklyLimitUsd: 20,
            dailyUsedUsd: nil, weeklyUsedUsd: 10,
            dailyRemainingUsd: nil, weeklyRemainingUsd: 10,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: nil, consumedTokens: nil, remainingTokens: nil,
            allowedModels: []
        )

        let result = try UsageMapper().map(dto, fetchedAt: .now)

        XCTAssertNil(result.fiveHour)
        XCTAssertEqual(try XCTUnwrap(result.weekly).percent, 50, accuracy: 0.001)
    }

    func test未知类型按有效非零额度判断订阅类型() throws {
        let 周期订阅DTO = UsageResponseDTO(
            planName: "Pro", type: 99,
            dailyLimitUsd: 10, weeklyLimitUsd: nil,
            dailyUsedUsd: 5, weeklyUsedUsd: nil,
            dailyRemainingUsd: 5, weeklyRemainingUsd: nil,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: nil, consumedTokens: nil, remainingTokens: nil,
            allowedModels: []
        )
        let 资源包DTO = UsageResponseDTO(
            planName: "资源包", type: 99,
            dailyLimitUsd: 10, weeklyLimitUsd: nil,
            dailyUsedUsd: 5, weeklyUsedUsd: nil,
            dailyRemainingUsd: 5, weeklyRemainingUsd: nil,
            dayWindowEndAt: nil, weekWindowEndAt: nil,
            totalTokens: 1_000, consumedTokens: 100, remainingTokens: 900,
            allowedModels: []
        )

        XCTAssertEqual(try UsageMapper().map(周期订阅DTO, fetchedAt: .now).kind, .periodic)
        XCTAssertEqual(try UsageMapper().map(资源包DTO, fetchedAt: .now).kind, .tokenPack)
    }
}
