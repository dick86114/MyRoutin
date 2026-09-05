import Foundation

struct GLMUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.z.ai")!) {
        self.session = session
        self.baseURL = baseURL
        self.descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .glm })!
    }

    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] {
        guard configuration.credentialKind == .apiKey else { return [] }
        return [
            UsageMetricCapability(
                metricID: "five-hour",
                label: "5 小时用量",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 0,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            ),
            UsageMetricCapability(
                metricID: "weekly",
                label: "每周用量",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 1,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            ),
            UsageMetricCapability(
                metricID: "model-calls",
                label: "模型调用量",
                presentation: .value,
                semantic: .value,
                isMenuBarSelectable: false,
                menuBarPriority: nil,
                defaultAlertEnabled: false,
                defaultAbsoluteAlertThreshold: nil
            ),
            UsageMetricCapability(
                metricID: "zcode-mcp",
                label: "MCP 调用量",
                presentation: .value,
                semantic: .usedQuota,
                isMenuBarSelectable: false,
                menuBarPriority: nil,
                defaultAlertEnabled: false,
                defaultAbsoluteAlertThreshold: nil
            )
        ]
    }

    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        try await fetchUsage(credential, now: now)
    }

    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        guard credential.providerID == .glm, credential.kind == .apiKey, !credential.secret.isEmpty else {
            throw UsageProviderError.invalidCredential
        }

        let root = credential.metadata["baseURL"]
            .flatMap(URL.init(string:)) ?? baseURL
        let start = Self.format(Self.windowStart(from: now))
        let end = Self.format(Self.windowEnd(from: now))
        let query = "?startTime=\(Self.encode(start))&endTime=\(Self.encode(end))"

        async let model = request(
            url: root.appendingPathComponent("/api/monitor/usage/model-usage").appending(query: query),
            credential: credential
        )
        async let quota = request(
            url: root.appendingPathComponent("/api/monitor/usage/quota/limit"),
            credential: credential
        )

        let (modelValue, quotaValue) = try await (model, quota)
        let quotaMetrics = Self.quotaMetrics(from: quotaValue)
        var metrics = quotaMetrics.filter { $0.id != "zcode-mcp" }
        if let modelCallMetric = Self.modelCallMetric(from: modelValue) {
            metrics.append(modelCallMetric)
        }
        if let zcodeMCPMetric = quotaMetrics.first(where: { $0.id == "zcode-mcp" }) {
            metrics.append(zcodeMCPMetric)
        }
        guard !metrics.isEmpty else {
            throw UsageProviderError.invalidResponse
        }

        return UsageSnapshot(
            planName: "Coding Plan",
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: now,
            providerID: .glm,
            credentialID: credential.credentialID,
            metrics: metrics
        )
    }

    private func request(url: URL, credential: ProviderCredential) async throws -> GLMJSONValue {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(credential.secret, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

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
            switch httpResponse.statusCode {
            case 401, 403: throw UsageProviderError.unauthorized
            case 429: throw UsageProviderError.rateLimited
            case 500...599: throw UsageProviderError.providerUnavailable
            default: throw UsageProviderError.invalidResponse
            }
        }
        do {
            return try JSONDecoder().decode(GLMJSONValue.self, from: data)
        } catch {
            throw UsageProviderError.invalidResponse
        }
    }

    private static func quotaMetrics(from value: GLMJSONValue) -> [NormalizedUsageMetric] {
        let limits: [GLMJSONValue]
        switch value {
        case let .object(object):
            if case let .object(data)? = object["data"], case let .array(items)? = data["limits"] {
                limits = items
            } else if case let .array(items)? = object["limits"] {
                limits = items
            } else {
                limits = []
            }
        default:
            limits = []
        }

        var fiveHour: NormalizedUsageMetric?
        var weekly: NormalizedUsageMetric?
        var zcodeMCP: NormalizedUsageMetric?

        for item in limits {
            guard case let .object(object) = item,
                  let percentage = object["percentage"]?.numberValue()
            else { continue }
            let type = object["type"]?.stringValue() ?? "quota"
            let unit = object["unit"]?.numberValue().map { NSDecimalNumber(decimal: $0).intValue }
            let number = object["number"]?.numberValue().map { NSDecimalNumber(decimal: $0).intValue }
            let windowEnd = Self.date(fromMilliseconds: object["nextResetTime"]?.numberValue())

            switch (type, unit, number) {
            case ("TOKENS_LIMIT", 3, 5):
                fiveHour = Self.percentMetric(
                    id: "five-hour",
                    label: "5 小时用量",
                    percentage: percentage,
                    windowEnd: windowEnd
                )
            case ("TOKENS_LIMIT", 6, 1):
                weekly = Self.percentMetric(
                    id: "weekly",
                    label: "每周用量",
                    percentage: percentage,
                    windowEnd: windowEnd
                )
            case ("TIME_LIMIT", _, _):
                let limit = object["usage"]?.numberValue() ?? 100
                let used = object["currentValue"]?.numberValue() ?? percentage
                let remaining = object["remaining"]?.numberValue() ?? max(0, limit - used)
                zcodeMCP = NormalizedUsageMetric(
                    id: "zcode-mcp",
                    label: "MCP 调用量",
                    used: used,
                    limit: limit,
                    remaining: remaining,
                    value: used,
                    unit: .request,
                    windowEnd: windowEnd,
                    presentation: .value,
                    semantic: .usedQuota,
                    healthState: Self.healthState(for: percentage)
                )
            default:
                continue
            }
        }

        return [fiveHour, weekly, zcodeMCP].compactMap { $0 }
    }

    private static func modelCallMetric(from value: GLMJSONValue) -> NormalizedUsageMetric? {
        guard case let .object(object) = value,
              case let .object(data)? = object["data"],
              case let .object(totalUsage)? = data["totalUsage"],
              let count = totalUsage["totalModelCallCount"]?.numberValue()
        else {
            return nil
        }
        return NormalizedUsageMetric(
            id: "model-calls",
            label: "模型调用量",
            value: count,
            unit: .request,
            presentation: .value,
            semantic: .value,
            healthState: .normal
        )
    }

    private static func percentMetric(
        id: String,
        label: String,
        percentage: Decimal,
        windowEnd: Date?
    ) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: label,
            used: percentage,
            limit: 100,
            remaining: max(0, 100 - percentage),
            unit: .token,
            windowEnd: windowEnd,
            presentation: .progress,
            semantic: .usedQuota,
            healthState: healthState(for: percentage)
        )
    }

    private static func healthState(for percentage: Decimal) -> UsageMetricHealthState {
        let value = NSDecimalNumber(decimal: percentage).doubleValue
        if value >= 80 { return .critical }
        if value >= 50 { return .warning }
        return .normal
    }

    private static func date(fromMilliseconds value: Decimal?) -> Date? {
        guard let value else { return nil }
        return Date(timeIntervalSince1970: NSDecimalNumber(decimal: value).doubleValue / 1_000)
    }

    private static func windowStart(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
    }

    private static func windowEnd(from date: Date) -> Date {
        Calendar.current.date(bySetting: .minute, value: 59, of: date)
            .flatMap { Calendar.current.date(bySetting: .second, value: 59, of: $0) } ?? date
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private extension URL {
    func appending(query: String) -> URL {
        URL(string: absoluteString + query) ?? self
    }
}
