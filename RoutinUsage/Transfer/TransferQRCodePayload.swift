import Foundation

struct TransferQRCodePayload: Codable, Equatable, Sendable {
    static let supportedProtocolVersion = 1
    static let scheme = "mytoken-transfer"

    let protocolVersion: Int
    let sessionID: UUID
    let host: String
    let port: Int
    let macEphemeralPublicKey: Data
    let expiresAt: Date
    let connectionCode: String

    init(
        protocolVersion: Int = Self.supportedProtocolVersion,
        sessionID: UUID,
        host: String,
        port: Int,
        macEphemeralPublicKey: Data,
        expiresAt: Date,
        connectionCode: String
    ) throws {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.host = host
        self.port = port
        self.macEphemeralPublicKey = macEphemeralPublicKey
        self.expiresAt = expiresAt
        self.connectionCode = connectionCode
        try validateStructure()
    }

    private func validateStructure() throws {
        guard protocolVersion == Self.supportedProtocolVersion else {
            throw TransferQRCodePayloadError.unsupportedVersion(protocolVersion)
        }
        guard !host.isEmpty, !host.contains(" ") else {
            throw TransferQRCodePayloadError.invalidHost
        }
        guard (1...65_535).contains(port) else {
            throw TransferQRCodePayloadError.invalidPort(port)
        }
        guard macEphemeralPublicKey.count == 32 else {
            throw TransferQRCodePayloadError.invalidPublicKey
        }
        guard connectionCode.count == 6, connectionCode.allSatisfy(\.isNumber) else {
            throw TransferQRCodePayloadError.invalidConnectionCode
        }
    }

    func validate(now: Date = Date()) throws {
        try validateStructure()
        guard expiresAt > now else {
            throw TransferQRCodePayloadError.expired
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
        self.macEphemeralPublicKey = try container.decode(Data.self, forKey: .macEphemeralPublicKey)
        self.expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        self.connectionCode = try container.decode(String.self, forKey: .connectionCode)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, sessionID, host, port, macEphemeralPublicKey, expiresAt, connectionCode
    }

    /// A compact URI intended for QR encoding. It contains only the seven
    /// fields in this payload; transfer packages and secrets are never added.
    func encodedString() throws -> String {
        try validate()
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "v\(protocolVersion)"
        components.queryItems = [
            URLQueryItem(name: "session", value: sessionID.uuidString),
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "publicKey", value: Self.base64URL(macEphemeralPublicKey)),
            URLQueryItem(name: "expiry", value: ISO8601DateFormatter.transfer.string(from: expiresAt)),
            URLQueryItem(name: "code", value: connectionCode)
        ]
        guard let string = components.string else { throw TransferQRCodePayloadError.invalidEncoding }
        return string
    }

    static func decode(_ string: String) throws -> TransferQRCodePayload {
        guard let components = URLComponents(string: string),
              components.scheme == Self.scheme,
              let host = components.host,
              host.hasPrefix("v"),
              let version = Int(host.dropFirst()),
              version == Self.supportedProtocolVersion,
              let queryItems = components.queryItems else {
            throw TransferQRCodePayloadError.invalidEncoding
        }
        let values = Dictionary(queryItems.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard values.count == 6,
              let session = values["session"], let sessionID = UUID(uuidString: session),
              let address = values["host"], let portString = values["port"], let port = Int(portString),
              let publicKeyString = values["publicKey"], let publicKey = Data(base64URL: publicKeyString),
              let expiryString = values["expiry"], let expiresAt = ISO8601DateFormatter.transfer.date(from: expiryString),
              let code = values["code"] else {
            throw TransferQRCodePayloadError.invalidEncoding
        }
        return try TransferQRCodePayload(
            protocolVersion: version, sessionID: sessionID, host: address, port: port,
            macEphemeralPublicKey: publicKey, expiresAt: expiresAt, connectionCode: code
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum TransferQRCodePayloadError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidHost
    case invalidPort(Int)
    case invalidPublicKey
    case expired
    case invalidConnectionCode
    case invalidEncoding
}

private extension Data {
    init?(base64URL value: String) {
        guard !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let standard = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)
        self.init(base64Encoded: padded)
    }
}

private extension ISO8601DateFormatter {
    static let transfer: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
