import AppKit
import SwiftUI

struct ModelIDChipFlow: View {
    let models: [String]
    let copiedModelID: String?
    let onCopied: (String) -> Void

    var body: some View {
        WrappingModelChips(spacing: 7) {
            ForEach(models, id: \.self) { modelID in
                ModelIDChip(
                    modelID: modelID,
                    isCopied: copiedModelID == modelID,
                    onCopied: onCopied
                )
            }
        }
    }
}

enum ModelIDChipPalette {
    static let colorCount = 12

    static func colorIndex(for modelID: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for scalar in modelID.unicodeScalars {
            hash = (hash ^ UInt64(scalar.value)) &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(colorCount))
    }

    static func accentColor(for modelID: String) -> Color {
        switch colorIndex(for: modelID) {
        case 0: .blue
        case 1: .teal
        case 2: .indigo
        case 3: .green
        case 4: .orange
        case 5: .purple
        case 6: .pink
        case 7: .cyan
        case 8: .mint
        case 9: .red
        case 10: .brown
        default: .yellow
        }
    }
}

private struct ModelIDChip: View {
    let modelID: String
    let isCopied: Bool
    let onCopied: (String) -> Void

    @State private var isHovered = false

    private var accent: Color {
        ModelIDChipPalette.accentColor(for: modelID)
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(modelID, forType: .string)
            onCopied(modelID)
        } label: {
            HStack(spacing: 4) {
                Text(modelID)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.semibold))
                    .opacity(isCopied ? 1 : 0.54)
            }
            .font(.caption.weight(.medium).monospaced())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(accent.opacity(isCopied ? 0.25 : (isHovered ? 0.18 : 0.11)))
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        accent.opacity(isCopied ? 0.68 : (isHovered ? 0.48 : 0.28)),
                        lineWidth: 1
                    )
            }
            .foregroundStyle(accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isCopied)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(isCopied ? "已复制模型 ID" : "复制模型 ID")
        .accessibilityLabel(isCopied ? "已复制模型 ID \(modelID)" : "复制模型 ID \(modelID)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct WrappingModelChips: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = max(proposal.width ?? 360, 1)
        let rows = calculateRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { partial, row in
            partial + (row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0) + spacing
        }

        return CGSize(width: maxWidth, height: max(height - spacing, 0))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = calculateRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX

            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width + spacing
            }

            y += rowHeight + spacing
        }
    }

    private func calculateRows(
        subviews: Subviews,
        maxWidth: CGFloat
    ) -> [[Subviews.Element]] {
        var rows: [[Subviews.Element]] = [[]]
        var x: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append([])
                x = 0
            }

            rows[rows.count - 1].append(view)
            x += size.width + spacing
        }

        return rows
    }
}
