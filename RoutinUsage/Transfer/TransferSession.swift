import CryptoKit
import Foundation

/// The lifecycle of a single macOS → Android transfer invitation.
enum TransferSessionState: String, Equatable, Sendable {
    case created
    case waitingForAndroid
    case connected
    case sent
    case completed
    case cancelled
    case expired

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .expired: return true
        default: return false
        }
    }
}

enum TransferSessionError: Error, Equatable {
    case invalidState(TransferSessionState)
    case sessionMismatch
    case connectionCodeMismatch
    case publicKeyMismatch
    case invalidAndroidPublicKey
    case sessionKeyUnavailable
    case expired
    case alreadyConnected
}

/// The metadata-only handshake Android sends over the accepted connection
/// before any encrypted payload. It carries no credential material.
struct TransferHandshake: Codable, Sendable, Equatable {
    let sessionID: UUID
    let androidEphemeralPublicKey: Data
}

/// Wire envelope for the encrypted transfer package. `nonce`, `ciphertext`
/// and `authenticationTag` are the AES-GCM parts; the AAD binds the protocol
/// version and session ID so envelopes cannot be replayed across sessions.
struct TransferEncryptedMessage: Codable, Sendable, Equatable {
    static let currentProtocolVersion = 1

    let protocolVersion: Int
    let sessionID: UUID
    let nonce: Data
    let ciphertext: Data
    let authenticationTag: Data
}

enum TransferCryptoError: Error, Equatable {
    case unsupportedProtocolVersion
    case invalidNonce
}

/// X25519 + HKDF-SHA256 + AES-256-GCM primitives shared by both sides.
enum TransferCrypto {
    /// HKDF shared info; includes the protocol version so key material is
    /// version-bound.
    static func sessionKeyInfo(protocolVersion: Int) -> Data {
        Data("mytoken-transfer/v\(protocolVersion)/hkdf-sha256".utf8)
    }

    /// AEAD associated data; binds every ciphertext to the protocol version
    /// and session ID.
    static func associatedData(sessionID: UUID, protocolVersion: Int) -> Data {
        Data("mytoken-transfer/v\(protocolVersion)|\(sessionID.uuidString)".utf8)
    }

    static func deriveSessionKey(
        sharedSecret: SharedSecret,
        sessionID: UUID,
        protocolVersion: Int = TransferEncryptedMessage.currentProtocolVersion
    ) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(sessionID.uuidString.utf8),
            sharedInfo: sessionKeyInfo(protocolVersion: protocolVersion),
            outputByteCount: 32
        )
    }

    /// Seals plaintext with a fresh random 12-byte nonce. Each call produces
    /// a unique nonce; sessions are single-use so at most one seal is sent.
    static func seal(
        _ plaintext: Data,
        key: SymmetricKey,
        sessionID: UUID,
        protocolVersion: Int = TransferEncryptedMessage.currentProtocolVersion
    ) throws -> TransferEncryptedMessage {
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: nonce,
            authenticating: associatedData(sessionID: sessionID, protocolVersion: protocolVersion)
        )
        return TransferEncryptedMessage(
            protocolVersion: protocolVersion,
            sessionID: sessionID,
            nonce: Data(nonce),
            ciphertext: Data(sealed.ciphertext),
            authenticationTag: Data(sealed.tag)
        )
    }

    static func open(_ message: TransferEncryptedMessage, key: SymmetricKey) throws -> Data {
        guard message.protocolVersion == TransferEncryptedMessage.currentProtocolVersion else {
            throw TransferCryptoError.unsupportedProtocolVersion
        }
        guard message.nonce.count == 12 else { throw TransferCryptoError.invalidNonce }
        let nonce = try AES.GCM.Nonce(data: message.nonce)
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: message.ciphertext,
            tag: message.authenticationTag
        )
        return try AES.GCM.open(
            sealed,
            using: key,
            authenticating: associatedData(sessionID: message.sessionID, protocolVersion: message.protocolVersion)
        )
    }
}

actor TransferSession {
    static let defaultTimeout: TimeInterval = 5 * 60

    let sessionID: UUID
    let connectionCode: String
    let expiresAt: Date
    let macEphemeralPublicKey: Data

    private(set) var state: TransferSessionState = .created
    private var ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var sessionKey: SymmetricKey?
    private var androidEphemeralPublicKey: Data?

    var hasEphemeralPrivateKey: Bool { ephemeralPrivateKey != nil }
    var hasSessionKey: Bool { sessionKey != nil }

    init(now: Date = Date(), timeout: TimeInterval = 5 * 60) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        sessionID = UUID()
        connectionCode = Self.makeConnectionCode()
        expiresAt = now.addingTimeInterval(max(0.001, timeout))
        macEphemeralPublicKey = privateKey.publicKey.rawRepresentation
        ephemeralPrivateKey = privateKey
    }

    func beginWaitingForAndroid() throws {
        guard state == .created else { throw TransferSessionError.invalidState(state) }
        guard !isExpired(at: Date()) else {
            transitionToExpired()
            throw TransferSessionError.expired
        }
        state = .waitingForAndroid
    }

    func makeQRCodePayload(host: String, port: Int) throws -> TransferQRCodePayload {
        guard state == .waitingForAndroid else { throw TransferSessionError.invalidState(state) }
        guard !isExpired(at: Date()) else {
            transitionToExpired()
            throw TransferSessionError.expired
        }
        return try TransferQRCodePayload(
            sessionID: sessionID, host: host, port: port,
            macEphemeralPublicKey: macEphemeralPublicKey,
            expiresAt: expiresAt, connectionCode: connectionCode
        )
    }

    func acceptConnection(
        sessionID: UUID,
        connectionCode: String,
        macEphemeralPublicKey: Data,
        now: Date = Date()
    ) throws {
        guard !isExpired(at: now) else {
            transitionToExpired()
            throw TransferSessionError.expired
        }
        guard state == .waitingForAndroid else {
            if state == .connected { throw TransferSessionError.alreadyConnected }
            throw TransferSessionError.invalidState(state)
        }
        guard self.sessionID == sessionID else { throw TransferSessionError.sessionMismatch }
        guard self.connectionCode == connectionCode else { throw TransferSessionError.connectionCodeMismatch }
        guard self.macEphemeralPublicKey == macEphemeralPublicKey else { throw TransferSessionError.publicKeyMismatch }
        state = .connected
    }

    /// Validates Android's handshake metadata and derives the one-time session
    /// key from the X25519 shared secret. Only valid on a connected session;
    /// key material is bound to the session ID and protocol version.
    func acceptHandshake(_ handshake: TransferHandshake, now: Date = Date()) throws {
        guard !isExpired(at: now) else {
            transitionToExpired()
            throw TransferSessionError.expired
        }
        guard state == .connected else { throw TransferSessionError.invalidState(state) }
        guard handshake.sessionID == sessionID else { throw TransferSessionError.sessionMismatch }
        guard sessionKey == nil else { throw TransferSessionError.invalidState(state) }
        guard let privateKey = ephemeralPrivateKey else {
            throw TransferSessionError.invalidState(state)
        }
        let androidKey: Curve25519.KeyAgreement.PublicKey
        do {
            androidKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: handshake.androidEphemeralPublicKey)
        } catch {
            throw TransferSessionError.invalidAndroidPublicKey
        }
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: androidKey)
        sessionKey = TransferCrypto.deriveSessionKey(
            sharedSecret: sharedSecret,
            sessionID: sessionID,
            protocolVersion: TransferEncryptedMessage.currentProtocolVersion
        )
        androidEphemeralPublicKey = handshake.androidEphemeralPublicKey
    }

    /// Encrypts one payload with the derived session key. Only valid before
    /// the single send; after `markSent()` the session refuses further seals.
    func sealMessage(_ plaintext: Data) throws -> TransferEncryptedMessage {
        guard state == .connected else { throw TransferSessionError.invalidState(state) }
        guard let key = sessionKey else { throw TransferSessionError.sessionKeyUnavailable }
        return try TransferCrypto.seal(
            plaintext,
            key: key,
            sessionID: sessionID,
            protocolVersion: TransferEncryptedMessage.currentProtocolVersion
        )
    }

    func markSent() throws {
        guard state == .connected else { throw TransferSessionError.invalidState(state) }
        state = .sent
    }

    func complete() throws {
        guard state == .sent else { throw TransferSessionError.invalidState(state) }
        state = .completed
        destroyEphemeralKey()
    }

    func cancel() {
        guard !state.isTerminal else { return }
        state = .cancelled
        destroyEphemeralKey()
    }

    @discardableResult
    func expireIfNeeded(now: Date = Date()) -> Bool {
        guard !state.isTerminal, isExpired(at: now) else { return false }
        transitionToExpired()
        return true
    }

    private func isExpired(at date: Date) -> Bool { date >= expiresAt }

    private func transitionToExpired() {
        state = .expired
        destroyEphemeralKey()
    }

    private func destroyEphemeralKey() {
        ephemeralPrivateKey = nil
        sessionKey = nil
        androidEphemeralPublicKey = nil
    }

    private static func makeConnectionCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 100_000...999_999, using: &generator))
    }
}
