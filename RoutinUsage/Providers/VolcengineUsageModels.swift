import Foundation

struct VolcengineUsageWindow: Decodable, Sendable {
    let quota: Decimal
    let used: Decimal
    let resetTime: Date?
    let subscribeTime: Date?

    private enum CodingKeys: String, CodingKey {
        case quota = "Quota"
        case used = "Used"
        case resetTime = "ResetTime"
        case subscribeTime = "SubscribeTime"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quota = try Self.decimal(container, key: .quota)
        used = try Self.decimal(container, key: .used)
        resetTime = Self.date(try container.decodeIfPresent(Int64.self, forKey: .resetTime))
        subscribeTime = Self.date(try container.decodeIfPresent(Int64.self, forKey: .subscribeTime))
    }

    private static func decimal(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Decimal {
        if let value = try? container.decode(Decimal.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key), let decimal = Decimal(string: value) { return decimal }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "无法解析 AFP 数值")
    }

    private static func date(_ milliseconds: Int64?) -> Date? {
        guard let milliseconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}

struct VolcengineUsageResult: Decodable, Sendable {
    let afpDaily: VolcengineUsageWindow?
    let afpFiveHour: VolcengineUsageWindow?
    let afpMonthly: VolcengineUsageWindow?
    let afpWeekly: VolcengineUsageWindow?
    let planType: String?
    let quotaUsage: [VolcengineCodingUsageItem]

    private enum CodingKeys: String, CodingKey {
        case afpDaily = "AFPDaily"
        case afpFiveHour = "AFPFiveHour"
        case afpMonthly = "AFPMonthly"
        case afpWeekly = "AFPWeekly"
        case planType = "PlanType"
        case quotaUsage = "QuotaUsage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        afpDaily = try container.decodeIfPresent(VolcengineUsageWindow.self, forKey: .afpDaily)
        afpFiveHour = try container.decodeIfPresent(VolcengineUsageWindow.self, forKey: .afpFiveHour)
        afpMonthly = try container.decodeIfPresent(VolcengineUsageWindow.self, forKey: .afpMonthly)
        afpWeekly = try container.decodeIfPresent(VolcengineUsageWindow.self, forKey: .afpWeekly)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        quotaUsage = try container.decodeIfPresent([VolcengineCodingUsageItem].self, forKey: .quotaUsage) ?? []
    }
}

struct VolcengineCodingUsageItem: Decodable, Sendable {
    let level: String
    let percent: Decimal
    let resetTimestamp: Int64?

    private enum CodingKeys: String, CodingKey {
        case level = "Level"
        case percent = "Percent"
        case resetTimestamp = "ResetTimestamp"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(String.self, forKey: .level) ?? "Coding Plan"
        if let value = try? container.decode(Decimal.self, forKey: .percent) {
            percent = value
        } else {
            let value = try container.decode(String.self, forKey: .percent)
            guard let decimal = Decimal(string: value) else {
                throw DecodingError.dataCorruptedError(forKey: .percent, in: container, debugDescription: "无法解析用量百分比")
            }
            percent = decimal
        }
        resetTimestamp = try container.decodeIfPresent(Int64.self, forKey: .resetTimestamp)
    }
}

struct VolcengineUsageResponse: Decodable, Sendable {
    let result: VolcengineUsageResult?

    private enum CodingKeys: String, CodingKey {
        case result = "Result"
    }
}

struct VolcenginePersonalPlanResponse: Decodable, Sendable {
    let result: VolcenginePersonalPlanResult?

    private enum CodingKeys: String, CodingKey {
        case result = "Result"
    }
}

struct VolcenginePersonalPlanResult: Decodable, Sendable {
    let planType: String?
    let status: String?
    let autoRenew: Bool?
    let startTime: String?
    let endTime: String?

    private enum CodingKeys: String, CodingKey {
        case planType = "PlanType"
        case status = "Status"
        case autoRenew = "AutoRenew"
        case startTime = "StartTime"
        case endTime = "EndTime"
    }
}

struct VolcenginePlanModelResponse: Decodable, Sendable {
    let result: VolcenginePlanModelResult?

    private enum CodingKeys: String, CodingKey {
        case result = "Result"
    }
}

struct VolcenginePlanModelResult: Decodable, Sendable {
    let models: [VolcenginePlanModel]

    private enum CodingKeys: String, CodingKey {
        case models = "Datas"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([VolcenginePlanModel].self, forKey: .models) ?? []
    }
}

struct VolcenginePlanModel: Decodable, Sendable {
    let modelID: String?

    private enum CodingKeys: String, CodingKey {
        case modelID = "ModelID"
    }
}
