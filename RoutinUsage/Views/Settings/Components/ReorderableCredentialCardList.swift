import SwiftUI

private let reorderableCardCoordinateSpace = "ReorderableCredentialCardList"

struct ReorderableCredentialCardList<ID: Hashable, Card: View>: View {
    let ids: [ID]
    let itemHeight: CGFloat
    let itemSpacing: CGFloat
    let move: (ID, Int) -> Bool
    @ViewBuilder let card: (ID) -> Card

    @State private var activeID: ID?
    @State private var startIndex: Int?
    @State private var currentIndex: Int?
    @State private var dragTranslation: CGFloat = .zero
    @State private var workingIDs: [ID] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: CGFloat { itemHeight + itemSpacing }

    private var displayedIDs: [ID] {
        workingIDs.isEmpty ? ids : workingIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: itemSpacing) {
            ForEach(displayedIDs, id: \.self) { id in
                card(id)
                    .frame(height: itemHeight)
                    .offset(y: dragOffset(for: id))
                    .transaction { transaction in
                        if activeID == id {
                            transaction.animation = nil
                        }
                    }
                    .scaleEffect(activeID == id ? 1.015 : 1)
                    .shadow(
                        color: .black.opacity(activeID == id ? 0.14 : 0),
                        radius: activeID == id ? 10 : 0,
                        y: activeID == id ? 4 : 0
                    )
                    .zIndex(activeID == id ? 10 : 0)
                    .contentShape(Rectangle())
                    .highPriorityGesture(dragGesture(for: id))
            }
        }
        .coordinateSpace(name: reorderableCardCoordinateSpace)
        .onAppear {
            workingIDs = ids
        }
        .onChange(of: ids) { _, updatedIDs in
            guard activeID == nil else { return }
            workingIDs = updatedIDs
        }
    }

    private func dragGesture(for id: ID) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(reorderableCardCoordinateSpace))
            .onChanged { value in
                if activeID != id {
                    guard activeID == nil,
                          let index = displayedIDs.firstIndex(of: id)
                    else { return }

                    workingIDs = ids
                    activeID = id
                    startIndex = index
                    currentIndex = index
                }

                guard activeID == id else { return }
                dragTranslation = value.translation.height
                updateTarget(for: id)
            }
            .onEnded { _ in
                commitMove(for: id)
            }
    }

    private func updateTarget(for id: ID) {
        guard activeID == id,
              let startIndex,
              let currentIndex,
              !workingIDs.isEmpty
        else { return }

        let targetIndex = max(
            0,
            min(workingIDs.count - 1, startIndex + Int(round(dragTranslation / step)))
        )
        guard targetIndex != currentIndex,
              let sourceIndex = workingIDs.firstIndex(of: id)
        else { return }

        var updatedIDs = workingIDs
        updatedIDs.remove(at: sourceIndex)
        updatedIDs.insert(id, at: targetIndex)

        withAnimation(
            reduceMotion
                ? nil
                : .interactiveSpring(response: 0.18, dampingFraction: 0.9)
        ) {
            workingIDs = updatedIDs
            self.currentIndex = targetIndex
        }
    }

    private func commitMove(for id: ID) {
        let destinationIndex = currentIndex
        let didMove = if let startIndex,
                         let destinationIndex,
                         destinationIndex != startIndex {
            move(id, destinationIndex)
        } else {
            true
        }

        withAnimation(
            reduceMotion
                ? nil
                : .interactiveSpring(response: 0.2, dampingFraction: 0.92)
        ) {
            if !didMove {
                workingIDs = ids
            }
            activeID = nil
            startIndex = nil
            currentIndex = nil
            dragTranslation = .zero
        }
    }

    private func dragOffset(for id: ID) -> CGFloat {
        guard activeID == id,
              let startIndex,
              let currentIndex
        else { return 0 }

        return dragTranslation - CGFloat(currentIndex - startIndex) * step
    }
}
