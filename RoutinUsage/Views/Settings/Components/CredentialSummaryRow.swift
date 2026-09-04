import SwiftUI

struct CredentialSummaryRow: View {
    let state: KeyUsageState
    let descriptor: ProviderDescriptor
    let planType: String
    var leading: AnyView? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(alias)
                    .font(.body.weight(.medium))
                Text("\(provider) · \(planType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .opacity(state.configuration.isEnabled ? 1 : 0.58)
    }

    private var alias: String {
        state.configuration.displayName
    }

    private var provider: String {
        descriptor.displayName
    }
}
