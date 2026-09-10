import XCTest
@testable import RoutinUsage

final class VolcenginePlanUsageProviderTests: XCTestCase {
    func test个人AFP窗口转换为进度型指标() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "Action" })?
                .value ?? ""
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))

            switch action {
            case "GetPersonalPlan":
                return (response, Data(#"{"Result":{"PlanType":"Max","Status":"Running"}}"#.utf8))
            case "GetAgentPlanAFPUsage":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = #"{"Result":{"PlanType":"Max","AFPFiveHour":{"Quota":"10000","Used":"0","ResetTime":1893456000000},"AFPDaily":{"Quota":"50000","Used":"0"},"AFPWeekly":{"Quota":"35000","Used":"3252.2867","ResetTime":1893456000000},"AFPMonthly":{"Quota":"100000","Used":"41222.3834","ResetTime":1893456000000}}}"#
                return (response, Data(body.utf8))
            default:
                return (response, Data(#"{"Result":{"Datas":[]}}"#.utf8))
            }
        }
        let provider = VolcenginePlanUsageProvider(session: stub.session, endpoint: URL(string: "https://ark.test/")!)
        let credential = ProviderCredential(
            credentialID: UUID(),
            providerID: .volcengine,
            kind: .accessKeyPair,
            secret: "secret-key",
            metadata: ["accessKeyID": "access-key", "region": "cn-beijing"]
        )

        let fetched = try await provider.fetchUsage(credential, now: Date(timeIntervalSince1970: 1_700_000_000))
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertEqual(snapshot.providerID, .volcengine)
        XCTAssertEqual(snapshot.planName, "Max Plan")
        XCTAssertEqual(snapshot.metrics.map(\.id), ["fiveHour", "weekly", "monthly"])
        XCTAssertEqual(snapshot.metrics.map(\.label), ["近 5 小时用量", "近一周用量", "近一月用量"])
        XCTAssertEqual(snapshot.metrics[1].used, Decimal(string: "3252.2867"))
        XCTAssertEqual(snapshot.metrics[1].limit, 35_000)
        XCTAssertEqual(snapshot.metrics[2].used, Decimal(string: "41222.3834"))
        XCTAssertEqual(snapshot.metrics[2].limit, 100_000)
        XCTAssertEqual(snapshot.metrics.first?.presentation, .progress)
    }

    func testAgent刷新动态获取套餐时间和允许模型() async throws {
        let actions = ActionRecorder()
        let stub = URLProtocolStub.makeSession { request in
            let action = Self.action(from: request)
            actions.append(action)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))

            switch action {
            case "GetPersonalPlan":
                let body = #"{"Result":{"PlanType":"medium","Status":"Running","StartTime":"2026-08-01T00:00:00Z","EndTime":"2026-09-01T00:00:00Z","AutoRenew":true}}"#
                return (response, Data(body.utf8))
            case "GetAgentPlanAFPUsage":
                let body = #"{"Result":{"PlanType":"medium","AFPFiveHour":{"Quota":"100","Used":"10","ResetTime":1893456000000},"AFPWeekly":{"Quota":"200","Used":"20"},"AFPMonthly":{"Quota":"300","Used":"30"}}}"#
                return (response, Data(body.utf8))
            case "ListArkAgentPlanModel":
                let body = #"{"Result":{"Datas":[{"ModelID":"doubao-seed-1-6"},{"ModelID":"kimi-k2-250711"}]}}"#
                return (response, Data(body.utf8))
            default:
                XCTFail("出现未预期的 Action：\(action)")
                return (response, Data())
            }
        }
        let provider = VolcenginePlanUsageProvider(session: stub.session, endpoint: URL(string: "https://ark.test/")!)
        let credential = Self.credential()

        let fetched = try await provider.fetchUsage(credential, now: Date(timeIntervalSince1970: 1_700_000_000))
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertEqual(actions.current, ["GetPersonalPlan", "GetAgentPlanAFPUsage", "ListArkAgentPlanModel"])
        XCTAssertEqual(snapshot.planName, "medium Plan")
        XCTAssertEqual(snapshot.statusText, "Running")
        XCTAssertEqual(snapshot.billingMode, "自动续费")
        XCTAssertEqual(snapshot.allowedModels, ["doubao-seed-1-6", "kimi-k2-250711"])
        XCTAssertEqual(
            snapshot.subscriptionStartAt,
            ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")
        )
        XCTAssertEqual(
            snapshot.subscriptionEndAt,
            ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")
        )
    }

    func test缺少AK或区域时拒绝凭证() async {
        let provider = VolcenginePlanUsageProvider(endpoint: URL(string: "https://ark.test/")!)
        let credential = ProviderCredential(
            providerID: .volcengine,
            kind: .accessKeyPair,
            secret: "secret-key",
            metadata: [:]
        )

        do {
            _ = try await provider.fetchUsage(credential, now: .now)
            XCTFail("预期凭证校验失败")
        } catch {
            XCTAssertEqual(error as? UsageProviderError, .invalidCredential)
        }
    }

    func testCodingPlan凭证使用CodingPlanAction() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "Action" })?
                .value ?? ""
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))

            switch action {
            case "GetPersonalPlan":
                return (response, Data(#"{"Result":{"PlanType":"CodingPlan","Status":"Running"}}"#.utf8))
            case "GetCodingPlanUsage":
                XCTAssertTrue(request.url?.absoluteString.contains("Action=GetCodingPlanUsage") == true)
                let body = #"{"Result":{"QuotaUsage":[{"Level":"5h","Percent":10,"ResetTimestamp":1893456000}]}}"#
                return (response, Data(body.utf8))
            default:
                return (response, Data(#"{"Result":{"Datas":[]}}"#.utf8))
            }
        }
        let provider = VolcenginePlanUsageProvider(session: stub.session, endpoint: URL(string: "https://ark.test/")!)
        let credential = ProviderCredential(
            providerID: .volcengine,
            kind: .accessKeyPair,
            secret: "secret-key",
            metadata: ["accessKeyID": "access-key", "region": "cn-beijing", "planType": "coding"]
        )

        let fetched = try await provider.fetchUsage(credential, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(fetched?.planName, "CodingPlan Plan")
    }

    func testCoding刷新动态获取Coding套餐和允许模型() async throws {
        let actions = ActionRecorder()
        let stub = URLProtocolStub.makeSession { request in
            let action = Self.action(from: request)
            actions.append(action)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))

            switch action {
            case "GetPersonalPlan":
                let body = #"{"Result":{"PlanType":"CodingPlan","Status":"Running","StartTime":"2026-08-01T08:00:00+08:00","EndTime":"2026-09-01T08:00:00+08:00","AutoRenew":false}}"#
                return (response, Data(body.utf8))
            case "GetCodingPlanUsage":
                let body = #"{"Result":{"QuotaUsage":[{"Level":"5h","Percent":10,"ResetTimestamp":1893456000}]}}"#
                return (response, Data(body.utf8))
            case "ListArkCodingPlanModel":
                let body = #"{"Result":{"Datas":[{"ModelID":"claude-sonnet-4-5"}]}}"#
                return (response, Data(body.utf8))
            default:
                XCTFail("出现未预期的 Action：\(action)")
                return (response, Data())
            }
        }
        let provider = VolcenginePlanUsageProvider(session: stub.session, endpoint: URL(string: "https://ark.test/")!)
        let credential = Self.credential(planType: "coding")

        let fetched = try await provider.fetchUsage(credential, now: Date(timeIntervalSince1970: 1_700_000_000))
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertEqual(actions.current, ["GetPersonalPlan", "GetCodingPlanUsage", "ListArkCodingPlanModel"])
        XCTAssertEqual(snapshot.planName, "CodingPlan Plan")
        XCTAssertEqual(snapshot.billingMode, "单次订阅")
        XCTAssertEqual(snapshot.allowedModels, ["claude-sonnet-4-5"])
    }

    func test套餐字段缺失时保留缺失状态而不是硬编码() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let action = Self.action(from: request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            switch action {
            case "GetPersonalPlan":
                return (response, Data(#"{"Result":{"PlanType":"medium"}}"#.utf8))
            case "GetAgentPlanAFPUsage":
                return (response, Data(#"{"Result":{"PlanType":"medium","AFPFiveHour":{"Quota":"100","Used":"10"}}}"#.utf8))
            default:
                return (response, Data(#"{"Result":{"Datas":[]}}"#.utf8))
            }
        }
        let provider = VolcenginePlanUsageProvider(session: stub.session, endpoint: URL(string: "https://ark.test/")!)

        let fetched = try await provider.fetchUsage(Self.credential(), now: .now)
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertNil(snapshot.billingMode)
        XCTAssertNil(snapshot.statusText)
        XCTAssertNil(snapshot.subscriptionStartAt)
        XCTAssertNil(snapshot.subscriptionEndAt)
        XCTAssertTrue(snapshot.allowedModels.isEmpty)
    }

    func test验证先确认个人套餐再查询用量() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let action = request.url?.absoluteString ?? ""
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            if action.contains("GetPersonalPlan") {
                return (response, Data(#"{"Result":{"PlanType":"Max","Status":"Running"}}"#.utf8))
            }
            if action.contains("GetAgentPlanAFPUsage") {
                return (response, Data(#"{"Result":{"PlanType":"Max","AFPFiveHour":{"Quota":"100","Used":"10"}}}"#.utf8))
            }
            return (response, Data(#"{"Result":{"Datas":[]}}"#.utf8))
        }
        let provider = VolcenginePlanUsageProvider(session: stub.session, endpoint: URL(string: "https://ark.test/")!)
        let credential = ProviderCredential(
            providerID: .volcengine,
            kind: .accessKeyPair,
            secret: "secret-key",
            metadata: ["accessKeyID": "access-key", "region": "cn-beijing", "planType": "agent"]
        )

        let fetched = try await provider.validate(credential, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(fetched?.planName, "Max Plan")
    }

    private static func credential(planType: String = "agent") -> ProviderCredential {
        ProviderCredential(
            credentialID: UUID(),
            providerID: .volcengine,
            kind: .accessKeyPair,
            secret: "secret-key",
            metadata: [
                "accessKeyID": "access-key",
                "region": "cn-beijing",
                "planType": planType
            ]
        )
    }

    private static func action(from request: URLRequest) -> String {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "Action" })?
            .value ?? ""
    }
}

private final class ActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock { values.append(value) }
    }

    var current: [String] {
        lock.withLock { values }
    }
}
