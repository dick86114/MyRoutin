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
    /** 供应商接口返回的原始状态文本；null 表示接口未返回。 */
    val statusText: String? = null,
    /** 供应商返回的计费/续费模式；null 表示接口未返回。 */
    val billingMode: String? = null,
    val usageKind: String? = null,
    val allowedModels: List<String> = emptyList(),
    val groupMultipliers: List<UsageGroupMultiplier> = emptyList(),
)
