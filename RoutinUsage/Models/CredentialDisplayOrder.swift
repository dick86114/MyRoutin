import Foundation

enum CredentialDisplaySequence: Equatable, Sendable {
    case menuBar
    case popover
}

struct CredentialDisplayVisibility: Equatable, Sendable {
    let menuBarIDs: [UUID]
    let popoverIDs: [UUID]
    let menuBarCandidateIDs: [UUID]
}

struct CredentialDisplayOrder: Codable, Equatable, Sendable {
    static let maximumMenuBarCount = 5

    var menuBarCredentialIDs: [UUID] {
        didSet {
            menuBarCredentialIDs = Self.normalizedMenuBar(menuBarCredentialIDs)
        }
    }

    var popoverCredentialIDs: [UUID] {
        didSet {
            popoverCredentialIDs = Self.uniqued(popoverCredentialIDs)
        }
    }

    init(
        menuBarCredentialIDs: [UUID] = [],
        popoverCredentialIDs: [UUID] = []
    ) {
        self.menuBarCredentialIDs = Self.normalizedMenuBar(menuBarCredentialIDs)
        self.popoverCredentialIDs = Self.uniqued(popoverCredentialIDs)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            menuBarCredentialIDs: try container.decode(
                [UUID].self,
                forKey: .menuBarCredentialIDs
            ),
            popoverCredentialIDs: try container.decode(
                [UUID].self,
                forKey: .popoverCredentialIDs
            )
        )
    }

    static func migrated(
        selected: [UUID],
        available: [UUID],
        allIDs: [UUID]
    ) -> Self {
        let menuBar = selected.filter { allIDs.contains($0) }
        let popover = selected + available + allIDs
        return Self(
            menuBarCredentialIDs: menuBar,
            popoverCredentialIDs: popover
        )
    }

    func visible(enabledIDs: Set<UUID>) -> CredentialDisplayVisibility {
        let menuBar = menuBarCredentialIDs.filter { enabledIDs.contains($0) }
        let popover = popoverCredentialIDs.filter { enabledIDs.contains($0) }
        let candidates = popover.filter { !menuBar.contains($0) }
        return CredentialDisplayVisibility(
            menuBarIDs: menuBar,
            popoverIDs: popover,
            menuBarCandidateIDs: candidates
        )
    }

    func moving(
        _ sequence: CredentialDisplaySequence,
        id: UUID,
        toIndex target: Int
    ) -> Self {
        var result = self
        let keyPath: WritableKeyPath<CredentialDisplayOrder, [UUID]> = switch sequence {
        case .menuBar: \.menuBarCredentialIDs
        case .popover: \.popoverCredentialIDs
        }
        result[keyPath: keyPath] = Self.moved(
            result[keyPath: keyPath],
            id: id,
            toIndex: target
        )
        return result
    }

    func movingDisplay(
        id: UUID,
        before targetID: UUID
    ) -> Self {
        let popoverIDs = popoverCredentialIDs
        guard id != targetID,
              popoverIDs.contains(id),
              let targetBeforeIndex = popoverIDs.firstIndex(of: targetID),
              let sourceIndex = popoverIDs.firstIndex(of: id)
        else {
            return self
        }

        let targetIndex = targetBeforeIndex > sourceIndex ? targetBeforeIndex - 1 : targetBeforeIndex
        let moved = moving(.popover, id: id, toIndex: targetIndex)
        let idIsInMenuBar = menuBarCredentialIDs.contains(id)
        let targetIsInMenuBar = menuBarCredentialIDs.contains(targetID)
        if targetIsInMenuBar {
            guard idIsInMenuBar || menuBarCredentialIDs.count < Self.maximumMenuBarCount else {
                return self
            }
        }

        var result = moved
        if targetIsInMenuBar {
            if !idIsInMenuBar {
                result.menuBarCredentialIDs.append(id)
            }
        } else if idIsInMenuBar {
            result.menuBarCredentialIDs.removeAll { $0 == id }
        }

        result.menuBarCredentialIDs = result.popoverCredentialIDs.filter {
            result.menuBarCredentialIDs.contains($0)
        }
        return result
    }

    func addingToMenuBar(_ id: UUID, toIndex target: Int) -> Self {
        guard menuBarCredentialIDs.contains(id) else {
            guard menuBarCredentialIDs.count < Self.maximumMenuBarCount else {
                return self
            }
            var result = self
            let index = max(0, min(target, result.menuBarCredentialIDs.count))
            result.menuBarCredentialIDs.insert(id, at: index)
            return result
        }
        return moving(.menuBar, id: id, toIndex: target)
    }

    func removingFromMenuBar(_ id: UUID) -> Self {
        var result = self
        result.menuBarCredentialIDs.removeAll { $0 == id }
        return result
    }

    func removingCredential(_ id: UUID) -> Self {
        var result = removingFromMenuBar(id)
        result.popoverCredentialIDs.removeAll { $0 == id }
        return result
    }

    private static func moved(
        _ ids: [UUID],
        id: UUID,
        toIndex target: Int
    ) -> [UUID] {
        guard let source = ids.firstIndex(of: id) else {
            return ids
        }

        var result = ids
        result.remove(at: source)
        let destination = target > source ? target - 1 : target
        let boundedIndex = max(0, min(destination, result.count))
        result.insert(id, at: boundedIndex)
        return result
    }

    private static func uniqued(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func normalizedMenuBar(_ ids: [UUID]) -> [UUID] {
        Array(uniqued(ids).prefix(maximumMenuBarCount))
    }
}
