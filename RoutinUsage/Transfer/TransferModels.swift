import Foundation

struct TransferPackageV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let credentials: [TransferCredential]
    let preferences: TransferPreferences
    let secretEnvelope: EncryptedSecretEnvelope
    let exportedAt: Date

    init(
        schemaVersion: Int = 1,
        credentials: [TransferCredential],
        preferences: TransferPreferences,
        secretEnvelope: EncryptedSecretEnvelope = .empty,
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
        secretEnvelope = try container.decode(EncryptedSecretEnvelope.self, forKey: .secretEnvelope)
        let credentialIDs = Set(credentials.map(\.credentialId))
        guard secretEnvelope.entries.allSatisfy({ credentialIDs.contains($0.credentialId) }) else {
            throw TransferSchemaError.invalidEnvelope("credentialAssociation")
        }
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw TransferSchemaError.unsupportedVersion(schemaVersion) }
        credentialId = try container.decode(String.self, forKey: .credentialId)
        guard UUID(uuidString: credentialId) != nil else { throw TransferSchemaError.invalidCredentialID(credentialId) }
        providerId = try container.decode(String.self, forKey: .providerId)
        guard ProviderID(rawValue: providerId) != nil else { throw TransferSchemaError.invalidProvider(providerId) }
        credentialKind = try container.decode(String.self, forKey: .credentialKind)
        guard CredentialKind(rawValue: credentialKind) != nil else { throw TransferSchemaError.invalidCredentialKind(credentialKind) }
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        let unknownMetadataKeys = Set(metadata.keys).subtracting(Self.metadataAllowlist)
        guard unknownMetadataKeys.isEmpty else {
            throw TransferSchemaError.invalidMetadataKey(unknownMetadataKeys.sorted().first!)
        }
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw TransferSchemaError.unsupportedVersion(schemaVersion) }
        guard UUID(uuidString: credentialId) != nil else { throw TransferSchemaError.invalidCredentialID(credentialId) }
        guard ProviderID(rawValue: providerId) != nil else { throw TransferSchemaError.invalidProvider(providerId) }
        guard CredentialKind(rawValue: credentialKind) != nil else { throw TransferSchemaError.invalidCredentialKind(credentialKind) }
        let unknownMetadataKeys = Set(metadata.keys).subtracting(Self.metadataAllowlist)
        guard unknownMetadataKeys.isEmpty else {
            throw TransferSchemaError.invalidMetadataKey(unknownMetadataKeys.sorted().first!)
        }
    }

    private static let metadataAllowlist: Set<String> = [
        "baseURL", "userID", "region", "planType", "usageKind", "websiteURL"
    ]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, credentialId, providerId, credentialKind, name, isEnabled, sortOrder, metadata
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshIntervalMinutes = try container.decode(Int.self, forKey: .refreshIntervalMinutes)
        guard [1, 5, 15, 30].contains(refreshIntervalMinutes) else {
            throw TransferSchemaError.invalidPreference("refreshIntervalMinutes")
        }
        wifiOnly = try container.decode(Bool.self, forKey: .wifiOnly)
        openAppRefresh = try container.decode(Bool.self, forKey: .openAppRefresh)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        alertThresholds = try container.decode([Int].self, forKey: .alertThresholds)
        guard alertThresholds.allSatisfy({ (0...100).contains($0) }) else {
            throw TransferSchemaError.invalidPreference("alertThresholds")
        }
        pinnedCredentialIds = try container.decode([String].self, forKey: .pinnedCredentialIds)
        guard pinnedCredentialIds.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw TransferSchemaError.invalidPreference("pinnedCredentialIds")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case refreshIntervalMinutes, wifiOnly, openAppRefresh, notificationsEnabled, alertThresholds, pinnedCredentialIds
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
    let entries: [EncryptedSecretEntry]

    static let empty: EncryptedSecretEnvelope = try! EncryptedSecretEnvelope(
        algorithm: "AES-256-GCM", keyAgreement: "X25519-HKDF-SHA256", nonce: "AA", ciphertext: "AA",
        tag: "AA", ephemeralPublicKey: "AA", associatedData: nil, entries: []
    )

    init(
        algorithm: String,
        keyAgreement: String,
        nonce: String,
        ciphertext: String,
        tag: String,
        ephemeralPublicKey: String,
        associatedData: String? = nil,
        entries: [EncryptedSecretEntry] = []
    ) throws {
        guard ["AES-256-GCM", "ChaCha20-Poly1305"].contains(algorithm) else {
            throw TransferSchemaError.invalidEnvelope("algorithm")
        }
        guard keyAgreement == "X25519-HKDF-SHA256" else { throw TransferSchemaError.invalidEnvelope("keyAgreement") }
        for (name, value) in [("nonce", nonce), ("ciphertext", ciphertext), ("tag", tag), ("ephemeralPublicKey", ephemeralPublicKey)] {
            guard Self.isBase64URL(value) else { throw TransferSchemaError.invalidEnvelope(name) }
        }
        let ids = entries.map(\.credentialId)
        guard Set(ids).count == ids.count else { throw TransferSchemaError.invalidEnvelope("entries") }
        self.algorithm = algorithm
        self.keyAgreement = keyAgreement
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.ephemeralPublicKey = ephemeralPublicKey
        self.associatedData = associatedData
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try EncryptedSecretEnvelope(
            algorithm: try container.decode(String.self, forKey: .algorithm),
            keyAgreement: try container.decode(String.self, forKey: .keyAgreement),
            nonce: try container.decode(String.self, forKey: .nonce),
            ciphertext: try container.decode(String.self, forKey: .ciphertext),
            tag: try container.decode(String.self, forKey: .tag),
            ephemeralPublicKey: try container.decode(String.self, forKey: .ephemeralPublicKey),
            associatedData: try container.decodeIfPresent(String.self, forKey: .associatedData),
            entries: try container.decode([EncryptedSecretEntry].self, forKey: .entries)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm, keyAgreement, nonce, ciphertext, tag, ephemeralPublicKey, associatedData, entries
    }

    private static func isBase64URL(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isNumber || $0.isLetter || $0 == "-" || $0 == "_" }
    }
}

struct EncryptedSecretEntry: Codable, Equatable, Sendable {
    let credentialId: String
    let bearerToken: String?
    let apiKey: String?
    let accessKeyID: String?
    let secretAccessKey: String?

    init(credentialId: UUID, bearerToken: String? = nil, apiKey: String? = nil, accessKeyID: String? = nil, secretAccessKey: String? = nil) throws {
        self.credentialId = credentialId.uuidString
        self.bearerToken = bearerToken
        self.apiKey = apiKey
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credentialId = try container.decode(String.self, forKey: .credentialId)
        guard UUID(uuidString: credentialId) != nil else { throw TransferSchemaError.invalidCredentialID(credentialId) }
        bearerToken = try container.decodeIfPresent(String.self, forKey: .bearerToken)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        accessKeyID = try container.decodeIfPresent(String.self, forKey: .accessKeyID)
        secretAccessKey = try container.decodeIfPresent(String.self, forKey: .secretAccessKey)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialId, forKey: .credentialId)
        try container.encodeIfPresent(bearerToken, forKey: .bearerToken)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
        try container.encodeIfPresent(accessKeyID, forKey: .accessKeyID)
        try container.encodeIfPresent(secretAccessKey, forKey: .secretAccessKey)
    }

    private func validate() throws {
        guard bearerToken != nil || apiKey != nil || accessKeyID != nil || secretAccessKey != nil else {
            throw TransferSchemaError.invalidEnvelope("secretFields")
        }
        for (name, value) in [("bearerToken", bearerToken), ("apiKey", apiKey), ("accessKeyID", accessKeyID), ("secretAccessKey", secretAccessKey)] {
            if let value, !Self.isBase64URL(value) { throw TransferSchemaError.invalidEnvelope(name) }
        }
        guard (accessKeyID == nil) == (secretAccessKey == nil) else {
            throw TransferSchemaError.invalidEnvelope("accessKeyPair")
        }
    }

    private static func isBase64URL(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count % 4 != 1,
              value.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95 })
        else { return false }
        let padded = value + String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: padded, options: [.ignoreUnknownCharacters]) else { return false }
        let canonical = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return canonical == value
    }

    private enum CodingKeys: String, CodingKey {
        case credentialId, bearerToken, apiKey, accessKeyID, secretAccessKey
    }
}

enum TransferSchemaError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidCredentialID(String)
    case invalidProvider(String)
    case invalidCredentialKind(String)
    case missingRequiredField(String)
    case invalidMetadataKey(String)
    case invalidPreference(String)
    case invalidEnvelope(String)
}
