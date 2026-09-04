import SwiftUI

struct CredentialManagementView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController

    var body: some View {
        ScrollView {
            SettingsPageHeader(
                title: "凭证管理",
                subtitle: "\(environment.store.orderedKeyIDs.count) 个凭证"
            )
            .padding(24)
        }
    }
}
