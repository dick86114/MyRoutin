import SwiftUI

struct HelpUpdateView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ScrollView {
            SettingsPageHeader(
                title: "帮助与更新",
                subtitle: "版本维护与反馈"
            )
            .padding(24)
        }
    }
}
