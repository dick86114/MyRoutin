import SwiftUI

struct ProviderFilterChips: View {
    let providers: [ProviderDescriptor]
    let selectedProviderID: ProviderID?
    let select: (ProviderID?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    title: "全部",
                    isSelected: selectedProviderID == nil
                ) {
                    select(nil)
                }

                ForEach(providers) { provider in
                    chip(
                        title: provider.displayName,
                        isSelected: selectedProviderID == provider.id
                    ) {
                        select(provider.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.14)
                                : Color.primary.opacity(0.04)
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected
                                ? Color.accentColor.opacity(0.28)
                                : Color.secondary.opacity(0.14),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
