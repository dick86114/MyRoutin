import Foundation

enum UsageMapperError: Error, Equatable {
    case invalidLimit
}

struct UsageMapper: Sendable {
    func map(_ dto: UsageResponseDTO, fetchedAt: Date) throws -> UsageSnapshot {
        let hasPeriodicLimit = hasValidLimit(dto.dailyLimitUsd) || hasValidLimit(dto.weeklyLimitUsd)
        let hasTokenLimit = hasValidLimit(dto.totalTokens)
        let kind = try usageKind(
            type: dto.type,
            hasPeriodicLimit: hasPeriodicLimit,
            hasTokenLimit: hasTokenLimit
        )
        let groupMultipliers = pairedGroupMultipliers(
            names: dto.groupNames,
            multipliers: dto.groupMultipliers
        )

        switch kind {
        case .periodic:
            let fiveHour = try metric(
                limit: dto.dailyLimitUsd,
                used: dto.dailyUsedUsd,
                remaining: dto.dailyRemainingUsd,
                unit: .usd,
                windowEnd: date(from: dto.dayWindowEndAt)
            )
            let weekly = try metric(
                limit: dto.weeklyLimitUsd,
                used: dto.weeklyUsedUsd,
                remaining: dto.weeklyRemainingUsd,
                unit: .usd,
                windowEnd: date(from: dto.weekWindowEndAt)
            )
            return UsageSnapshot(
                planName: dto.planName ?? "",
                subscriptionId: dto.subscriptionId,
                planId: dto.planId,
                kind: .periodic,
                fiveHour: fiveHour,
                weekly: weekly,
                token: nil,
                allowedModels: dto.allowedModels ?? [],
                fetchedAt: fetchedAt,
                groupMultiplier: groupMultipliers.first?.multiplier,
                groupMultipliers: groupMultipliers,
                status: dto.status,
                subscriptionStartAt: date(from: dto.startAt),
                subscriptionEndAt: date(from: dto.endAt),
                metrics: [
                    normalizedMetric(id: "fiveHour", label: "5 小时", metric: fiveHour),
                    normalizedMetric(id: "weekly", label: "周", metric: weekly)
                ].compactMap { $0 }
            )
        case .tokenPack:
            let token = try metric(
                limit: dto.totalTokens,
                used: dto.consumedTokens,
                remaining: dto.remainingTokens,
                unit: .token,
                windowEnd: nil
            )
            return UsageSnapshot(
                planName: dto.planName ?? "",
                subscriptionId: dto.subscriptionId,
                planId: dto.planId,
                kind: .tokenPack,
                fiveHour: nil,
                weekly: nil,
                token: token,
                allowedModels: dto.allowedModels ?? [],
                fetchedAt: fetchedAt,
                groupMultiplier: groupMultipliers.first?.multiplier,
                groupMultipliers: groupMultipliers,
                status: dto.status,
                subscriptionStartAt: date(from: dto.startAt),
                subscriptionEndAt: date(from: dto.endAt),
                metrics: [
                    normalizedMetric(id: "token", label: "Token", metric: token)
                ].compactMap { $0 }
            )
        }
    }

    private func usageKind(
        type: Int?,
        hasPeriodicLimit: Bool,
        hasTokenLimit: Bool
    ) throws -> UsageKind {
        if hasTokenLimit && !hasPeriodicLimit {
            return .tokenPack
        }
        if hasPeriodicLimit && type == 1 {
            return .periodic
        }
        if hasTokenLimit && hasPeriodicLimit && type != 1 {
            return .tokenPack
        }
        if hasPeriodicLimit {
            return .periodic
        }
        throw UsageMapperError.invalidLimit
    }

    private func metric(
        limit: Decimal?,
        used: Decimal?,
        remaining: Decimal?,
        unit: UsageUnit,
        windowEnd: Date?
    ) throws -> UsageMetric? {
        guard let limit, hasValidLimit(limit) else {
            return nil
        }
        guard used != nil || remaining != nil else {
            return nil
        }

        let resolvedUsed = used ?? (remaining.map { limit - $0 } ?? 0)
        let resolvedRemaining = remaining ?? (limit - resolvedUsed)
        let percent = NSDecimalNumber(decimal: resolvedUsed)
            .dividing(by: NSDecimalNumber(decimal: limit))
            .multiplying(by: 100)
            .doubleValue

        return UsageMetric(
            used: resolvedUsed,
            limit: limit,
            remaining: resolvedRemaining,
            percent: percent,
            unit: unit,
            windowEnd: windowEnd
        )
    }

    private func hasValidLimit(_ value: Decimal?) -> Bool {
        guard let value else {
            return false
        }
        return value > 0
    }

    private func normalizedMetric(
        id: String,
        label: String,
        metric: UsageMetric?
    ) -> NormalizedUsageMetric? {
        guard let metric else { return nil }
        return NormalizedUsageMetric(
            id: id,
            label: label,
            used: metric.used,
            limit: metric.limit,
            remaining: metric.remaining,
            unit: metric.unit == .token ? .token : .currency,
            windowEnd: metric.windowEnd,
            presentation: .progress,
            semantic: .usedQuota,
            currencyCode: metric.unit == .usd ? "USD" : nil
        )
    }

    private func pairedGroupMultipliers(
        names: UsageKeyedValues<String>?,
        multipliers: UsageKeyedValues<Decimal>?
    ) -> [UsageGroupMultiplier] {
        guard let names, let multipliers else { return [] }
        return names.keys.compactMap { key in
            guard let name = names.values[key], let multiplier = multipliers.values[key] else {
                return nil
            }
            return UsageGroupMultiplier(name: name, multiplier: multiplier)
        }
    }

    private func date(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let fractionalSecondsFormatter = ISO8601DateFormatter()
        fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalSecondsFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
