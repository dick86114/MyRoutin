package ai.routin.mytoken.provider

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.usage.UsageProviderException
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.glm.GLMUsageProvider
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test

class GLMUsageProviderTest {

    private val fixedClock: Clock = Clock.fixed(Instant.parse("2026-09-07T12:34:56Z"), ZoneOffset.UTC)
    private val transport = FakeHttpTransport()
    private val provider = GLMUsageProvider(transport = transport, clock = fixedClock)
    private val secret = CredentialSecret.ApiKey("glm-secret-key")

    private fun credential(baseURL: String? = null) = Credential(
        id = UUID.fromString("33333333-3333-4333-8333-333333333333"),
        providerId = ProviderId.Glm,
        credentialKind = CredentialKind.ApiKey,
        name = "GLM 示例",
        metadata = if (baseURL == null) {
            emptyMap()
        } else {
            mapOf(CredentialMetadataKey.BaseURL to baseURL)
        }
    )

    private fun ok(body: String) = ProviderHttpResponse(200, body.toByteArray())

    private fun queueSuccess() {
        transport.responses += ok(readFixture("usage/glm-model-usage.json"))
        transport.responses += ok(readFixture("usage/glm-quota-limit.json"))
        transport.responses += ok("""{"data":[{"id":"glm-5.3"},{"id":"glm-5.3-flash"},{"id":""}]}""")
    }

    @Test
    fun fetchUsage_requestsModelUsageThenQuotaLimitWithRawAuthorization() = runTest {
        queueSuccess()

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.isSuccess)
        assertEquals(3, transport.requests.size)

        val modelUsage = transport.requests[0]
        assertEquals("GET", modelUsage.method)
        assertEquals(
            "https://api.z.ai/api/monitor/usage/model-usage" +
                "?startTime=2026-09-06%2012:34:56&endTime=2026-09-07%2012:59:59",
            modelUsage.url
        )
        assertEquals("glm-secret-key", modelUsage.headers["Authorization"])
        assertEquals("application/json", modelUsage.headers["Content-Type"])
        assertEquals("en-US,en", modelUsage.headers["Accept-Language"])

        val quotaLimit = transport.requests[1]
        assertEquals(
            "https://api.z.ai/api/monitor/usage/quota/limit" +
                "?startTime=2026-09-06%2012:34:56&endTime=2026-09-07%2012:59:59",
            quotaLimit.url
        )

        val models = transport.requests[2]
        assertEquals("https://api.z.ai/api/coding/paas/v4/models", models.url)
        assertEquals("glm-secret-key", models.headers["Authorization"])
    }

    @Test
    fun fetchUsage_usesBaseURLMetadataWhenPresent() = runTest {
        queueSuccess()

        val result = provider.fetchUsage(credential(baseURL = "https://glm.example.com"), secret)

        assertTrue(result.isSuccess)
        assertTrue(transport.requests[0].url.startsWith("https://glm.example.com/api/monitor/usage/model-usage"))
        assertTrue(transport.requests[1].url.startsWith("https://glm.example.com/api/monitor/usage/quota/limit"))
    }

    @Test
    fun fetchUsage_mapsQuotaAndModelCallMetricsInStableOrder() = runTest {
        queueSuccess()

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertEquals(fixedClock.instant(), snapshot.fetchedAt)
        assertEquals(listOf("glm-5.3", "glm-5.3-flash"), snapshot.allowedModels)
        assertEquals(
            listOf("five-hour", "weekly", "model-calls", "zcode-mcp"),
            snapshot.metrics.map { it.id }
        )

        val fiveHour = snapshot.metrics[0]
        assertEquals("5 小时用量", fiveHour.label)
        assertEquals(0, fiveHour.used!!.compareTo(BigDecimal("42")))
        assertEquals(0, fiveHour.limit!!.compareTo(BigDecimal("100")))
        assertEquals(0, fiveHour.remaining!!.compareTo(BigDecimal("58")))
        assertEquals(UsageMetricUnit.Token, fiveHour.unit)
        assertEquals(UsageMetricPresentation.Progress, fiveHour.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, fiveHour.semantic)
        assertEquals(UsageMetricHealthState.Normal, fiveHour.healthState)
        assertEquals(Instant.ofEpochMilli(1893456000000L), fiveHour.windowEnd)

        val weekly = snapshot.metrics[1]
        assertEquals("每周用量", weekly.label)
        assertEquals(0, weekly.used!!.compareTo(BigDecimal("12")))
        assertEquals(0, weekly.remaining!!.compareTo(BigDecimal("88")))
        assertEquals(UsageMetricHealthState.Normal, weekly.healthState)

        val modelCalls = snapshot.metrics[2]
        assertEquals("模型调用量", modelCalls.label)
        assertEquals(0, modelCalls.value!!.compareTo(BigDecimal("22")))
        assertEquals(UsageMetricUnit.Request, modelCalls.unit)
        assertEquals(UsageMetricPresentation.Value, modelCalls.presentation)
        assertEquals(UsageMetricSemantic.Value, modelCalls.semantic)
        assertEquals(UsageMetricHealthState.Normal, modelCalls.healthState)

        val zcodeMcp = snapshot.metrics[3]
        assertEquals("MCP 调用量", zcodeMcp.label)
        assertEquals(0, zcodeMcp.used!!.compareTo(BigDecimal("461")))
        assertEquals(0, zcodeMcp.limit!!.compareTo(BigDecimal("1000")))
        assertEquals(0, zcodeMcp.remaining!!.compareTo(BigDecimal("539")))
        assertEquals(0, zcodeMcp.value!!.compareTo(BigDecimal("461")))
        assertEquals(UsageMetricUnit.Request, zcodeMcp.unit)
        assertEquals(UsageMetricPresentation.Value, zcodeMcp.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, zcodeMcp.semantic)
    }

    @Test
    fun fetchUsage_keepsEmptyModelsWhenModelRequestFails() = runTest {
        transport.responses += ok(readFixture("usage/glm-model-usage.json"))
        transport.responses += ok(readFixture("usage/glm-quota-limit.json"))
        transport.responses += ProviderHttpResponse(404, "{}".toByteArray())

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertTrue(snapshot.allowedModels.isEmpty())
        assertEquals(4, snapshot.metrics.size)
    }

    @Test
    fun fetchUsage_marksHighUsageAsCritical() = runTest {
        transport.responses += ok("""{"data":{"totalUsage":{"totalModelCallCount":1}}}""")
        transport.responses += ok(
            """
            {"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":85}]}}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertEquals(UsageMetricHealthState.Critical, snapshot.metrics[0].healthState)
    }

    @Test
    fun fetchUsage_marksModerateUsageAsWarning() = runTest {
        transport.responses += ok("""{"data":{"totalUsage":{"totalModelCallCount":1}}}""")
        transport.responses += ok(
            """
            {"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":55}]}}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertEquals(UsageMetricHealthState.Warning, snapshot.metrics[0].healthState)
    }

    @Test
    fun fetchUsage_emptyMetricsFailsWithInvalidResponse() = runTest {
        transport.responses += ok("""{"data":{}}""")
        transport.responses += ok("""{"data":{"limits":[]}}""")

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_401MapsToUnauthorized() = runTest {
        transport.responses += ProviderHttpResponse(401, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.Unauthorized)
    }

    @Test
    fun fetchUsage_429MapsToRateLimited() = runTest {
        transport.responses += ProviderHttpResponse(429, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.RateLimited)
    }

    @Test
    fun fetchUsage_5xxMapsToProviderUnavailable() = runTest {
        transport.responses += ProviderHttpResponse(502, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.ProviderUnavailable)
    }

    @Test
    fun fetchUsage_errorsNeverContainTheSecret() = runTest {
        transport.responses += ProviderHttpResponse(401, "{}".toByteArray())

        val error = provider.fetchUsage(credential(), secret).exceptionOrNull()

        assertTrue(error!!.message?.contains(secret.key) != true)
    }

    private fun readFixture(name: String): String =
        javaClass.classLoader!!.getResourceAsStream(name)!!.readBytes().decodeToString()
}
