package ai.routin.mytoken.domain.model

import java.time.Instant
import java.util.UUID

data class UsageSnapshot(
    val credentialId: UUID,
    val fetchedAt: Instant,
    val metrics: List<UsageMetric>
)
