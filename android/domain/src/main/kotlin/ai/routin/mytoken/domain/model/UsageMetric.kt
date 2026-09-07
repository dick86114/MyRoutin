package ai.routin.mytoken.domain.model

import java.math.BigDecimal
import java.time.Instant

enum class UsageMetricUnit {
    Token,
    Currency,
    Request,
    Boolean_,
    Text
}

enum class UsageMetricPresentation {
    Progress,
    Balance,
    Status,
    Value
}

enum class UsageMetricSemantic {
    UsedQuota,
    RemainingQuota,
    Balance,
    Status,
    Value
}

enum class UsageMetricHealthState {
    Normal,
    Warning,
    Critical,
    Unavailable,
    Stale,
    Unknown
}

data class UsageMetric(
    val id: String,
    val label: String,
    val used: BigDecimal? = null,
    val limit: BigDecimal? = null,
    val remaining: BigDecimal? = null,
    val value: BigDecimal? = null,
    val unit: UsageMetricUnit,
    val windowStart: Instant? = null,
    val windowEnd: Instant? = null,
    val presentation: UsageMetricPresentation,
    val semantic: UsageMetricSemantic,
    val currencyCode: String? = null,
    val healthState: UsageMetricHealthState = UsageMetricHealthState.Unknown
)
