import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case routin
    case deepseek
    case glm
    case volcengine
    case newAPI
    case commandCode

    var id: String { rawValue }
}

enum CredentialKind: String, Codable, Sendable {
    case bearerAPIKey
    case apiKey
    case accessKeyPair
}

struct ProviderCapability: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let quotaWindow = Self(rawValue: 1 << 0)
    static let balance = Self(rawValue: 1 << 1)
    static let tokenUsage = Self(rawValue: 1 << 2)
    static let modelBreakdown = Self(rawValue: 1 << 3)
    static let toolBreakdown = Self(rawValue: 1 << 4)
    static let resetTime = Self(rawValue: 1 << 5)
    static let planDetection = Self(rawValue: 1 << 6)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

struct CredentialField: Codable, Equatable, Hashable, Sendable {
    let id: String
    let label: String
    let isSecret: Bool
    let isRequired: Bool
    let placeholder: String?

    init(
        id: String,
        label: String,
        isSecret: Bool,
        isRequired: Bool = true,
        placeholder: String? = nil
    ) {
        self.id = id
        self.label = label
        self.isSecret = isSecret
        self.isRequired = isRequired
        self.placeholder = placeholder
    }
}

struct ProviderDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: ProviderID
    let displayName: String
    let shortCode: String
    let iconName: String
    let capabilities: ProviderCapability
    let credentialSchemas: [CredentialKind: [CredentialField]]

    var identifier: ProviderID { id }

    init(
        id: ProviderID,
        displayName: String,
        shortCode: String,
        iconName: String,
        capabilities: ProviderCapability,
        credentialSchemas: [CredentialKind: [CredentialField]]
    ) {
        self.id = id
        self.displayName = displayName
        self.shortCode = shortCode
        self.iconName = iconName
        self.capabilities = capabilities
        self.credentialSchemas = credentialSchemas
    }
}

struct ProviderCredential: Sendable {
    let credentialID: UUID?
    let providerID: ProviderID
    let kind: CredentialKind
    let secret: String
    let secondarySecret: String?
    let metadata: [String: String]

    init(
        credentialID: UUID? = nil,
        providerID: ProviderID,
        kind: CredentialKind,
        secret: String,
        secondarySecret: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.credentialID = credentialID
        self.providerID = providerID
        self.kind = kind
        self.secret = secret
        self.secondarySecret = secondarySecret
        self.metadata = metadata
    }
}
