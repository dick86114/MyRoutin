package ai.routin.mytoken.data.local

import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageGroupMultiplier
import ai.routin.mytoken.domain.model.UsageSnapshot
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * JSON codec for cached [UsageSnapshot] values, using org.json (no extra dependency).
 *
 * Enum values are serialized with the cross-platform rawValue spelling (e.g. `boolean`,
 * `progress`, `usedQuota`, `normal`) so cached snapshots stay interchangeable with the
 * macOS implementation.
 */
object UsageSnapshotJsonCodec {

    fun encode(snapshot: UsageSnapshot): String {
        val metrics = JSONArray()
        for (metric in snapshot.metrics) {
            metrics.put(
                JSONObject()
                    .put("id", metric.id)
                    .put("label", metric.label)
                    .putOpt("used", metric.used?.toPlainString())
                    .putOpt("limit", metric.limit?.toPlainString())
                    .putOpt("remaining", metric.remaining?.toPlainString())
                    .putOpt("value", metric.value?.toPlainString())
                    .put("unit", metric.unit.rawValue)
                    .putOpt("windowStart", metric.windowStart?.toString())
                    .putOpt("windowEnd", metric.windowEnd?.toString())
                    .put("presentation", metric.presentation.rawValue)
                    .put("semantic", metric.semantic.rawValue)
                    .putOpt("currencyCode", metric.currencyCode)
                    .put("healthState", metric.healthState.rawValue)
            )
        }
        return JSONObject()
            .put("credentialId", snapshot.credentialId.toString())
            .put("fetchedAt", snapshot.fetchedAt.toString())
            .putOpt("planName", snapshot.planName.takeIf { it.isNotEmpty() })
            .putOpt("subscriptionStartAt", snapshot.subscriptionStartAt?.toString())
            .putOpt("subscriptionEndAt", snapshot.subscriptionEndAt?.toString())
            .putOpt("status", snapshot.status)
            .putOpt("statusText", snapshot.statusText)
            .putOpt("billingMode", snapshot.billingMode)
            .putOpt("usageKind", snapshot.usageKind)
            .put("allowedModels", JSONArray(snapshot.allowedModels))
            .put(
                "groupMultipliers",
                JSONArray().apply {
                    snapshot.groupMultipliers.forEach { group ->
                        put(
                            JSONObject()
                                .put("name", group.name)
                                .put("multiplier", group.multiplier.toPlainString())
                        )
                    }
                }
            )
            .put("metrics", metrics)
            .toString()
    }

    fun decode(credentialId: UUID, json: String): UsageSnapshot? = runCatching {
        val root = JSONObject(json)
        val metricsJson = root.getJSONArray("metrics")
        val metrics = (0 until metricsJson.length()).map { index ->
            val item = metricsJson.getJSONObject(index)
            UsageMetric(
                id = item.getString("id"),
                label = item.getString("label"),
                used = item.optNullableString("used")?.let(::BigDecimal),
                limit = item.optNullableString("limit")?.let(::BigDecimal),
                remaining = item.optNullableString("remaining")?.let(::BigDecimal),
                value = item.optNullableString("value")?.let(::BigDecimal),
                unit = requireNotNull(UsageMetricUnit.fromRawValue(item.getString("unit"))) { "unknown unit" },
                windowStart = item.optNullableString("windowStart")?.let(Instant::parse),
                windowEnd = item.optNullableString("windowEnd")?.let(Instant::parse),
                presentation = requireNotNull(
                    UsageMetricPresentation.fromRawValue(item.getString("presentation"))
                ) { "unknown presentation" },
                semantic = requireNotNull(UsageMetricSemantic.fromRawValue(item.getString("semantic"))) { "unknown semantic" },
                currencyCode = item.optNullableString("currencyCode"),
                healthState = UsageMetricHealthState.fromRawValue(item.getString("healthState"))
                    ?: UsageMetricHealthState.Unknown
            )
        }
        UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = Instant.parse(root.getString("fetchedAt")),
            planName = root.optNullableString("planName").orEmpty(),
            subscriptionStartAt = root.optNullableString("subscriptionStartAt")?.let(Instant::parse),
            subscriptionEndAt = root.optNullableString("subscriptionEndAt")?.let(Instant::parse),
            status = if (root.has("status") && !root.isNull("status")) root.getInt("status") else null,
            statusText = root.optNullableString("statusText"),
            billingMode = root.optNullableString("billingMode"),
            usageKind = root.optNullableString("usageKind"),
            allowedModels = root.optJSONArray("allowedModels")
                ?.let { array -> (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotEmpty) } }
                ?: emptyList(),
            groupMultipliers = root.optJSONArray("groupMultipliers")
                ?.let { groups ->
                    (0 until groups.length()).mapNotNull { index ->
                        val item = groups.optJSONObject(index) ?: return@mapNotNull null
                        val multiplier = item.optNullableString("multiplier")?.let(::BigDecimal) ?: return@mapNotNull null
                        UsageGroupMultiplier(item.optString("name"), multiplier)
                    }
                }
                ?: emptyList(),
            metrics = metrics
        )
    }.getOrNull()

    private fun JSONObject.optNullableString(key: String): String? =
        if (isNull(key)) null else getString(key)
}
