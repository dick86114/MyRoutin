import Foundation

struct UsageMetricCapability: Codable, Equatable, Identifiable, Sendable {
    let metricID: String
    let label: String
    let presentation: NormalizedUsageMetricPresentation
    let semantic: NormalizedUsageMetricSemantic
    let isMenuBarSelectable: Bool
    let menuBarPriority: Int?
    let defaultAlertEnabled: Bool
    let defaultAbsoluteAlertThreshold: Decimal?

    var id: String { metricID }
}
