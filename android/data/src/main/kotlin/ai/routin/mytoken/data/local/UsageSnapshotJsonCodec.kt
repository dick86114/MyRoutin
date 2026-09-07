package ai.routin.mytoken.data.local

import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** JSON codec for cached [UsageSnapshot] values, using org.json (no extra dependency). */
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
                    .put("unit", metric.unit.name)
                    .putOpt("windowStart", metric.windowStart?.toString())
                    .putOpt("windowEnd", metric.windowEnd?.toString())
                    .put("presentation", metric.presentation.name)
                    .put("semantic", metric.semantic.name)
                    .putOpt("currencyCode", metric.currencyCode)
                    .put("healthState", metric.healthState.name)
            )
        }
        return JSONObject()
            .put("credentialId", snapshot.credentialId.toString())
            .put("fetchedAt", snapshot.fetchedAt.toString())
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
                unit = UsageMetricUnit.valueOf(item.getString("unit")),
                windowStart = item.optNullableString("windowStart")?.let(Instant::parse),
                windowEnd = item.optNullableString("windowEnd")?.let(Instant::parse),
                presentation = UsageMetricPresentation.valueOf(item.getString("presentation")),
                semantic = UsageMetricSemantic.valueOf(item.getString("semantic")),
                currencyCode = item.optNullableString("currencyCode"),
                healthState = UsageMetricHealthState.valueOf(item.getString("healthState"))
            )
        }
        UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = Instant.parse(root.getString("fetchedAt")),
            metrics = metrics
        )
    }.getOrNull()

    private fun JSONObject.optNullableString(key: String): String? =
        if (isNull(key)) null else getString(key)
}
