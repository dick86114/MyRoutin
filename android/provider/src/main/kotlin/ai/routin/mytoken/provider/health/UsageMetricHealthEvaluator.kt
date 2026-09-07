package ai.routin.mytoken.provider.health

import ai.routin.mytoken.domain.model.UsageMetricHealthState
import java.math.BigDecimal

/** Health evaluation, aligned with the macOS UsageMetricHealthEvaluator. */
object UsageMetricHealthEvaluator {

    fun balanceState(
        balance: BigDecimal,
        warningThreshold: BigDecimal?,
        isAvailable: Boolean,
    ): UsageMetricHealthState {
        if (!isAvailable) return UsageMetricHealthState.Unavailable
        if (balance.signum() <= 0) return UsageMetricHealthState.Critical
        if (warningThreshold != null && warningThreshold.signum() > 0 && balance < warningThreshold) {
            return UsageMetricHealthState.Warning
        }
        return UsageMetricHealthState.Normal
    }

    fun fromPercent(percent: Double): UsageMetricHealthState = when {
        percent >= 80 -> UsageMetricHealthState.Critical
        percent >= 50 -> UsageMetricHealthState.Warning
        else -> UsageMetricHealthState.Normal
    }
}
