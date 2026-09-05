import Foundation

struct MenuBarMetricResolution: Equatable, Sendable {
    let selectedMetricID: String?
    let metric: NormalizedUsageMetric?
    let isFallback: Bool
}

enum MenuBarMetricResolver {
    static func options(
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability]
    ) -> [UsageMetricCapability] {
        let capabilityByID = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.metricID, $0) })
        var representedIDs = Set<String>()
        var options: [UsageMetricCapability] = []

        for metric in metrics {
            if let capability = capabilityByID[metric.id] {
                guard isSelectable(capability) else { continue }
                options.append(capability)
            } else {
                guard let capability = synthesizedCapability(for: metric) else { continue }
                options.append(capability)
            }

            representedIDs.insert(metric.id)
        }

        let declaredOptions = capabilities
            .filter { isSelectable($0) && !representedIDs.contains($0.metricID) }
            .sorted {
                menuOrder($0) < menuOrder($1)
            }

        return options + declaredOptions
    }

    static func resolve(
        selectedMetricID: String?,
        metrics: [NormalizedUsageMetric],
        capabilities: [UsageMetricCapability]
    ) -> MenuBarMetricResolution {
        let metricByID = Dictionary(uniqueKeysWithValues: metrics.map { ($0.id, $0) })
        let capabilityByID = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.metricID, $0) })

        if let selectedMetricID,
           let metric = metricByID[selectedMetricID],
           isSelectable(capabilityByID[selectedMetricID] ?? synthesizedCapability(for: metric)) {
            return MenuBarMetricResolution(
                selectedMetricID: selectedMetricID,
                metric: metric,
                isFallback: false
            )
        }

        var automaticCandidates: [(index: Int, metric: NormalizedUsageMetric, order: Int)] = []
        for (index, metric) in metrics.enumerated() {
            guard let capability = capabilityByID[metric.id] ?? synthesizedCapability(for: metric) else { continue }
            guard isSelectable(capability) else { continue }
            automaticCandidates.append((index, metric, menuOrder(capability)))
        }
        automaticCandidates.sort {
            $0.order == $1.order ? $0.index < $1.index : $0.order < $1.order
        }
        let automaticMetric = automaticCandidates.first?.metric

        return MenuBarMetricResolution(
            selectedMetricID: selectedMetricID,
            metric: automaticMetric,
            isFallback: selectedMetricID != nil
        )
    }

    private static func isSelectable(_ capability: UsageMetricCapability?) -> Bool {
        capability?.isMenuBarSelectable == true && capability?.presentation != .value
    }

    private static func synthesizedCapability(
        for metric: NormalizedUsageMetric
    ) -> UsageMetricCapability? {
        switch (metric.presentation, metric.semantic) {
        case (.progress, .usedQuota), (.progress, .remainingQuota):
            return UsageMetricCapability(
                metricID: metric.id,
                label: metric.label,
                presentation: .progress,
                semantic: metric.semantic,
                isMenuBarSelectable: true,
                menuBarPriority: nil,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            )
        case (.balance, .balance):
            return UsageMetricCapability(
                metricID: metric.id,
                label: metric.label,
                presentation: .balance,
                semantic: .balance,
                isMenuBarSelectable: true,
                menuBarPriority: nil,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            )
        case (.status, .status):
            return UsageMetricCapability(
                metricID: metric.id,
                label: metric.label,
                presentation: .status,
                semantic: .status,
                isMenuBarSelectable: true,
                menuBarPriority: nil,
                defaultAlertEnabled: true,
                defaultAbsoluteAlertThreshold: nil
            )
        default:
            return nil
        }
    }

    private static func menuOrder(_ capability: UsageMetricCapability) -> Int {
        let priority = capability.menuBarPriority ?? Int.max
        let presentationOrder: Int = switch capability.presentation {
        case .progress: 0
        case .balance: 1
        case .status: 2
        case .value: 3
        }
        return priority * 10 + presentationOrder
    }
}
