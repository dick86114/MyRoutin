import XCTest
@testable import RoutinUsage

final class CommandCodeUsageProviderTests: XCTestCase {
    func test账户额度订阅和使用窗口转换为统一指标() async throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-09-10T12:00:00Z"))
        let periodStart = "2026-08-01T00:00:00Z"
        let periodEnd = "2026-09-01T00:00:00Z"
        let fiveHourReset = Int64((now.addingTimeInterval(3_600)).timeIntervalSince1970 * 1_000)
        let weeklyReset = Int64((now.addingTimeInterval(86_400)).timeIntervalSince1970 * 1_000)
        let requests = RequestRecorder()
        let stub = URLProtocolStub.makeSession { request in
            requests.append(request)
            let path = request.url?.path ?? ""
            let body: String
            switch path {
            case "/alpha/whoami":
                body = #"{"success":true,"user":{"id":"user-1","userName":"alice"},"org":{"id":"org-1","login":"acme"},"orgLimits":[]}"#
            case "/alpha/billing/credits":
                body = """
                {"credits":{"planId":"individual-pro-v1","monthlyCredits":42,"purchasedCredits":10,"freeCredits":3},"windowLimits":{"limited":true,"fiveHour":{"used":7,"cap":16,"resetAt":\(fiveHourReset)},"weekly":{"used":25,"cap":40,"resetAt":\(weeklyReset)}}}
                """
            case "/alpha/billing/subscriptions":
                body = #"{"data":{"planId":"individual-pro-v1","status":"active","currentPeriodStart":"\#(periodStart)","currentPeriodEnd":"\#(periodEnd)"}}"#
            case "/alpha/usage/summary":
                body = #"{"totalCost":25.5,"totalCount":123}"#
            case "/provider/v1/models":
                body = #"{"object":"list","data":[{"id":"claude-sonnet-5"},{"id":"deepseek-v4-flash"}]}"#
            default:
                XCTFail("意外请求：\(path)")
                body = "{}"
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data(body.utf8))
        }
        let provider = CommandCodeUsageProvider(session: stub.session)
        let credential = ProviderCredential(
            providerID: .commandCode,
            kind: .bearerAPIKey,
            secret: "cmd-api-key"
        )

        let fetched = try await provider.fetchUsage(credential, now: now)
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertEqual(snapshot.providerID, .commandCode)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.subscriptionStartAt, formatter.date(from: periodStart))
        XCTAssertEqual(snapshot.subscriptionEndAt, formatter.date(from: periodEnd))
        XCTAssertEqual(snapshot.statusText, "有效")
        XCTAssertEqual(snapshot.allowedModels, ["claude-sonnet-5", "deepseek-v4-flash"])
        XCTAssertEqual(snapshot.metrics.map(\.id), [
            "credit-progress", "credit-balance", "monthly-remaining",
            "purchased-remaining", "free-remaining", "period-spent",
            "request-count", "five-hour", "weekly"
        ])
        XCTAssertEqual(snapshot.metrics[0].used, 38)
        XCTAssertEqual(snapshot.metrics[0].label, "月")
        XCTAssertEqual(snapshot.metrics[0].limit, 93)
        XCTAssertEqual(snapshot.metrics[0].remaining, 55)
        XCTAssertEqual(snapshot.metrics[0].currencyCode, "$")
        XCTAssertEqual(snapshot.metrics[0].healthState, .normal)
        XCTAssertEqual(snapshot.metrics[1].value, 55)
        XCTAssertEqual(snapshot.metrics[2].value, 42)
        XCTAssertEqual(snapshot.metrics[3].value, 10)
        XCTAssertEqual(snapshot.metrics[4].value, 3)
        XCTAssertEqual(snapshot.metrics[5].value, Decimal(string: "25.5"))
        XCTAssertEqual(snapshot.metrics[6].value, 123)
        XCTAssertEqual(snapshot.metrics[7].used, 7)
        XCTAssertEqual(snapshot.metrics[7].limit, 16)
        XCTAssertEqual(snapshot.metrics[7].remaining, 9)
        XCTAssertEqual(snapshot.metrics[7].windowEnd, now.addingTimeInterval(3_600))
        XCTAssertEqual(snapshot.metrics[8].used, 25)
        XCTAssertEqual(snapshot.metrics[8].limit, 40)
        XCTAssertEqual(snapshot.metrics[8].remaining, 15)
        XCTAssertEqual(snapshot.metrics[8].windowEnd, now.addingTimeInterval(86_400))

        let whoamiURL = try XCTUnwrap(requests.request(at: 0)?.url)
        let whoamiComponents = URLComponents(url: whoamiURL, resolvingAgainstBaseURL: false)
        XCTAssertEqual(whoamiComponents?.queryItems?.first(where: { $0.name == "limits" })?.value, "1")
        let summaryURL = try XCTUnwrap(requests.request(at: 3)?.url)
        let summaryComponents = URLComponents(url: summaryURL, resolvingAgainstBaseURL: false)
        XCTAssertEqual(
            summaryComponents?.queryItems?.first(where: { $0.name == "since" })?.value,
            periodStart
        )
        XCTAssertEqual(
            requests.request(at: 3)?.value(forHTTPHeaderField: "Authorization"),
            "Bearer cmd-api-key"
        )
        XCTAssertEqual(requests.request(at: 4)?.url?.path, "/provider/v1/models")
    }

    func test个人账号不发送空orgId查询参数() async throws {
        let requests = RequestRecorder()
        let stub = URLProtocolStub.makeSession { request in
            requests.append(request)
            let path = request.url?.path ?? ""
            let body: String
            switch path {
            case "/alpha/whoami":
                body = #"{"success":true,"org":null,"user":{"id":"user-1","userName":"alice"}}"#
            case "/alpha/billing/credits":
                body = #"{"credits":{"planId":"individual-provider","monthlyCredits":15,"purchasedCredits":2,"freeCredits":0},"windowLimits":{"limited":false}}"#
            case "/alpha/billing/subscriptions":
                body = #"{"data":{"planId":"individual-provider","status":"active","currentPeriodStart":"2026-08-01T00:00:00Z","currentPeriodEnd":"2026-09-01T00:00:00Z"}}"#
            case "/alpha/usage/summary":
                body = #"{"totalCost":2,"totalCount":3}"#
            case "/provider/v1/models":
                body = #"{"object":"list","data":[{"id":"claude-sonnet-5"}]}"#
            default:
                XCTFail("意外请求：\(path)")
                body = "{}"
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(body.utf8))
        }
        let provider = CommandCodeUsageProvider(session: stub.session)
        let credential = ProviderCredential(
            providerID: .commandCode,
            kind: .bearerAPIKey,
            secret: "cmd-api-key"
        )

        _ = try await provider.fetchUsage(credential, now: .now)

        for index in 1..<5 {
            let url = try XCTUnwrap(requests.request(at: index)?.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            XCTAssertNil(components?.queryItems?.first(where: { $0.name == "orgId" }))
        }
    }

    func test认证失败映射为统一错误() async {
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let provider = CommandCodeUsageProvider(session: stub.session)
        let credential = ProviderCredential(
            providerID: .commandCode,
            kind: .bearerAPIKey,
            secret: "cmd-api-key"
        )

        do {
            _ = try await provider.fetchUsage(credential, now: .now)
            XCTFail("预期认证失败")
        } catch {
            XCTAssertEqual(error as? UsageProviderError, .unauthorized)
        }
    }

    func testHTTP200业务错误展示供应商返回信息() async {
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"{"success":false,"error":{"message":"Invalid API key"}}"#.utf8))
        }
        let provider = CommandCodeUsageProvider(session: stub.session)
        let credential = ProviderCredential(
            providerID: .commandCode,
            kind: .bearerAPIKey,
            secret: "cmd-api-key"
        )

        do {
            _ = try await provider.fetchUsage(credential, now: .now)
            XCTFail("预期业务错误")
        } catch {
            XCTAssertEqual(
                error as? UsageProviderError,
                .providerMessage("Command Code：Invalid API key")
            )
        }
    }

    func test菜单栏额度指标标题使用月() {
        let provider = CommandCodeUsageProvider()
        let configuration = KeyConfiguration(
            id: UUID(),
            name: "Command Code",
            keySuffix: "",
            sortOrder: 0,
            providerID: .commandCode,
            credentialKind: .bearerAPIKey
        )

        XCTAssertEqual(provider.metricCapabilities(for: configuration).first?.label, "月")
    }

    func test凭证配置保留CommandCode密钥和预警值() throws {
        let result = try CredentialEditorValidation.validate(
            providerID: .commandCode,
            name: "我的 Command Code",
            apiKey: "cmd-api-key",
            accessKeyID: "",
            secretAccessKey: "",
            region: "",
            balanceWarningThreshold: "12.5"
        )

        XCTAssertEqual(result.providerID, .commandCode)
        XCTAssertEqual(result.credentialKind, .bearerAPIKey)
        XCTAssertEqual(result.secret, "cmd-api-key")
        XCTAssertEqual(result.metadata["balanceWarningThreshold"], "12.5")
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func request(at index: Int) -> URLRequest? {
        lock.withLock { index < requests.count ? requests[index] : nil }
    }
}
