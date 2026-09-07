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
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Cross-platform JSON contract: encoded enum values must use the macOS rawValue
 * spelling (e.g. `boolean`, `progress`, `usedQuota`, `normal`), not the Kotlin enum
 * constant names (e.g. `Boolean_`).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class UsageSnapshotJsonCodecTest {

    private val credentialId = UUID.fromString("11111111-1111-4111-8111-111111111111")

    private fun metric() = UsageMetric(
        id = "availability",
        label = "账户状态",
        used = BigDecimal("1"),
        limit = BigDecimal("2"),
        remaining = BigDecimal("3"),
        value = BigDecimal("4"),
        unit = UsageMetricUnit.Boolean_,
        windowStart = Instant.parse("2026-09-07T00:00:00Z"),
        windowEnd = Instant.parse("2026-09-07T01:00:00Z"),
        presentation = UsageMetricPresentation.Progress,
        semantic = UsageMetricSemantic.UsedQuota,
        currencyCode = "USD",
        healthState = UsageMetricHealthState.Normal
    )

    @Test
    fun encode_usesMacOsRawValuesForEnums() {
        val json = JSONObject(UsageSnapshotJsonCodec.encode(snapshot()))

        val metricJson = json.getJSONArray("metrics").getJSONObject(0)
        assertEquals("boolean", metricJson.getString("unit"))
        assertEquals("progress", metricJson.getString("presentation"))
        assertEquals("usedQuota", metricJson.getString("semantic"))
        assertEquals("normal", metricJson.getString("healthState"))
    }

    @Test
    fun decode_acceptsMacOsRawValueJson() {
        val json = """
            {
              "fetchedAt": "2026-09-07T04:00:00Z",
              "metrics": [
                {
                  "id": "availability",
                  "label": "账户状态",
                  "used": "1",
                  "limit": "2",
                  "remaining": "3",
                  "value": "4",
                  "unit": "boolean",
                  "windowStart": "2026-09-07T00:00:00Z",
                  "windowEnd": "2026-09-07T01:00:00Z",
                  "presentation": "progress",
                  "semantic": "usedQuota",
                  "currencyCode": "USD",
                  "healthState": "normal"
                }
              ]
            }
        """.trimIndent()

        val snapshot = UsageSnapshotJsonCodec.decode(credentialId, json)

        assertEquals(snapshot(), snapshot)
    }

    @Test
    fun roundTrip_preservesMetricValues() {
        val encoded = UsageSnapshotJsonCodec.encode(snapshot())

        assertEquals(snapshot(), UsageSnapshotJsonCodec.decode(credentialId, encoded))
    }

    @Test
    fun decode_returnsNullForUnknownEnumValue() {
        val json = """
            {
              "fetchedAt": "2026-09-07T04:00:00Z",
              "metrics": [
                {
                  "id": "availability",
                  "label": "账户状态",
                  "unit": "boolean TYPO",
                  "presentation": "progress",
                  "semantic": "usedQuota",
                  "healthState": "normal"
                }
              ]
            }
        """.trimIndent()

        assertNull(UsageSnapshotJsonCodec.decode(credentialId, json))
    }

    @Test
    fun decode_returnsNullForLegacyKotlinEnumNames() {
        // Caches written by the previous buggy codec (Kotlin .name spelling) are not readable;
        // they degrade to a cache miss instead of crashing.
        val json = """
            {
              "fetchedAt": "2026-09-07T04:00:00Z",
              "metrics": [
                {
                  "id": "availability",
                  "label": "账户状态",
                  "unit": "Boolean_",
                  "presentation": "Progress",
                  "semantic": "UsedQuota",
                  "healthState": "Normal"
                }
              ]
            }
        """.trimIndent()

        assertNull(UsageSnapshotJsonCodec.decode(credentialId, json))
    }

    private fun snapshot() = UsageSnapshot(
        credentialId = credentialId,
        fetchedAt = Instant.parse("2026-09-07T04:00:00Z"),
        metrics = listOf(metric())
    )
}
