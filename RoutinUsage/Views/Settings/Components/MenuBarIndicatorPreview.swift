import AppKit
import SwiftUI

struct MenuBarIndicatorPreview: View, Equatable {
    let state: KeyUsageState
    let descriptor: ProviderDescriptor
    let dimension: DisplayDimension

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state
            && lhs.descriptor == rhs.descriptor
            && lhs.dimension == rhs.dimension
    }

    var body: some View {
        let indicator = MenuBarIndicatorModel.make(
            state: state,
            descriptor: descriptor,
            dimension: dimension
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
