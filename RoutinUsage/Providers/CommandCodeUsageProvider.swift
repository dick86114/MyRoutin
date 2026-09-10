import Foundation

struct CommandCodeUsageProvider: UsageProvider {
    static let baseURL = URL(string: "https://api.commandcode.ai")!

    let descriptor: ProviderDescriptor
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        self.descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .commandCode })!
    }

    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] {
        guard configuration.credentialKind == .bearerAPIKey else { return [] }
        let warningThreshold = configuration.metadata["balanceWarningThreshold"]
            .flatMap { Decimal(string: $0) }
        return [
            UsageMetricCapability(
                metricID: "credit-progress",
                label: "月",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 0,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: warningThreshold
            ),
            UsageMetricCapability(
                metricID: "five-hour",
                label: "5 小时",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 1,
                defaultAlertEnabled: false,
                defaultAbsoluteAlertThreshold: nil
            ),
            UsageMetricCapability(
                metricID: "weekly",
                label: "周",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 2,
                defaultAlertEnabled: false,
                defaultAbsoluteAlertThreshold: nil
            ),
            valueCapability(metricID: "credit-balance", label: "剩余额度"),
            valueCapability(metricID: "monthly-remaining", label: "月度剩余"),
            valueCapability(metricID: "purchased-remaining", label: "购买剩余"),
            valueCapability(metricID: "free-remaining", label: "赠送剩余"),
            valueCapability(metricID: "period-spent", label: "本周期消费"),
            valueCapability(metricID: "request-count", label: "累计请求")
        ]
    }

    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        try await fetchUsage(credential, now: now)
    }

    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        guard credential.providerID == .commandCode,
              credential.kind == .bearerAPIKey,
              !credential.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw UsageProviderError.invalidCredential }

        let whoami: CommandCodeWhoami
        let creditsResponse: CommandCodeCreditsResponse
        let subscriptionResponse: CommandCodeSubscriptionResponse
        do {
            whoami = try await request(
                "/alpha/whoami",
                query: [URLQueryItem(name: "limits", value: "1")],
                credential: credential
            )
            let orgID = whoami.org?.id
            creditsResponse = try await request(
                "/alpha/billing/credits",
                query: [URLQueryItem(name: "orgId", value: orgID)],
                credential: credential
            )
            subscriptionResponse = try await request(
                "/alpha/billing/subscriptions",
                query: [URLQueryItem(name: "orgId", value: orgID)],
                credential: credential
            )
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.invalidResponse
        }

        guard let credits = creditsResponse.credits else {
            throw UsageProviderError.providerMessage("Command Code：额度信息返回失败")
        }
        let subscription = subscriptionResponse.data
        let currentPeriodStart = subscription?.currentPeriodStart
        let summary: CommandCodeUsageSummary
        do {
            summary = try await request(
                "/alpha/usage/summary",
                query: [
                    URLQueryItem(name: "orgId", value: whoami.org?.id),
                    URLQueryItem(name: "since", value: currentPeriodStart)
                ],
                credential: credential
            )
        } catch let error as UsageProviderError {
            throw error
        } catch {
            throw UsageProviderError.invalidResponse
        }

        let monthlyRemaining = max(0, credits.monthlyCredits ?? 0)
        let allowedModels: [String]
        do {
            let models: CommandCodeModelsResponse = try await request(
                "/provider/v1/models",
                query: [],
                credential: credential
            )
            allowedModels = models.data.compactMap {
                let id = $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                return id.isEmpty ? nil : id
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            allowedModels = []
        }
        let purchasedRemaining = max(0, credits.purchasedCredits ?? 0)
        let freeRemaining = max(0, credits.freeCredits ?? 0)
        let totalRemaining = monthlyRemaining + purchasedRemaining + freeRemaining
        let totalSpent = max(0, summary.totalCost ?? 0)
        let plan = CommandCodePlanInfo(planID: subscription?.planID)
        let isActivePlan = subscription?.status == "active" || subscription?.status == "trialing"
        let totalPool: Decimal
        if isActivePlan, let monthlyAllowance = plan.monthlyCredits {
            totalPool = max(monthlyAllowance, monthlyRemaining) + purchasedRemaining + freeRemaining
        } else {
            totalPool = totalSpent + totalRemaining
        }
        let totalUsed = max(0, totalPool - totalRemaining)
        let warningThreshold = credential.metadata["balanceWarningThreshold"]
            .flatMap { Decimal(string: $0) }
        let health = UsageMetricHealthEvaluator.balanceState(
            balance: totalRemaining,
            warningThreshold: warningThreshold,
            isAvailable: true
        )

        var metrics = [
            progressMetric(
                id: "credit-progress",
                label: "月",
                used: totalUsed,
                limit: totalPool,
                remaining: totalRemaining,
                healthState: health
            ),
            valueMetric(id: "credit-balance", label: "剩余额度", value: totalRemaining, health: health),
            valueMetric(id: "monthly-remaining", label: "月度剩余", value: monthlyRemaining, health: health),
            valueMetric(id: "purchased-remaining", label: "购买剩余", value: purchasedRemaining, health: health),
            valueMetric(id: "free-remaining", label: "赠送剩余", value: freeRemaining, health: health),
            valueMetric(id: "period-spent", label: "本周期消费", value: totalSpent, health: .normal),
            valueMetric(
                id: "request-count",
                label: "累计请求",
                value: Decimal(max(0, summary.totalCount ?? 0)),
                health: .normal
            )
        ]
        metrics.append(contentsOf: windowMetrics(from: creditsResponse.windowLimits))

        return UsageSnapshot(
            planName: plan.name,
            planId: subscription?.planID,
            kind: .periodic,
            fiveHour: nil,
            weekly: nil,
            token: nil,
            allowedModels: allowedModels,
            fetchedAt: now,
            statusText: CommandCodePlanInfo.statusText(subscription?.status),
            billingMode: subscription?.status,
            subscriptionStartAt: Self.date(currentPeriodStart),
            subscriptionEndAt: Self.date(subscription?.currentPeriodEnd),
            providerID: .commandCode,
            credentialID: credential.credentialID,
            metrics: metrics
        )
    }

    private func windowMetrics(
        from limits: CommandCodeWindowLimits?
    ) -> [NormalizedUsageMetric] {
        guard limits?.limited == true else { return [] }
        var metrics: [NormalizedUsageMetric] = []
        if let fiveHour = limits?.fiveHour {
            metrics.append(windowMetric(id: "five-hour", label: "5 小时", limit: fiveHour))
        }
        if let weekly = limits?.weekly {
            metrics.append(windowMetric(id: "weekly", label: "周", limit: weekly))
        }
        return metrics
    }

    private func windowMetric(
        id: String,
        label: String,
        limit: CommandCodeUsageWindow
    ) -> NormalizedUsageMetric {
        let used = max(0, limit.used ?? 0)
        let cap = max(0, limit.cap ?? 0)
        return NormalizedUsageMetric(
            id: id,
            label: label,
            used: used,
            limit: cap,
            remaining: max(0, cap - used),
            unit: .currency,
            windowEnd: Self.date(fromMilliseconds: limit.resetAt),
            presentation: .progress,
            semantic: .usedQuota,
            currencyCode: "$",
            healthState: .normal
        )
    }

    private func progressMetric(
        id: String,
        label: String,
        used: Decimal,
        limit: Decimal,
        remaining: Decimal,
        healthState: UsageMetricHealthState
    ) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: label,
            used: used,
            limit: limit,
            remaining: remaining,
            unit: .currency,
            presentation: .progress,
            semantic: .usedQuota,
            currencyCode: "$",
            healthState: healthState
        )
    }

    private func valueMetric(
        id: String,
        label: String,
        value: Decimal,
        health: UsageMetricHealthState
    ) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: label,
            value: value,
            unit: .currency,
            presentation: .value,
            semantic: .value,
            currencyCode: "$",
            healthState: health
        )
    }

    private func valueCapability(metricID: String, label: String) -> UsageMetricCapability {
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

    private func request<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem],
        credential: ProviderCredential
    ) async throws -> T {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.filter { $0.value != nil }
        guard let url = components?.url else { throw UsageProviderError.invalidCredential }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 15
        urlRequest.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
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
            case 401, 403:
                throw UsageProviderError.unauthorized
            case 429:
                throw UsageProviderError.rateLimited
            case 500...599:
                throw UsageProviderError.providerUnavailable
            default:
                throw UsageProviderError.invalidResponse
            }
        }

        if let errorEnvelope = try? JSONDecoder().decode(CommandCodeErrorEnvelope.self, from: data),
           errorEnvelope.success == false {
            throw UsageProviderError.providerMessage(
                "Command Code：\(errorEnvelope.error?.message ?? "请求返回失败")"
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            await AppLogStore.shared.log(
                level: .error,
                event: "command_code_decode_failed",
                details: "path=\(path) reason=\(error)"
            )
            throw UsageProviderError.invalidResponse
        }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func date(fromMilliseconds value: Double?) -> Date? {
        guard let value else { return nil }
        return Date(timeIntervalSince1970: value / 1_000)
    }
}

private struct CommandCodeErrorEnvelope: Decodable, Sendable {
    let success: Bool?
    let error: CommandCodeAPIError?
}

private struct CommandCodeAPIError: Decodable, Sendable {
    let message: String?
}

private struct CommandCodeWhoami: Decodable, Sendable {
    let user: CommandCodeUser?
    let org: CommandCodeOrg?
}

private struct CommandCodeUser: Decodable, Sendable {
    let id: String?
    let userName: String?
}

private struct CommandCodeOrg: Decodable, Sendable {
    let id: String?
    let login: String?
}

private struct CommandCodeCreditsResponse: Decodable, Sendable {
    let credits: CommandCodeCredits?
    let windowLimits: CommandCodeWindowLimits?
}

private struct CommandCodeCredits: Decodable, Sendable {
    let planID: String?
    let monthlyCredits: Decimal?
    let purchasedCredits: Decimal?
    let freeCredits: Decimal?

    private enum CodingKeys: String, CodingKey {
        case planID = "planId"
        case monthlyCredits
        case purchasedCredits
        case freeCredits
    }
}

private struct CommandCodeWindowLimits: Decodable, Sendable {
    let limited: Bool?
    let fiveHour: CommandCodeUsageWindow?
    let weekly: CommandCodeUsageWindow?
}

private struct CommandCodeUsageWindow: Decodable, Sendable {
    let used: Decimal?
    let cap: Decimal?
    let resetAt: Double?
}

private struct CommandCodeSubscriptionResponse: Decodable, Sendable {
    let data: CommandCodeSubscription?
}

private struct CommandCodeSubscription: Decodable, Sendable {
    let planID: String?
    let status: String?
    let currentPeriodStart: String?
    let currentPeriodEnd: String?

    private enum CodingKeys: String, CodingKey {
        case planID = "planId"
        case status
        case currentPeriodStart
        case currentPeriodEnd
    }
}

private struct CommandCodeUsageSummary: Decodable, Sendable {
    let totalCost: Decimal?
    let totalCount: Int?
}

private struct CommandCodeModelsResponse: Decodable, Sendable {
    let data: [CommandCodeModel]
}

private struct CommandCodeModel: Decodable, Sendable {
    let id: String
}

private struct CommandCodePlanInfo {
    static func statusText(_ status: String?) -> String? {
        switch status {
        case "active": return "有效"
        case "trialing": return "试用中"
        case "past_due": return "逾期"
        case "canceled", "cancelled": return "已取消"
        case let .some(value) where !value.isEmpty: return value
        case .some, .none: return nil
        }
    }

    let name: String
    let monthlyCredits: Decimal?

    init(planID: String?) {
        switch planID {
        case "individual-go":
            name = "Go"
            monthlyCredits = 10
        case "individual-goat":
            name = "GOAT"
            monthlyCredits = 70
        case "individual-pro", "individual-pro-v1":
            name = "Pro"
            monthlyCredits = planID == "individual-pro" ? 30 : 80
        case "individual-provider":
            name = "Provider"
            monthlyCredits = 15
        case "individual-max":
            name = "Max"
            monthlyCredits = 150
        case "individual-ultra":
            name = "Ultra"
            monthlyCredits = 300
        case "teams-pro":
            name = "Teams Pro"
            monthlyCredits = 40
        case let .some(planID):
            name = planID
            monthlyCredits = nil
        case .none:
            name = ""
            monthlyCredits = nil
        }
    }
}
