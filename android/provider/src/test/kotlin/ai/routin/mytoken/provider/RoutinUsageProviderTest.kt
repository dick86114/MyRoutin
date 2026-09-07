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
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.routin.RoutinUsageProvider
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test

class RoutinUsageProviderTest {

    private val fixedClock: Clock = Clock.fixed(Instant.parse("2026-09-07T04:00:00Z"), ZoneOffset.UTC)
    private val transport = FakeHttpTransport()
    private val provider = RoutinUsageProvider(transport = transport, clock = fixedClock)

    private fun credential(): Credential = Credential(
        id = UUID.fromString("11111111-1111-4111-8111-111111111111"),
        providerId = ProviderId.Routin,
        credentialKind = CredentialKind.BearerApiKey,
        name = "Routin 示例",
        metadata = mapOf(CredentialMetadataKey.UsageKind to "periodic")
    )

    private fun ok(body: String) = ProviderHttpResponse(200, body.toByteArray())

    @Test
    fun fetchUsage_sendsBearerGetRequestToFixedEndpoint() = runTest {
        transport.responses += ok(readFixture("usage/routin-periodic.json"))

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("plan-test"))

        assertTrue(result.isSuccess)
        val request = transport.requests.single()
        assertEquals("GET", request.method)
        assertEquals("https://api.routin.ai/plan/v1/usage", request.url)
        assertEquals("Bearer plan-test", request.headers["Authorization"])
        assertEquals("application/json", request.headers["Accept"])
    }

    @Test
    fun fetchUsage_mapsPeriodicMetrics() = runTest {
        transport.responses += ok(readFixture("usage/routin-periodic.json"))

        val snapshot = provider.fetchUsage(credential(), CredentialSecret.BearerToken("plan-test"))
            .getOrThrow()

        assertEquals(fixedClock.instant(), snapshot.fetchedAt)
        assertEquals(listOf("fiveHour", "weekly"), snapshot.metrics.map { it.id })

        val fiveHour = snapshot.metrics[0]
        assertEquals("5 小时", fiveHour.label)
        assertEquals(0, fiveHour.used!!.compareTo(BigDecimal("2")))
        assertEquals(0, fiveHour.limit!!.compareTo(BigDecimal("10")))
        assertEquals(0, fiveHour.remaining!!.compareTo(BigDecimal("8")))
        assertEquals(UsageMetricUnit.Currency, fiveHour.unit)
        assertEquals("USD", fiveHour.currencyCode)
        assertEquals(UsageMetricPresentation.Progress, fiveHour.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, fiveHour.semantic)
        assertEquals(Instant.parse("2026-08-10T14:00:00Z"), fiveHour.windowEnd)

        val weekly = snapshot.metrics[1]
        assertEquals("周", weekly.label)
        assertEquals(0, weekly.used!!.compareTo(BigDecimal("10")))
        assertEquals(0, weekly.limit!!.compareTo(BigDecimal("50")))
        assertEquals(0, weekly.remaining!!.compareTo(BigDecimal("40")))
        assertEquals(Instant.parse("2026-08-15T00:00:00Z"), weekly.windowEnd)
    }

    @Test
    fun fetchUsage_derivesUsedWhenOnlyRemainingIsPresent() = runTest {
        transport.responses += ok(
            """
            {"planName":"Pro","type":1,"dailyLimitUsd":10,"dailyRemainingUsd":8}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))
            .getOrThrow()

        val fiveHour = snapshot.metrics.single { it.id == "fiveHour" }
        assertEquals(0, fiveHour.used!!.compareTo(BigDecimal("2")))
        assertEquals(0, fiveHour.remaining!!.compareTo(BigDecimal("8")))
    }

    @Test
    fun fetchUsage_mapsTokenPackMetric() = runTest {
        transport.responses += ok(readFixture("usage/routin-token-pack.json"))

        val snapshot = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))
            .getOrThrow()

        val token = snapshot.metrics.single()
        assertEquals("token", token.id)
        assertEquals("Token", token.label)
        assertEquals(0, token.used!!.compareTo(BigDecimal("250000")))
        assertEquals(0, token.limit!!.compareTo(BigDecimal("1000000")))
        assertEquals(0, token.remaining!!.compareTo(BigDecimal("750000")))
        assertEquals(UsageMetricUnit.Token, token.unit)
        assertEquals(UsageMetricPresentation.Progress, token.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, token.semantic)
    }

    @Test
    fun fetchUsage_jsonNullBodyYieldsSnapshotWithoutMetrics() = runTest {
        transport.responses += ok(" null ")

        val snapshot = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))
            .getOrThrow()

        assertTrue(snapshot.metrics.isEmpty())
    }

    @Test
    fun fetchUsage_invalidKeyBodyMapsToUnauthorized() = runTest {
        transport.responses += ProviderHttpResponse(401, """{"error":"invalid_api_key"}""".toByteArray())

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.Unauthorized)
    }

    @Test
    fun fetchUsage_other401MapsToInvalidResponse() = runTest {
        transport.responses += ProviderHttpResponse(401, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_429MapsToRateLimited() = runTest {
        transport.responses += ProviderHttpResponse(429, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.RateLimited)
    }

    @Test
    fun fetchUsage_5xxMapsToProviderUnavailable() = runTest {
        transport.responses += ProviderHttpResponse(503, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.ProviderUnavailable)
    }

    @Test
    fun fetchUsage_otherStatusMapsToInvalidResponse() = runTest {
        transport.responses += ProviderHttpResponse(404, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_malformedJsonMapsToInvalidResponse() = runTest {
        transport.responses += ok("{ not json")

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_missingLimitsMapsToInvalidResponse() = runTest {
        transport.responses += ok("""{"planName":"Pro"}""")

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_rejectsMismatchedCredentialKindWithoutNetworkCall() = runTest {
        val wrong = credential().copy(credentialKind = CredentialKind.ApiKey)

        val result = provider.fetchUsage(wrong, CredentialSecret.ApiKey("k"))

        assertTrue(result.exceptionOrNull() is ai.routin.mytoken.domain.usage.UsageProviderException.InvalidCredential)
        assertTrue(transport.requests.isEmpty())
    }

    private fun readFixture(name: String): String =
        javaClass.classLoader!!.getResourceAsStream(name)!!.readBytes().decodeToString()
}
