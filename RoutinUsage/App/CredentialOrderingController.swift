import Foundation
import Observation

struct CredentialAddOutcome: Sendable, Equatable {
    let saveResult: KeyEditorSaveResult
    let addedCredentialID: UUID?
}

@MainActor
final class CredentialOrderingController {
    private let settings: AppSettings
    private let addCredential: @MainActor (ValidatedCredentialInput) async throws -> CredentialAddOutcome
    private let setKeyEnabled: @MainActor (UUID, Bool) throws -> Void
    private let deleteCredential: @MainActor (UUID) throws -> Void

    init(
        settings: AppSettings,
        addCredential: @escaping @MainActor (ValidatedCredentialInput) async throws -> CredentialAddOutcome,
        setKeyEnabled: @escaping @MainActor (UUID, Bool) throws -> Void,
        delete: @escaping @MainActor (UUID) throws -> Void
    ) {
        self.settings = settings
        self.addCredential = addCredential
        self.setKeyEnabled = setKeyEnabled
        self.deleteCredential = delete
    }

    func addValidatedCredential(
        _ input: ValidatedCredentialInput
    ) async throws -> KeyEditorSaveResult {
        let previousIDs = Set(settings.displayOrder.popoverCredentialIDs)
        let outcome = try await addCredential(input)
        if let addedID = outcome.addedCredentialID,
           !previousIDs.contains(addedID) {
            settings.appendCredential(addedID)
        }
        return outcome.saveResult
    }

    func setEnabled(_ id: UUID, enabled: Bool) throws {
        try setKeyEnabled(id, enabled)
    }

    func delete(_ id: UUID) throws {
        try deleteCredential(id)
        settings.removeCredential(id)
    }

    func move(
        _ sequence: CredentialDisplaySequence,
        id: UUID,
        toIndex: Int
    ) {
        settings.displayOrder = settings.displayOrder.moving(
            sequence,
            id: id,
            toIndex: toIndex
        )
    }

    func addToMenuBar(_ id: UUID, toIndex: Int) {
        settings.displayOrder = settings.displayOrder.addingToMenuBar(
            id,
            toIndex: toIndex
        )
    }

    func removeFromMenuBar(_ id: UUID) {
        settings.displayOrder = settings.displayOrder.removingFromMenuBar(id)
    }
}
