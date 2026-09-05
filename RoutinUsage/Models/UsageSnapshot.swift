import Foundation

enum UsageKind: String, Codable, Equatable, Sendable {
    case periodic
    case tokenPack
}

enum UsageUnit: String, Codable, Equatable, Sendable {
    case usd
    case token
}

enum UsageDimension: String, Codable, Equatable, Sendable {
    case fiveHour
    case weekly
    case token
    case balance
}

enum DisplayDimension: String, Codable, Equatable, Sendable, CaseIterable {
    case fiveHour
    case weekly
}

enum NormalizedUsageMetricPresentation: String, Codable, Equatable, Sendable {
    case progress
    case balance
    case status
    case value
}

enum NormalizedUsageMetricSemantic: String, Codable, Equatable, Sendable {
    case usedQuota
    case remainingQuota
    case balance
    case status
    case value
}

enum UsageMetricUnit: String, Codable, Equatable, Sendable {
    case token
    case currency
    case request
    case boolean
    case text
}

enum UsageMetricHealthState: String, Codable, Equatable, Sendable {
    case normal
    case warning
    case critical
    case unavailable
    case stale
    case unknown
}

enum UsageMetricHealthEvaluator {
    static func balanceState(
        balance: Decimal,
        warningThreshold: Decimal?,
        isAvailable: Bool
    ) -> UsageMetricHealthState {
        guard isAvailable else { return .unavailable }
        guard balance > 0 else { return .critical }
        if let warningThreshold, warningThreshold > 0, balance < warningThreshold {
            return .warning
        }
        return .normal
    }
}

struct NormalizedUsageMetric: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let used: Decimal?
    let limit: Decimal?
    let remaining: Decimal?
    let value: Decimal?
    let unit: UsageMetricUnit
    let windowStart: Date?
    let windowEnd: Date?
    let presentation: NormalizedUsageMetricPresentation
    let semantic: NormalizedUsageMetricSemantic
    let currencyCode: String?
    let healthState: UsageMetricHealthState

    var displayedPercent: Double? {
        guard let limit, limit > 0 else { return nil }
        let amount: Decimal
        switch semantic {
        case .usedQuota:
            guard let used else { return nil }
            amount = used
        case .remainingQuota:
            guard let remaining else { return nil }
            amount = remaining
        case .balance, .status, .value:
            return nil
        }
        return NSDecimalNumber(decimal: amount)
            .dividing(by: NSDecimalNumber(decimal: limit))
            .multiplying(by: 100)
            .doubleValue
    }

    var displaysRemainingPercent: Bool {
        semantic == .remainingQuota
    }

    init(
        id: String,
        label: String,
        used: Decimal? = nil,
        limit: Decimal? = nil,
        remaining: Decimal? = nil,
        value: Decimal? = nil,
        unit: UsageMetricUnit,
        windowStart: Date? = nil,
        windowEnd: Date? = nil,
        presentation: NormalizedUsageMetricPresentation,
        semantic: NormalizedUsageMetricSemantic,
        currencyCode: String? = nil,
        healthState: UsageMetricHealthState = .unknown
    ) {
        self.id = id
        self.label = label
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.value = value
        self.unit = unit
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.presentation = presentation
        self.semantic = semantic
        self.currencyCode = currencyCode
        self.healthState = healthState
    }

    func withID(_ id: String) -> NormalizedUsageMetric {
        NormalizedUsageMetric(
            id: id,
            label: label,
            used: used,
            limit: limit,
            remaining: remaining,
            value: value,
            unit: unit,
            windowStart: windowStart,
            windowEnd: windowEnd,
            presentation: presentation,
            semantic: semantic,
            currencyCode: currencyCode,
            healthState: healthState
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case used
        case limit
        case remaining
        case value
        case unit
        case windowStart
        case windowEnd
        case presentation
        case semantic
        case currencyCode
        case healthState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let label = try container.decode(String.self, forKey: .label)
        let presentation = try container.decode(NormalizedUsageMetricPresentation.self, forKey: .presentation)

        self.id = id
        self.label = label
        used = try container.decodeIfPresent(Decimal.self, forKey: .used)
        limit = try container.decodeIfPresent(Decimal.self, forKey: .limit)
        remaining = try container.decodeIfPresent(Decimal.self, forKey: .remaining)
        value = try container.decodeIfPresent(Decimal.self, forKey: .value)
        unit = try container.decode(UsageMetricUnit.self, forKey: .unit)
        windowStart = try container.decodeIfPresent(Date.self, forKey: .windowStart)
        windowEnd = try container.decodeIfPresent(Date.self, forKey: .windowEnd)
        self.presentation = presentation
        semantic = try container.decodeIfPresent(NormalizedUsageMetricSemantic.self, forKey: .semantic)
            ?? Self.legacySemantic(id: id, label: label, presentation: presentation)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
        healthState = try container.decodeIfPresent(UsageMetricHealthState.self, forKey: .healthState) ?? .unknown
    }

    private static func legacySemantic(
        id: String,
        label: String,
        presentation: NormalizedUsageMetricPresentation
    ) -> NormalizedUsageMetricSemantic {
        switch presentation {
        case .balance: return .balance
        case .status: return .status
        case .value: return .value
        case .progress:
            return id.localizedCaseInsensitiveContains("remaining") || label.contains("剩余")
                ? .remainingQuota
                : .usedQuota
        }
    }
}

struct UsageMetric: Codable, Equatable, Sendable {
    let used: Decimal
    let limit: Decimal
    let remaining: Decimal
    let percent: Double
    let unit: UsageUnit
    let windowEnd: Date?
}

struct UsageGroupMultiplier: Codable, Equatable, Sendable {
    let name: String
    let multiplier: Decimal
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    let providerID: ProviderID?
    let credentialID: UUID?
    let subscriptionId: String?
    let planId: String?
    let planName: String
    let kind: UsageKind
    let fiveHour: UsageMetric?
    let weekly: UsageMetric?
    let token: UsageMetric?
    let allowedModels: [String]
    let fetchedAt: Date
    /// 当前订阅分组的计费倍率；资源包或旧缓存可能没有该数据。
    let groupMultiplier: Decimal?
    /// 按接口返回顺序配对的订阅分组和计费倍率；旧缓存缺少时为空。
    let groupMultipliers: [UsageGroupMultiplier]
    let status: Int?
    let subscriptionStartAt: Date?
    let subscriptionEndAt: Date?
    let metrics: [NormalizedUsageMetric]

    var normalizedMetrics: [NormalizedUsageMetric] {
        if !metrics.isEmpty {
            return metrics
        }

        var result: [NormalizedUsageMetric] = []
        if let fiveHour {
            result.append(NormalizedUsageMetric(
                id: "fiveHour",
                label: "5 小时",
                used: fiveHour.used,
                limit: fiveHour.limit,
                remaining: fiveHour.remaining,
                unit: fiveHour.unit == .token ? .token : .currency,
                windowEnd: fiveHour.windowEnd,
                presentation: .progress,
                semantic: .usedQuota,
                currencyCode: fiveHour.unit == .usd ? "USD" : nil
            ))
        }
        if let weekly {
            result.append(NormalizedUsageMetric(
                id: "weekly",
                label: "周",
                used: weekly.used,
                limit: weekly.limit,
                remaining: weekly.remaining,
                unit: weekly.unit == .token ? .token : .currency,
                windowEnd: weekly.windowEnd,
                presentation: .progress,
                semantic: .usedQuota,
                currencyCode: weekly.unit == .usd ? "USD" : nil
            ))
        }
        if let token {
            result.append(NormalizedUsageMetric(
                id: "token",
                label: "Token",
                used: token.used,
                limit: token.limit,
                remaining: token.remaining,
                unit: .token,
                presentation: .progress,
                semantic: .usedQuota
            ))
        }
        return result
    }

    func assigningIdentity(providerID: ProviderID, credentialID: UUID?) -> UsageSnapshot {
        UsageSnapshot(
            planName: planName,
            subscriptionId: subscriptionId,
            planId: planId,
            kind: kind,
            fiveHour: fiveHour,
            weekly: weekly,
            token: token,
            allowedModels: allowedModels,
            fetchedAt: fetchedAt,
            groupMultiplier: groupMultiplier,
            groupMultipliers: groupMultipliers,
            status: status,
            subscriptionStartAt: subscriptionStartAt,
            subscriptionEndAt: subscriptionEndAt,
            providerID: providerID,
            credentialID: credentialID,
            metrics: metrics
        )
    }

    init(
        planName: String,
        subscriptionId: String? = nil,
        planId: String? = nil,
        kind: UsageKind,
        fiveHour: UsageMetric?,
        weekly: UsageMetric?,
        token: UsageMetric?,
        allowedModels: [String],
        fetchedAt: Date,
        groupMultiplier: Decimal? = nil,
        groupMultipliers: [UsageGroupMultiplier] = [],
        status: Int? = nil,
        subscriptionStartAt: Date? = nil,
        subscriptionEndAt: Date? = nil,
        providerID: ProviderID? = nil,
        credentialID: UUID? = nil,
        metrics: [NormalizedUsageMetric] = []
    ) {
        self.providerID = providerID
        self.credentialID = credentialID
        self.subscriptionId = subscriptionId
        self.planId = planId
        self.planName = planName
        self.kind = kind
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.token = token
        self.allowedModels = allowedModels
        self.fetchedAt = fetchedAt
        self.groupMultiplier = groupMultiplier
        self.groupMultipliers = groupMultipliers
        self.status = status
        self.subscriptionStartAt = subscriptionStartAt
        self.subscriptionEndAt = subscriptionEndAt
        self.metrics = metrics
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case credentialID
        case planName
        case subscriptionId
        case planId
        case kind
        case fiveHour
        case weekly
        case token
        case allowedModels
        case fetchedAt
        case groupMultiplier
        case groupMultipliers
        case status
        case subscriptionStartAt
        case subscriptionEndAt
        case metrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decodeIfPresent(ProviderID.self, forKey: .providerID)
        credentialID = try container.decodeIfPresent(UUID.self, forKey: .credentialID)
        planName = try container.decode(String.self, forKey: .planName)
        subscriptionId = try container.decodeIfPresent(String.self, forKey: .subscriptionId)
        planId = try container.decodeIfPresent(String.self, forKey: .planId)
        kind = try container.decode(UsageKind.self, forKey: .kind)
        fiveHour = try container.decodeIfPresent(UsageMetric.self, forKey: .fiveHour)
        weekly = try container.decodeIfPresent(UsageMetric.self, forKey: .weekly)
        token = try container.decodeIfPresent(UsageMetric.self, forKey: .token)
        allowedModels = try container.decode([String].self, forKey: .allowedModels)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        groupMultiplier = try container.decodeIfPresent(Decimal.self, forKey: .groupMultiplier)
        groupMultipliers = try container.decodeIfPresent([UsageGroupMultiplier].self, forKey: .groupMultipliers) ?? []
        status = try container.decodeIfPresent(Int.self, forKey: .status)
        subscriptionStartAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionStartAt)
        subscriptionEndAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionEndAt)
        let decodedMetrics = try container.decodeIfPresent([NormalizedUsageMetric].self, forKey: .metrics) ?? []
        var seenIDs: [String: Int] = [:]
        metrics = decodedMetrics.enumerated().map { index, metric in
            let count = seenIDs[metric.id, default: 0]
            seenIDs[metric.id] = count + 1
            return count == 0 ? metric : metric.withID("\(metric.id)-\(index)")
        }
    }
}
