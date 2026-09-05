import Foundation

struct NewAPIUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        self.descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .newAPI })!
    }

    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] {
        guard configuration.credentialKind == .bearerAPIKey else { return [] }
        let warningThreshold = configuration.metadata["balanceWarningThreshold"]
            .flatMap { Decimal(string: $0) }
        return [
            UsageMetricCapability(
                metricID: "quota-progress",
                label: "账户额度",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 0,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: warningThreshold
            ),
            Self.valueCapability(metricID: "today-token", label: "今日 Token"),
            Self.valueCapability(metricID: "one-day-token", label: "近 24 小时 Token"),
            Self.valueCapability(metricID: "seven-day-token", label: "近 7 天 Token"),
            Self.valueCapability(metricID: "thirty-day-token", label: "近 30 天 Token"),
            Self.valueCapability(metricID: "today-token-cost", label: "今日消费"),
            Self.valueCapability(metricID: "one-day-token-cost", label: "近 24 小时消费"),
            Self.valueCapability(metricID: "seven-day-token-cost", label: "近 7 天消费"),
            Self.valueCapability(metricID: "thirty-day-token-cost", label: "近 30 天消费"),
            Self.valueCapability(metricID: "rpm", label: "近 60 秒 RPM"),
            Self.valueCapability(metricID: "tpm", label: "近 60 秒 TPM"),
            Self.valueCapability(metricID: "request-count", label: "账户累计请求")
        ]
    }

    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        try await fetchUsage(credential, now: now)
    }

    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        guard credential.providerID == .newAPI,
              credential.kind == .bearerAPIKey,
              !credential.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rawUserID = credential.metadata["userID"],
              let userID = Int(rawUserID.trimmingCharacters(in: .whitespacesAndNewlines)),
              userID > 0,
              let root = Self.baseURL(from: credential.metadata["baseURL"])
        else { throw UsageProviderError.invalidCredential }

        let user: NewAPIUser
        let displayUnit: NewAPIDisplayUnit
        do {
            async let statusResponse = request(
                root.appendingPathComponent("api/status"),
                credential: credential,
                as: NewAPIEnvelope<NewAPIStatus>.self
            )
            async let userResponse = request(
                root.appendingPathComponent("api/user/self"),
                credential: credential,
                as: NewAPIEnvelope<NewAPIUser>.self
            )
            let (statusEnvelope, userEnvelope) = try await (statusResponse, userResponse)
            guard userEnvelope.success != false, let userData = userEnvelope.data else {
                throw UsageProviderError.providerMessage("New API：\(userEnvelope.message ?? "认证失败")")
            }
            user = userData
            displayUnit = NewAPIDisplayUnit(status: statusEnvelope.data)
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.invalidResponse
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let oneDayStart = now.addingTimeInterval(-24 * 60 * 60)
        let sevenDayStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let thirtyDayStart = now.addingTimeInterval(-30 * 24 * 60 * 60)

        // New API 的个人日志没有时间段 Token 聚合字段；/api/data/self 是日志衍生的
        // 当前用户聚合数据，直接返回 token_used 和 count，可避免分页拉取上万条日志。
        async let todayData = requestTokenSummary(
            root: root,
            start: Self.restrictedStart(todayStart, now: now),
            end: now,
            credential: credential
        )
        async let oneDayData = requestTokenSummary(
            root: root,
            start: Self.restrictedStart(oneDayStart, now: now),
            end: now,
            credential: credential
        )
        async let sevenDayData = requestTokenSummary(
            root: root,
            start: Self.restrictedStart(sevenDayStart, now: now),
            end: now,
            credential: credential
        )
        async let thirtyDayData = requestTokenSummary(
            root: root,
            start: Self.restrictedStart(thirtyDayStart, now: now),
            end: now,
            credential: credential
        )
        async let currentMinuteStat = requestStat(
            root: root,
            start: now.addingTimeInterval(-60),
            end: now,
            credential: credential
        )
        let (
            todaySummary,
            oneDaySummary,
            sevenDaySummary,
            thirtyDaySummary,
            currentMinute
        ) = try await (todayData, oneDayData, sevenDayData, thirtyDayData, currentMinuteStat)

        let used = user.usedQuota
        let remaining = max(0, user.quota)
        let total = used + remaining
        let threshold = credential.metadata["balanceWarningThreshold"]
            .flatMap { Decimal(string: $0) }
            .map { Self.convert($0, using: displayUnit) }
        let convertedRemaining = Self.convert(remaining, using: displayUnit)
        let health = UsageMetricHealthEvaluator.balanceState(
            balance: convertedRemaining,
            warningThreshold: threshold,
            isAvailable: true
        )
        let group = user.group?.trimmingCharacters(in: .whitespacesAndNewlines)
        let planName = group.map { "New API · \($0)" } ?? "New API"

        return UsageSnapshot(
            planName: planName,
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: [],
            fetchedAt: now,
            providerID: .newAPI,
            credentialID: credential.credentialID,
            metrics: [
                NormalizedUsageMetric(
                    id: "quota-progress",
                    label: "账户额度",
                    used: Self.convert(used, using: displayUnit),
                    limit: Self.convert(total, using: displayUnit),
                    remaining: convertedRemaining,
                    unit: .currency,
                    presentation: .progress,
                    semantic: .usedQuota,
                    currencyCode: displayUnit.symbol,
                    healthState: health
                ),
                NormalizedUsageMetric(
                    id: "today-token",
                    label: "今日 Token",
                    value: Decimal(todaySummary.tokenUsed ?? 0),
                    unit: .token,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "one-day-token",
                    label: "近 24 小时 Token",
                    value: Decimal(oneDaySummary.tokenUsed ?? 0),
                    unit: .token,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "seven-day-token",
                    label: "近 7 天 Token",
                    value: Decimal(sevenDaySummary.tokenUsed ?? 0),
                    unit: .token,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "thirty-day-token",
                    label: "近 30 天 Token",
                    value: Decimal(thirtyDaySummary.tokenUsed ?? 0),
                    unit: .token,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "today-token-cost",
                    label: "今日消费",
                    value: Self.convert(Decimal(todaySummary.quota ?? 0), using: displayUnit),
                    unit: .currency,
                    presentation: .value,
                    semantic: .value,
                    currencyCode: displayUnit.symbol,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "one-day-token-cost",
                    label: "近 24 小时消费",
                    value: Self.convert(Decimal(oneDaySummary.quota ?? 0), using: displayUnit),
                    unit: .currency,
                    presentation: .value,
                    semantic: .value,
                    currencyCode: displayUnit.symbol,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "seven-day-token-cost",
                    label: "近 7 天消费",
                    value: Self.convert(Decimal(sevenDaySummary.quota ?? 0), using: displayUnit),
                    unit: .currency,
                    presentation: .value,
                    semantic: .value,
                    currencyCode: displayUnit.symbol,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "thirty-day-token-cost",
                    label: "近 30 天消费",
                    value: Self.convert(Decimal(thirtyDaySummary.quota ?? 0), using: displayUnit),
                    unit: .currency,
                    presentation: .value,
                    semantic: .value,
                    currencyCode: displayUnit.symbol,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "rpm",
                    label: "近 60 秒 RPM",
                    value: Decimal(currentMinute.rpm),
                    unit: .request,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "tpm",
                    label: "近 60 秒 TPM",
                    value: Decimal(currentMinute.tpm),
                    unit: .token,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                ),
                NormalizedUsageMetric(
                    id: "request-count",
                    label: "账户累计请求",
                    value: Decimal(user.requestCount),
                    unit: .request,
                    presentation: .value,
                    semantic: .value,
                    healthState: .normal
                )
            ]
        )
    }

    private func requestStat(
        root: URL,
        start: Date,
        end: Date,
        credential: ProviderCredential
    ) async throws -> NewAPIStat {
        var components = URLComponents(url: root.appendingPathComponent("api/log/self/stat"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start_timestamp", value: String(Int64(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_timestamp", value: String(Int64(end.timeIntervalSince1970))),
            URLQueryItem(name: "type", value: "2")
        ]
        guard let url = components?.url else { throw UsageProviderError.invalidCredential }
        let envelope = try await request(url, credential: credential, as: NewAPIEnvelope<NewAPIStat>.self)
        guard envelope.success != false, let data = envelope.data else {
            throw UsageProviderError.providerMessage("New API：\(envelope.message ?? "统计接口返回失败")")
        }
        return data
    }

    private func requestTokenSummary(
        root: URL,
        start: Date,
        end: Date,
        credential: ProviderCredential
    ) async throws -> NewAPITokenSummary {
        var components = URLComponents(url: root.appendingPathComponent("api/data/self"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start_timestamp", value: String(Int64(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_timestamp", value: String(Int64(end.timeIntervalSince1970)))
        ]
        guard let url = components?.url else { throw UsageProviderError.invalidCredential }
        let envelope = try await request(url, credential: credential, as: NewAPIEnvelope<[NewAPITokenSummary]>.self)
        guard envelope.success != false else {
            throw UsageProviderError.providerMessage("New API：\(envelope.message ?? "Token 统计接口返回失败")")
        }
        return (envelope.data ?? []).reduce(NewAPITokenSummary()) { partial, item in
            NewAPITokenSummary(
                tokenUsed: (partial.tokenUsed ?? 0) + (item.tokenUsed ?? 0),
                requestCount: (partial.requestCount ?? 0) + (item.requestCount ?? 0),
                quota: (partial.quota ?? 0) + (item.quota ?? 0)
            )
        }
    }

    private static func restrictedStart(_ start: Date, now: Date) -> Date {
        max(start, now.addingTimeInterval(-2592000))
    }

    private static func valueCapability(metricID: String, label: String) -> UsageMetricCapability {
        UsageMetricCapability(
            metricID: metricID,
            label: label,
            presentation: .value,
            semantic: .value,
            isMenuBarSelectable: false,
            menuBarPriority: nil,
            defaultAlertEnabled: false,
            defaultAbsoluteAlertThreshold: nil
        )
    }

    private func request<T: Decodable>(
        _ url: URL,
        credential: ProviderCredential,
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        request.setValue(credential.metadata["userID"], forHTTPHeaderField: "New-Api-User")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw UsageProviderError.invalidResponse
        }
    }

    private static func baseURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              var components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme != nil,
              components.host != nil
        else { return nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        if components.path == "/api" { components.path = "" }
        return components.url
    }

    private static func valueMetric(
        id: String,
        label: String,
        value: Decimal,
        displayUnit: NewAPIDisplayUnit,
        health: UsageMetricHealthState
    ) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: label,
            value: value,
            unit: .currency,
            presentation: .value,
            semantic: .value,
            currencyCode: displayUnit.symbol,
            healthState: health
        )
    }

    private static func convert(_ rawQuota: Decimal, using displayUnit: NewAPIDisplayUnit) -> Decimal {
        displayUnit.convert(rawQuota)
    }
}

private struct NewAPIDisplayUnit: Sendable {
    let quotaPerUnit: Decimal
    let exchangeRate: Decimal
    let symbol: String
    let displaysRawQuota: Bool

    init(status: NewAPIStatus?) {
        let quotaPerUnit = status?.quotaPerUnit ?? 500_000
        self.quotaPerUnit = quotaPerUnit > 0 ? quotaPerUnit : 500_000

        let displayType = (status?.quotaDisplayType ?? "USD").uppercased()
        let usdRate = status?.usdExchangeRate ?? 1
        let customRate = status?.customCurrencyExchangeRate ?? 1

        switch displayType {
        case "CNY":
            exchangeRate = usdRate > 0 ? usdRate : 1
            symbol = "¥"
            displaysRawQuota = false
        case "CUSTOM":
            exchangeRate = customRate > 0 ? customRate : 1
            let customSymbol = (status?.customCurrencySymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            symbol = customSymbol.isEmpty ? "单位" : customSymbol
            displaysRawQuota = false
        case "TOKENS":
            exchangeRate = 1
            symbol = "额度"
            displaysRawQuota = true
        default:
            exchangeRate = 1
            symbol = "$"
            displaysRawQuota = false
        }
    }

    func convert(_ rawQuota: Decimal) -> Decimal {
        displaysRawQuota ? rawQuota : rawQuota / quotaPerUnit * exchangeRate
    }
}

private struct NewAPIStatus: Decodable {
    let quotaPerUnit: Decimal?
    let quotaDisplayType: String?
    let usdExchangeRate: Decimal?
    let customCurrencyExchangeRate: Decimal?
    let customCurrencySymbol: String?

    private enum CodingKeys: String, CodingKey {
        case quotaPerUnit = "quota_per_unit"
        case quotaDisplayType = "quota_display_type"
        case usdExchangeRate = "usd_exchange_rate"
        case customCurrencyExchangeRate = "custom_currency_exchange_rate"
        case customCurrencySymbol = "custom_currency_symbol"
    }
}

private struct NewAPITokenSummary: Decodable, Sendable {
    let tokenUsed: Int?
    let requestCount: Int?
    let quota: Int?

    init(tokenUsed: Int? = nil, requestCount: Int? = nil, quota: Int? = nil) {
        self.tokenUsed = tokenUsed
        self.requestCount = requestCount
        self.quota = quota
    }

    private enum CodingKeys: String, CodingKey {
        case tokenUsed = "token_used"
        case requestCount = "count"
        case quota
    }
}

private struct NewAPIEnvelope<Value: Decodable>: Decodable {
    let success: Bool?
    let message: String?
    let data: Value?
}

private struct NewAPIUser: Decodable {
    let quota: Decimal
    let usedQuota: Decimal
    let requestCount: Int
    let group: String?

    private enum CodingKeys: String, CodingKey {
        case quota
        case usedQuota = "used_quota"
        case requestCount = "request_count"
        case group
    }
}

private struct NewAPIStat: Decodable {
    let quota: Decimal
    let rpm: Int
    let tpm: Int
}
