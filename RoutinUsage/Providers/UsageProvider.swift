import Foundation

protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability]
    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot?
    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot?
}

extension UsageProvider {
    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] { [] }
}

enum UsageProviderError: LocalizedError, Equatable, Sendable {
    case invalidCredential
    case unauthorized
    case rateLimited
    case transport
    case timeout
    case invalidResponse
    case providerUnavailable
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "凭证字段不完整，请检查输入"
        case .unauthorized:
            return "凭证无效或没有该供应商权限"
        case .rateLimited:
            return "请求过于频繁，请稍后重试"
        case .transport:
            return "网络连接失败，请检查网络后重试"
        case .timeout:
            return "请求超时，请稍后重试"
        case .invalidResponse:
            return "供应商返回的数据无法识别"
        case .providerUnavailable:
            return "供应商服务暂时不可用"
        case let .providerMessage(message):
            return message
        }
    }
}

struct ProviderRegistry: Sendable {
    private let providers: [ProviderID: any UsageProvider]

    init(providers: [any UsageProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.descriptor.id, $0) })
    }

    func provider(for id: ProviderID) -> (any UsageProvider)? {
        providers[id]
    }

    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] {
        provider(for: configuration.providerID)?.metricCapabilities(for: configuration) ?? []
    }

    static let builtInDescriptors: [ProviderDescriptor] = [
        ProviderDescriptor(
            id: .routin,
            displayName: "Routin",
            shortCode: "ROU",
            iconName: "circle.hexagongrid",
            capabilities: [.quotaWindow, .tokenUsage, .resetTime, .planDetection],
            credentialSchemas: [
                .bearerAPIKey: [CredentialField(id: "secret", label: "plan Key", isSecret: true)]
            ]
        ),
        ProviderDescriptor(
            id: .deepseek,
            displayName: "DeepSeek",
            shortCode: "DS",
            iconName: "d.circle",
            capabilities: [.balance],
            credentialSchemas: [
                .apiKey: [CredentialField(id: "secret", label: "API Key", isSecret: true)]
            ]
        ),
        ProviderDescriptor(
            id: .glm,
            displayName: "GLM",
            shortCode: "GLM",
            iconName: "g.circle",
            capabilities: [.quotaWindow, .tokenUsage, .modelBreakdown, .toolBreakdown, .resetTime],
            credentialSchemas: [
                .apiKey: [CredentialField(id: "secret", label: "API Key", isSecret: true)]
            ]
        ),
        ProviderDescriptor(
            id: .volcengine,
            displayName: "火山方舟",
            shortCode: "VOL",
            iconName: "cloud",
            capabilities: [.quotaWindow, .tokenUsage, .resetTime, .planDetection],
            credentialSchemas: [
                .accessKeyPair: [
                    CredentialField(id: "accessKeyID", label: "AccessKey ID", isSecret: false),
                    CredentialField(id: "secretAccessKey", label: "SecretAccessKey", isSecret: true),
                    CredentialField(id: "region", label: "区域", isSecret: false, isRequired: false, placeholder: "cn-beijing")
                ]
            ]
        ),
        ProviderDescriptor(
            id: .newAPI,
            displayName: "New API",
            shortCode: "NEW",
            iconName: "server.rack",
            capabilities: [.balance, .tokenUsage],
            credentialSchemas: [
                .bearerAPIKey: [
                    CredentialField(id: "baseURL", label: "New API 地址", isSecret: false),
                    CredentialField(id: "userID", label: "用户 ID", isSecret: false),
                    CredentialField(id: "secret", label: "用户访问令牌", isSecret: true)
                ]
            ]
        )
    ]
}
