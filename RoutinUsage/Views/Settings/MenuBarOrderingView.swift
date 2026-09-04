import SwiftUI

struct MenuBarOrderingView: View {
    @Bindable var environment: AppEnvironment
    let ordering: CredentialOrderingController

    var body: some View {
        ScrollView {
            SettingsPageHeader(
                title: "菜单栏显示",
                subtitle: "菜单栏图标排序"
            )
            .padding(24)
        }
    }
}
