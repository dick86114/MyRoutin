package ai.routin.mytoken.domain.model

import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

data class UsageGroupMultiplier(
    val name: String,
    val multiplier: BigDecimal,
)

data class UsageSnapshot(
    val credentialId: UUID,
    val fetchedAt: Instant,
    val metrics: List<UsageMetric>,
    val planName: String = "",
    val subscriptionStartAt: Instant? = null,
    val subscriptionEndAt: Instant? = null,
    val status: Int? = null,
    val usageKind: String? = null,
    val allowedModels: List<String> = emptyList(),
    val groupMultipliers: List<UsageGroupMultiplier> = emptyList(),
)
