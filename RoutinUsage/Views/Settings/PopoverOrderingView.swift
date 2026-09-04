import SwiftUI

struct PopoverOrderingView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController

    var body: some View {
        ScrollView {
            SettingsPageHeader(
                title: "弹窗显示",
                subtitle: "弹窗凭证排序"
            )
            .padding(24)
        }
    }
}
