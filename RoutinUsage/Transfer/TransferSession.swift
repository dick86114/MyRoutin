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
    case expired
    case alreadyConnected
}

actor TransferSession {
    static let defaultTimeout: TimeInterval = 5 * 60

    let sessionID: UUID
    let connectionCode: String
    let expiresAt: Date
    let macEphemeralPublicKey: Data

    private(set) var state: TransferSessionState = .created
    private var ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey?

    var hasEphemeralPrivateKey: Bool { ephemeralPrivateKey != nil }

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
    }

    private static func makeConnectionCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 100_000...999_999, using: &generator))
    }
}
