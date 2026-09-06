import Foundation

struct TransferPackageV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let credentials: [TransferCredential]
    let preferences: TransferPreferences
    let secretEnvelope: EncryptedSecretEnvelope?
    let exportedAt: Date

    init(
        schemaVersion: Int = 1,
        credentials: [TransferCredential],
        preferences: TransferPreferences,
        secretEnvelope: EncryptedSecretEnvelope?,
        exportedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.credentials = credentials
        self.preferences = preferences
        self.secretEnvelope = secretEnvelope
        self.exportedAt = exportedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw TransferSchemaError.unsupportedVersion(schemaVersion) }
        credentials = try container.decode([TransferCredential].self, forKey: .credentials)
        preferences = try container.decode(TransferPreferences.self, forKey: .preferences)
        secretEnvelope = try container.decodeIfPresent(EncryptedSecretEnvelope.self, forKey: .secretEnvelope)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, credentials, preferences, secretEnvelope, exportedAt
    }
}

struct TransferCredential: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let credentialId: String
    let providerId: String
    let credentialKind: String
    let name: String
    let isEnabled: Bool
    let sortOrder: Int
    let metadata: [String: String]
    /// Secrets are intentionally absent. They can only be carried by `secretEnvelope`.
    let secret: String?

    init(
        schemaVersion: Int = 1,
        credentialId: UUID,
        providerId: String,
        credentialKind: String,
        name: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.credentialId = credentialId.uuidString
        self.providerId = providerId
        self.credentialKind = credentialKind
        self.name = name
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.metadata = metadata
        self.secret = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw TransferSchemaError.unsupportedVersion(schemaVersion) }
        credentialId = try container.decode(String.self, forKey: .credentialId)
        guard UUID(uuidString: credentialId) != nil else { throw TransferSchemaError.invalidCredentialID(credentialId) }
        providerId = try container.decode(String.self, forKey: .providerId)
        guard !providerId.isEmpty else { throw TransferSchemaError.missingRequiredField("providerId") }
        credentialKind = try container.decode(String.self, forKey: .credentialKind)
        guard !credentialKind.isEmpty else { throw TransferSchemaError.missingRequiredField("credentialKind") }
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        let unknownMetadataKeys = Set(metadata.keys).subtracting(Self.metadataAllowlist)
        guard unknownMetadataKeys.isEmpty else {
            throw TransferSchemaError.invalidMetadataKey(unknownMetadataKeys.sorted().first!)
        }
        secret = try container.decodeIfPresent(String.self, forKey: .secret)
        guard secret == nil else { throw TransferSchemaError.secretOutsideEnvelope }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(credentialId, forKey: .credentialId)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(credentialKind, forKey: .credentialKind)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(metadata, forKey: .metadata)
    }

    private static let metadataAllowlist: Set<String> = [
        "baseURL", "userID", "region", "planType", "usageKind", "websiteURL"
    ]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, credentialId, providerId, credentialKind, name, isEnabled, sortOrder, metadata, secret
    }
}

struct TransferPreferences: Codable, Equatable, Sendable {
    let refreshIntervalMinutes: Int
    let wifiOnly: Bool
    let openAppRefresh: Bool
    let notificationsEnabled: Bool
    let alertThresholds: [Int]
    let pinnedCredentialIds: [String]

    init(
        refreshIntervalMinutes: Int = 15,
        wifiOnly: Bool = false,
        openAppRefresh: Bool = true,
        notificationsEnabled: Bool = true,
        alertThresholds: [Int] = [50, 80],
        pinnedCredentialIds: [String] = []
    ) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.wifiOnly = wifiOnly
        self.openAppRefresh = openAppRefresh
        self.notificationsEnabled = notificationsEnabled
        self.alertThresholds = alertThresholds
        self.pinnedCredentialIds = pinnedCredentialIds
    }
}

struct EncryptedSecretEnvelope: Codable, Equatable, Sendable {
    let algorithm: String
    let keyAgreement: String
    let nonce: String
    let ciphertext: String
    let tag: String
    let ephemeralPublicKey: String
    let associatedData: String?

    init(
        algorithm: String,
        keyAgreement: String,
        nonce: String,
        ciphertext: String,
        tag: String,
        ephemeralPublicKey: String,
        associatedData: String? = nil
    ) {
        self.algorithm = algorithm
        self.keyAgreement = keyAgreement
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.ephemeralPublicKey = ephemeralPublicKey
        self.associatedData = associatedData
    }
}

enum TransferSchemaError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidCredentialID(String)
    case missingRequiredField(String)
    case invalidMetadataKey(String)
    case secretOutsideEnvelope
}
