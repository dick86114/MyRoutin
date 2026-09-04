import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let credentialID = UTType("ai.routin.mytoken.credential") ?? .plainText
}

struct CredentialDropDelegate: DropDelegate {
    let targetID: UUID
    let draggedID: UUID?
    let reduceMotion: Bool
    let canAccept: (UUID) -> Bool
    let move: (UUID) -> Void
    let finish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != targetID,
              canAccept(draggedID)
        else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
            move(draggedID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        finish()
        return draggedID != nil
    }
}
