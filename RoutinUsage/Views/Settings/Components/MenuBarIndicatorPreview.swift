import AppKit
import SwiftUI

struct MenuBarIndicatorPreview: View {
    @Bindable var environment: AppEnvironment
    let state: KeyUsageState
    let descriptor: ProviderDescriptor

    var body: some View {
        let indicator = MenuBarIndicatorModel.make(
            state: state,
            descriptor: descriptor,
            dimension: environment.settings.displayDimension
        )
        let image = MenuBarMultiUsageIcon.image(
            indicators: [indicator],
            appearance: NSApp.effectiveAppearance
        )

        Image(nsImage: image)
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 26)
    }
}
