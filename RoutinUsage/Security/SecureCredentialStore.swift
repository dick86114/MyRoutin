import Foundation

protocol CredentialStoring: Sendable {
    func save(_ secret: String, for id: UUID) throws
    func read(for id: UUID) throws -> String?
    func delete(for id: UUID) throws
}

protocol SecureCredentialStoring: CredentialStoring {}

// Keep the old spelling source-compatible for existing migration adapters and clients.
typealias LocalKeyStoring = CredentialStoring
