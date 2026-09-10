import XCTest
@testable import RoutinUsage

final class GLMUsageProviderTests: XCTestCase {
    func test配额模型和工具响应转换为通用指标() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let path = request.url?.path ?? ""
            let body: String
            if path.contains("quota/limit") {
                body = #"{"data":{"limits":[{"type":"TIME_LIMIT","unit":5,"number":1,"usage":1000,"currentValue":461,"remaining":539,"percentage":46},{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":42},{"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":12}]}}"#
            } else if path.contains("model-usage") {
                body = #"{"data":{"totalUsage":{"totalModelCallCount":22}}}"#
            } else if path.contains("/api/coding/paas/v4/models") {
                body = #"{"data":[{"id":"glm-5.3"},{"id":"glm-5.3-flash"},{"id":""}]}"#
            } else {
                body = #"{"data":{"items":[{"toolName":"search","count":9}]}}"#
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data(body.utf8))
        }
        let provider = GLMUsageProvider(session: stub.session, baseURL: URL(string: "https://glm.test")!)
        let credential = ProviderCredential(providerID: .glm, kind: .apiKey, secret: "glm-token")

        let fetched = try await provider.fetchUsage(credential, now: Date(timeIntervalSince1970: 100))
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertEqual(snapshot.providerID, .glm)
        XCTAssertEqual(snapshot.allowedModels, ["glm-5.3", "glm-5.3-flash"])
        XCTAssertEqual(snapshot.metrics.count, 4)
        XCTAssertEqual(snapshot.metrics.map(\.id), ["five-hour", "weekly", "model-calls", "zcode-mcp"])
        XCTAssertEqual(snapshot.metrics.first?.label, "5 小时用量")
        XCTAssertEqual(snapshot.metrics.first?.used, 42)
        XCTAssertEqual(snapshot.metrics[1].label, "每周用量")
        XCTAssertEqual(snapshot.metrics[2].value, 22)
        XCTAssertEqual(snapshot.metrics[3].label, "MCP 调用量")
        XCTAssertEqual(snapshot.metrics[3].presentation, .value)
        XCTAssertEqual(snapshot.metrics[3].value, 461)
        XCTAssertEqual(snapshot.metrics[3].used, 461)
        XCTAssertEqual(snapshot.metrics[3].limit, 1_000)
    }

    func test模型清单接口失败时保留空列表并继续显示用量() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let path = request.url?.path ?? ""
            let statusCode = path.contains("/api/coding/paas/v4/models") ? 404 : 200
            let body = path.contains("quota/limit")
                ? #"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":42}]}}"#
                : #"{"data":{"totalUsage":{"totalModelCallCount":22}}}"#
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(body.utf8))
        }
        let provider = GLMUsageProvider(session: stub.session, baseURL: URL(string: "https://glm.test")!)
        let credential = ProviderCredential(providerID: .glm, kind: .apiKey, secret: "glm-token")

        let fetched = try await provider.fetchUsage(credential, now: .now)
        let snapshot = try XCTUnwrap(fetched)

        XCTAssertTrue(snapshot.allowedModels.isEmpty)
        XCTAssertTrue(snapshot.metrics.contains(where: { $0.id == "five-hour" }))
    }

    func test单个接口认证失败映射为统一错误() async {
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let provider = GLMUsageProvider(session: stub.session, baseURL: URL(string: "https://glm.test")!)
        let credential = ProviderCredential(providerID: .glm, kind: .apiKey, secret: "glm-token")

        do {
            _ = try await provider.fetchUsage(credential, now: .now)
            XCTFail("预期认证失败")
        } catch {
            XCTAssertEqual(error as? UsageProviderError, .unauthorized)
        }
    }

    func test配额百分比按官网语义显示已用值() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let path = request.url?.path ?? ""
            let body = path.contains("quota/limit")
                ? #"{"data":{"limits":[{"type":"TIME_LIMIT","unit":5,"number":1,"usage":1000,"currentValue":260,"remaining":740,"percentage":26},{"type":"TOKENS_LIMIT","unit":6,"number":1,"percentage":1}]}}"#
                : #"{"data":{"items":[]}}"#
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(body.utf8))
        }
        let provider = GLMUsageProvider(session: stub.session, baseURL: URL(string: "https://glm.test")!)
        let credential = ProviderCredential(providerID: .glm, kind: .apiKey, secret: "glm-token")

        let fetched = try await provider.fetchUsage(credential, now: .now)
        let snapshot = try XCTUnwrap(fetched)
        let mcp = try XCTUnwrap(snapshot.metrics.first(where: { $0.id == "zcode-mcp" }))
        let weekly = try XCTUnwrap(snapshot.metrics.first(where: { $0.id == "weekly" }))

        XCTAssertEqual(mcp.used, 260)
        XCTAssertEqual(mcp.remaining, 740)
        XCTAssertEqual(try XCTUnwrap(mcp.displayedPercent), 26, accuracy: 0.001)
        XCTAssertFalse(mcp.label.contains("剩余"))
        XCTAssertEqual(weekly.label, "每周用量")
    }
}
