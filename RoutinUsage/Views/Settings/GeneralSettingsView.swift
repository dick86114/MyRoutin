import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ScrollView {
            SettingsPageHeader(
                title: "通用",
                subtitle: "刷新、启动与提醒"
            )
            .padding(24)
        }
    }
}
