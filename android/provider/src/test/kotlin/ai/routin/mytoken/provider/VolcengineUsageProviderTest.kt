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
import ai.routin.mytoken.provider.volcengine.VolcengineUsageProvider
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test

class VolcengineUsageProviderTest {

    private val fixedClock: Clock = Clock.fixed(Instant.parse("2026-09-07T04:00:00Z"), ZoneOffset.UTC)
    private val transport = FakeHttpTransport()
    private val provider = VolcengineUsageProvider(transport = transport, clock = fixedClock)
    private val secret = CredentialSecret.AccessKeyPair(
        accessKeyID = "access-key",
        secretAccessKey = "secret-key"
    )

    private fun credential(planType: String) = Credential(
        id = UUID.fromString("44444444-4444-4444-8444-444444444444"),
        providerId = ProviderId.Volcengine,
        credentialKind = CredentialKind.AccessKeyPair,
        name = "火山方舟示例",
        metadata = mapOf(
            CredentialMetadataKey.Region to "cn-beijing",
            CredentialMetadataKey.PlanType to planType
        )
    )

    private fun ok(body: String) = ProviderHttpResponse(200, body.toByteArray())

    @Test
    fun fetchUsage_sendsSignedAgentPlanRequestByDefault() = runTest {
        transport.responses += ok(readFixture("usage/volcengine-usage.json"))

        val result = provider.fetchUsage(credential(planType = "agent"), secret)

        assertTrue(result.isSuccess)
        val request = transport.requests.single()
        assertEquals("POST", request.method)
        assertEquals("https://open.volcengineapi.com/?Action=GetAgentPlanAFPUsage&Version=2024-01-01", request.url)
        assertEquals("{}".toByteArray().toList(), request.body!!.toList())
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals("open.volcengineapi.com", request.headers["Host"])
        val authorization = request.headers["Authorization"]!!
        assertTrue(authorization.startsWith("HMAC-SHA256 Credential=access-key/20260907/cn-beijing/ark/request"))
        assertTrue(authorization.contains("SignedHeaders=content-type;host;x-content-sha256;x-date"))
        assertEquals(
            "20260907T040000Z",
            request.headers["X-Date"]
        )
    }

    @Test
    fun fetchUsage_usesCodingPlanActionForCodingPlanType() = runTest {
        transport.responses += ok(readFixture("usage/volcengine-coding-usage.json"))

        val result = provider.fetchUsage(credential(planType = "coding"), secret)

        assertTrue(result.isSuccess)
        assertEquals(
            "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01",
            transport.requests.single().url
        )
    }

    @Test
    fun fetchUsage_mapsAfpWindowMetrics() = runTest {
        transport.responses += ok(readFixture("usage/volcengine-usage.json"))

        val snapshot = provider.fetchUsage(credential(planType = "coding"), secret).getOrThrow()

        assertEquals(fixedClock.instant(), snapshot.fetchedAt)
        assertEquals(listOf("fiveHour", "weekly", "monthly"), snapshot.metrics.map { it.id })

        val fiveHour = snapshot.metrics[0]
        assertEquals("近 5 小时用量", fiveHour.label)
        assertEquals(0, fiveHour.used!!.compareTo(BigDecimal("0")))
        assertEquals(0, fiveHour.limit!!.compareTo(BigDecimal("10000")))
        assertEquals(0, fiveHour.remaining!!.compareTo(BigDecimal("10000")))
        assertEquals(UsageMetricUnit.Request, fiveHour.unit)
        assertEquals(UsageMetricPresentation.Progress, fiveHour.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, fiveHour.semantic)
        assertEquals(UsageMetricHealthState.Normal, fiveHour.healthState)
        assertEquals(Instant.ofEpochMilli(1893456000000L), fiveHour.windowEnd)

        val weekly = snapshot.metrics[1]
        assertEquals("近一周用量", weekly.label)
        assertEquals(0, weekly.used!!.compareTo(BigDecimal("3252.2867")))
        assertEquals(0, weekly.limit!!.compareTo(BigDecimal("35000")))
        assertEquals(0, weekly.remaining!!.compareTo(BigDecimal("31747.7133")))
        assertEquals(UsageMetricHealthState.Normal, weekly.healthState)

        val monthly = snapshot.metrics[2]
        assertEquals("近一月用量", monthly.label)
        assertEquals(0, monthly.used!!.compareTo(BigDecimal("41222.3834")))
        assertEquals(0, monthly.remaining!!.compareTo(BigDecimal("58777.6166")))
        assertEquals(UsageMetricHealthState.Normal, monthly.healthState)
    }

    @Test
    fun fetchUsage_skipsWindowsWithoutQuota() = runTest {
        transport.responses += ok(
            """
            {"Result":{"AFPFiveHour":{"Quota":0,"Used":0},
            "AFPWeekly":{"Quota":"35000","Used":"3252.2867"}}}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(planType = "agent"), secret).getOrThrow()

        assertEquals(listOf("weekly"), snapshot.metrics.map { it.id })
    }

    @Test
    fun fetchUsage_fallsBackToQuotaUsageItems() = runTest {
        transport.responses += ok(readFixture("usage/volcengine-coding-usage.json"))

        val snapshot = provider.fetchUsage(credential(planType = "coding"), secret).getOrThrow()

        assertEquals(listOf("coding-0"), snapshot.metrics.map { it.id })
        val metric = snapshot.metrics[0]
        assertEquals("5h", metric.label)
        assertEquals(0, metric.used!!.compareTo(BigDecimal("10")))
        assertEquals(0, metric.limit!!.compareTo(BigDecimal("100")))
        assertEquals(0, metric.remaining!!.compareTo(BigDecimal("90")))
        assertEquals(UsageMetricPresentation.Progress, metric.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, metric.semantic)
        assertEquals(Instant.ofEpochSecond(1893456000L), metric.windowEnd)
    }

    @Test
    fun fetchUsage_highUsageMarksCritical() = runTest {
        transport.responses += ok("""{"Result":{"QuotaUsage":[{"Level":"5h","Percent":85}]}}""")

        val snapshot = provider.fetchUsage(credential(planType = "coding"), secret).getOrThrow()

        assertEquals(UsageMetricHealthState.Critical, snapshot.metrics[0].healthState)
    }

    @Test
    fun fetchUsage_missingResultFailsWithInvalidResponse() = runTest {
        transport.responses += ok("""{"ResponseMetadata":{}}""")

        val result = provider.fetchUsage(credential(planType = "coding"), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_emptyMetricsFailsWithInvalidResponse() = runTest {
        transport.responses += ok("""{"Result":{}}""")

        val result = provider.fetchUsage(credential(planType = "coding"), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_errorBodyMapsToProviderMessageWithoutSecret() = runTest {
        transport.responses += ProviderHttpResponse(400, readFixture("usage/volcengine-error.json").toByteArray())

        val error = provider.fetchUsage(credential(planType = "agent"), secret).exceptionOrNull()

        assertTrue(error is UsageProviderException.ProviderMessage)
        assertEquals("火山方舟：InvalidAccessKey：The access key is invalid", error!!.message)
        assertTrue(error.message?.contains("secret-key") != true)
        assertTrue(error.message?.contains("access-key") != true)
    }

    @Test
    fun fetchUsage_401WithoutErrorBodyMapsToUnauthorized() = runTest {
        transport.responses += ProviderHttpResponse(401, "{}".toByteArray())

        val result = provider.fetchUsage(credential(planType = "agent"), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.Unauthorized)
    }

    @Test
    fun fetchUsage_429MapsToRateLimited() = runTest {
        transport.responses += ProviderHttpResponse(429, "{}".toByteArray())

        val result = provider.fetchUsage(credential(planType = "agent"), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.RateLimited)
    }

    @Test
    fun fetchUsage_5xxMapsToProviderUnavailable() = runTest {
        transport.responses += ProviderHttpResponse(500, "{}".toByteArray())

        val result = provider.fetchUsage(credential(planType = "agent"), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.ProviderUnavailable)
    }

    @Test
    fun fetchUsage_malformedSuccessBodyFailsWithInvalidResponse() = runTest {
        transport.responses += ok("{ nope")

        val result = provider.fetchUsage(credential(planType = "agent"), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_missingRegionFailsWithInvalidCredentialWithoutNetworkCall() = runTest {
        val credential = Credential(
            id = UUID.randomUUID(),
            providerId = ProviderId.Volcengine,
            credentialKind = CredentialKind.AccessKeyPair,
            name = "火山方舟示例",
            metadata = emptyMap()
        )

        val result = provider.fetchUsage(credential, secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidCredential)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun fetchUsage_rejectsWrongProviderWithoutNetworkCall() = runTest {
        val credential = credential(planType = "agent").copy(providerId = ProviderId.DeepSeek)

        val result = provider.fetchUsage(credential, secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidCredential)
        assertTrue(transport.requests.isEmpty())
    }

    private fun readFixture(name: String): String =
        javaClass.classLoader!!.getResourceAsStream(name)!!.readBytes().decodeToString()
}
