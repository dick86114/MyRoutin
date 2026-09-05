import Foundation

struct RoutinUsageProvider: UsageProvider {
    let descriptor: ProviderDescriptor
    private let client: any UsageFetching

    init(client: any UsageFetching) {
        self.client = client
        self.descriptor = ProviderRegistry.builtInDescriptors.first(where: { $0.id == .routin })!
    }

    func metricCapabilities(for configuration: KeyConfiguration) -> [UsageMetricCapability] {
        guard configuration.credentialKind == .bearerAPIKey else { return [] }
        if configuration.metadata["usageKind"] == "tokenPack" {
            return [
                UsageMetricCapability(
                    metricID: "token",
                    label: "Token",
                    presentation: .progress,
                    semantic: .usedQuota,
                    isMenuBarSelectable: true,
                    menuBarPriority: 0,
                    defaultAlertEnabled: true,
                    defaultAbsoluteAlertThreshold: nil
                )
            ]
        }
        return [
            UsageMetricCapability(
                metricID: "fiveHour",
                label: "5 小时",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 0,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            ),
            UsageMetricCapability(
                metricID: "weekly",
                label: "周",
                presentation: .progress,
                semantic: .usedQuota,
                isMenuBarSelectable: true,
                menuBarPriority: 1,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            )
        ]
    }

    func validate(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        try await fetchUsage(credential, now: now)
    }

    func fetchUsage(_ credential: ProviderCredential, now: Date) async throws -> UsageSnapshot? {
        guard credential.providerID == .routin, credential.kind == .bearerAPIKey else {
            throw UsageProviderError.invalidCredential
        }
        do {
            return try await client.fetchUsage(apiKey: credential.secret, now: now)?
                .assigningIdentity(providerID: .routin, credentialID: credential.credentialID)
        } catch let error as UsageAPIError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: UsageAPIError) -> UsageProviderError {
        switch error {
        case .invalidKey:
            return .unauthorized
        case .transport:
            return .transport
        case .invalidResponse:
            return .invalidResponse
        case let .server(statusCode):
            if statusCode == 429 { return .rateLimited }
            if (500...599).contains(statusCode) { return .providerUnavailable }
            return .invalidResponse
        }
    }
}
