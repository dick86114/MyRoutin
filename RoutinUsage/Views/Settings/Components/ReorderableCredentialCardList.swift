import SwiftUI

private let reorderableCardCoordinateSpace = "ReorderableCredentialCardList"

private struct CardFramePreferenceKey<ID: Hashable>: PreferenceKey {
    typealias Value = [ID: CGRect]

    static var defaultValue: [ID: CGRect] { [:] }

    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

struct ReorderableCredentialCardList<ID: Hashable, Card: View>: View {
    let ids: [ID]
    let draggedID: ID?
    let itemHeight: CGFloat
    let itemSpacing: CGFloat
    let move: (ID, ID) -> Bool
    @ViewBuilder let card: (ID) -> Card

    @Binding var externalDraggedID: ID?
    @State private var activeID: ID?
    @State private var startFrame: CGRect?
    @State private var startIndex: Int?
    @State private var currentIndex: Int?
    @State private var dragTranslation: CGFloat = .zero
    @State private var frames: [ID: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: CGFloat { itemHeight + itemSpacing }

    var body: some View {
        VStack(alignment: .leading, spacing: itemSpacing) {
            ForEach(ids, id: \.self) { id in
                card(id)
                    .frame(height: itemHeight)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: CardFramePreferenceKey<ID>.self,
                                value: [
                                    id: geometry.frame(in: .named(reorderableCardCoordinateSpace)),
                                ]
                            )
                        }
                    )
                    .offset(y: dragOffset(for: id))
                    .scaleEffect(activeID == id ? 1.02 : 1)
                    .shadow(
                        color: .black.opacity(activeID == id ? 0.18 : 0),
                        radius: activeID == id ? 14 : 0,
                        y: activeID == id ? 6 : 0
                    )
                    .zIndex(activeID == id ? 10 : 0)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(for: id))
            }
        }
        .coordinateSpace(name: reorderableCardCoordinateSpace)
        .onPreferenceChange(CardFramePreferenceKey<ID>.self) { value in
            frames = value
        }
    }

    private func dragGesture(for id: ID) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(reorderableCardCoordinateSpace))
            .onChanged { value in
                if activeID != id {
                    guard activeID == nil else { return }
                    activeID = id
                    externalDraggedID = id
                    startFrame = frames[id]
                    startIndex = ids.firstIndex(of: id)
                    currentIndex = startIndex
                }

                guard activeID == id else { return }
                dragTranslation = value.translation.height
                updateTarget(for: id)
            }
            .onEnded { _ in
                withAnimation(
                    reduceMotion
                        ? nil
                        : .interactiveSpring(response: 0.28, dampingFraction: 0.84)
                ) {
                    activeID = nil
                    externalDraggedID = nil
                    startFrame = nil
                    startIndex = nil
                    currentIndex = nil
                    dragTranslation = .zero
                }
            }
    }

    private func updateTarget(for id: ID) {
        guard let startFrame,
              let startIndex,
              let currentIndex,
              let firstFrame = ids.first.flatMap({ frames[$0] })
        else { return }

        let draggedCenter = startFrame.midY + dragTranslation
        let relativePosition = draggedCenter - firstFrame.minY - itemHeight / 2
        let targetIndex = max(0, min(ids.count - 1, Int(round(relativePosition / step))))
        guard targetIndex != currentIndex, ids.indices.contains(targetIndex) else { return }

        let targetID = ids[targetIndex]
        if move(id, targetID) {
            self.currentIndex = targetIndex
        }
    }

    private func dragOffset(for id: ID) -> CGFloat {
        guard activeID == id,
              let startIndex,
              let currentIndex
        else { return 0 }

        return dragTranslation - CGFloat((currentIndex - startIndex) * Int(step))
    }
}
