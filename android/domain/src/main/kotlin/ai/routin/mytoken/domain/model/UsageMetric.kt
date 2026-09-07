package ai.routin.mytoken.domain.model

import java.math.BigDecimal
import java.time.Instant

enum class UsageMetricUnit(val rawValue: String) {
    Token("token"),
    Currency("currency"),
    Request("request"),
    Boolean_("boolean"),
    Text("text");

    companion object {
        fun fromRawValue(value: String): UsageMetricUnit? =
            entries.firstOrNull { it.rawValue == value }
    }
}

enum class UsageMetricPresentation(val rawValue: String) {
    Progress("progress"),
    Balance("balance"),
    Status("status"),
    Value("value");

    companion object {
        fun fromRawValue(value: String): UsageMetricPresentation? =
            entries.firstOrNull { it.rawValue == value }
    }
}

enum class UsageMetricSemantic(val rawValue: String) {
    UsedQuota("usedQuota"),
    RemainingQuota("remainingQuota"),
    Balance("balance"),
    Status("status"),
    Value("value");

    companion object {
        fun fromRawValue(value: String): UsageMetricSemantic? =
            entries.firstOrNull { it.rawValue == value }
    }
}

enum class UsageMetricHealthState(val rawValue: String) {
    Normal("normal"),
    Warning("warning"),
    Critical("critical"),
    Unavailable("unavailable"),
    Stale("stale"),
    Unknown("unknown");

    companion object {
        fun fromRawValue(value: String): UsageMetricHealthState? =
            entries.firstOrNull { it.rawValue == value }
    }
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
