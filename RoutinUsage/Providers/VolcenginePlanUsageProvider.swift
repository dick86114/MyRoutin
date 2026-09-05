import Foundation

struct VolcenginePlanUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let signer: VolcengineRequestSigner
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        signer: VolcengineRequestSigner = VolcengineRequestSigner(),
        endpoint: URL = URL(string: "https://open.volcengineapi.com/")!
    ) {
        self.session = session
        self.signer = signer
        self.endpoint = endpoint
        self.descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .volcengine })!
    }

    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        try await validatePersonalPlan(credential, now: now)
        return try await fetchUsage(credential, now: now)
    }

    private func validatePersonalPlan(_ credential: ProviderCredential, now: Date) async throws {
        guard let accessKeyID = credential.metadata["accessKeyID"],
              let region = credential.metadata["region"],
              !accessKeyID.isEmpty,
              !region.isEmpty,
              !credential.secret.isEmpty
        else {
            throw UsageProviderError.invalidCredential
        }

        let requestedPlan = credential.metadata["planType"] == "coding" ? "CodingPlan" : "AgentPlan"
        let body = try JSONSerialization.data(withJSONObject: ["Plan": requestedPlan])
        let data = try await sendRequest(
            action: "GetPersonalPlan",
            body: body,
            accessKeyID: accessKeyID,
            secretAccessKey: credential.secret,
            region: region,
            now: now
        )
        do {
            let response = try JSONDecoder().decode(VolcenginePersonalPlanResponse.self, from: data)
            guard response.result != nil else {
                throw UsageProviderError.providerMessage("火山方舟：未找到已购买的\(requestedPlan)套餐")
            }
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.invalidResponse
        }
    }

    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        guard credential.providerID == .volcengine,
              credential.kind == .accessKeyPair,
              let accessKeyID = credential.metadata["accessKeyID"],
              !accessKeyID.isEmpty,
              let region = credential.metadata["region"],
              !region.isEmpty,
              !credential.secret.isEmpty
        else {
            throw UsageProviderError.invalidCredential
        }

        let body = Data("{}".utf8)
        let data = try await sendRequest(
            action: credential.metadata["planType"] == "coding" ? "GetCodingPlanUsage" : "GetAgentPlanAFPUsage",
            body: body,
            accessKeyID: accessKeyID,
            secretAccessKey: credential.secret,
            region: region,
            now: now
        )

        do {
            let payload = try JSONDecoder().decode(VolcengineUsageResponse.self, from: data)
            guard let result = payload.result else { throw UsageProviderError.invalidResponse }
            let windows: [(String, String, VolcengineUsageWindow?)] = [
                ("fiveHour", "近 5 小时用量", result.afpFiveHour),
                ("weekly", "近一周用量", result.afpWeekly),
                ("monthly", "近一月用量", result.afpMonthly)
            ]
            var metrics = windows.compactMap { id, label, window -> NormalizedUsageMetric? in
                guard let window, window.quota > 0 else { return nil }
                let percent = (window.used / window.quota) * 100
                return NormalizedUsageMetric(
                    id: id,
                    label: label,
                    used: window.used,
                    limit: window.quota,
                    remaining: max(0, window.quota - window.used),
                    unit: .request,
                    windowEnd: window.resetTime,
                    presentation: .progress,
                    semantic: .usedQuota,
                    healthState: percent >= 80 ? .critical : (percent >= 50 ? .warning : .normal)
                )
            }
            if metrics.isEmpty, !result.quotaUsage.isEmpty {
                metrics = result.quotaUsage.enumerated().map { index, item in
                    let percent = NSDecimalNumber(decimal: item.percent).doubleValue
                    return NormalizedUsageMetric(
                        id: "coding-\(index)",
                        label: item.level,
                        used: item.percent,
                        limit: 100,
                        remaining: max(0, 100 - item.percent),
                        unit: .request,
                        windowEnd: item.resetTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                        presentation: .progress,
                        semantic: .usedQuota,
                        healthState: percent >= 80 ? .critical : (percent >= 50 ? .warning : .normal)
                    )
                }
            }
            guard !metrics.isEmpty else { throw UsageProviderError.invalidResponse }
            let configuredPlan = credential.metadata["planType"] == "coding" ? "Coding Plan" : "Agent Plan"
            return UsageSnapshot(
                planName: result.planType.map { "\($0) Plan" } ?? configuredPlan,
                kind: .periodic,
                fiveHour: nil,
                weekly: nil,
                token: nil,
                allowedModels: [],
                fetchedAt: now,
                providerID: .volcengine,
                credentialID: credential.credentialID,
                metrics: metrics
            )
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.invalidResponse
        }
    }

    private static func makeURL(endpoint: URL, action: String) -> URL? {
        URL(string: endpoint.absoluteString + "?Action=\(action)&Version=2024-01-01")
    }

    private func sendRequest(
        action: String,
        body: Data,
        accessKeyID: String,
        secretAccessKey: String,
        region: String,
        now: Date
    ) async throws -> Data {
        guard let url = Self.makeURL(endpoint: endpoint, action: action) else {
            throw UsageProviderError.invalidCredential
        }
        let credential = VolcengineCredential(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            region: region
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = body
        var headers = [
            "Content-Type": "application/json",
            "Host": url.host ?? "open.volcengineapi.com"
        ]
        headers = signer.sign(
            method: "POST",
            url: url,
            headers: headers,
            body: body,
            credential: credential,
            date: now
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageProviderError.transport
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message = Self.safeErrorMessage(from: data) {
                throw UsageProviderError.providerMessage("火山方舟：\(message)")
            }
            switch httpResponse.statusCode {
            case 401, 403: throw UsageProviderError.unauthorized
            case 429: throw UsageProviderError.rateLimited
            case 500...599: throw UsageProviderError.providerUnavailable
            default: throw UsageProviderError.invalidResponse
            }
        }
        return data
    }

    private static func safeErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let error = object["Error"] as? [String: Any]
            ?? object["error"] as? [String: Any]
            ?? object["ResponseMetadata"] as? [String: Any]
        let code = error?["Code"] as? String ?? error?["code"] as? String
        let message = error?["Message"] as? String ?? error?["message"] as? String
        if let code, let message { return "\(code)：\(message)" }
        return message ?? code
    }
}
