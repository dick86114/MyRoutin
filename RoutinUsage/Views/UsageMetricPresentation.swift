import SwiftUI

enum UsageMetricTone: Equatable {
    case normal
    case warning
    case critical

    var color: Color {
        switch self {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}

enum UsageMetricPresentation {
    static func clampedPercent(_ percent: Double) -> Double {
        guard percent.isFinite else {
            return 0
        }
        return min(max(percent, 0), 100)
    }

    static func tone(for percent: Double) -> UsageMetricTone {
        switch MenuBarUsageRisk.level(for: percent) {
        case .normal:
            return .normal
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }

    static func color(for percent: Double) -> Color {
        tone(for: percent).color
    }
}

struct UsageMetricProgressBar: View {
    let percent: Double

    init(percent: Double) {
        self.percent = percent
    }

    init(metric: UsageMetric) {
        percent = metric.percent
    }

    var body: some View {
        GeometryReader { geometry in
            let clampedPercent = UsageMetricPresentation.clampedPercent(percent)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(UsageMetricPresentation.color(for: percent))
                    .frame(
                        width: max(
                            clampedPercent == 0 ? 0 : 2,
                            geometry.size.width * clampedPercent / 100
                        )
                    )
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

enum ProviderTheme {
    static func accentColor(for providerID: ProviderID) -> Color {
        switch providerID {
        case .routin:
            return .blue
        case .deepseek:
            return .indigo
        case .glm:
            return .green
        case .volcengine:
            return .orange
        case .newAPI:
            return .purple
        case .commandCode:
            return .teal
        }
    }

    static func background(for providerID: ProviderID) -> Color {
        accentColor(for: providerID).opacity(0.10)
    }

    static func borderColor(for providerID: ProviderID) -> Color {
        accentColor(for: providerID).opacity(0.18)
    }
}
