package ai.routin.mytoken.provider

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.usage.UsageProviderException
import ai.routin.mytoken.provider.http.HttpTransport
import ai.routin.mytoken.provider.http.ProviderHttpRequest
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.newapi.NewAPIUsageProvider
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NewAPIUsageProviderTest {

    private val fixedClock = Clock.fixed(Instant.parse("2026-09-07T04:00:00Z"), ZoneOffset.UTC)

    private class RoutingTransport : HttpTransport {
        val requests = mutableListOf<ProviderHttpRequest>()

        override suspend fun execute(request: ProviderHttpRequest): ProviderHttpResponse {
            requests += request
            val body = when {
                request.url.endsWith("/api/status") -> envelope(
                    """
                    {
                      "quota_per_unit": 500000,
                      "quota_display_type": "CNY",
                      "usd_exchange_rate": 7
                    }
                    """.trimIndent()
                )
                request.url.endsWith("/api/user/self") -> envelope(
                    """
                    {
                      "quota": 750000,
                      "used_quota": 250000,
                      "request_count": 42,
                      "group": "vip"
                    }
                    """.trimIndent()
                )
                request.url.contains("/api/data/self?") -> envelope("""[{"token_used": 12, "count": 2, "quota": 100000}]""")
                request.url.contains("/api/log/self/stat?") -> envelope("""{"rpm": 3, "tpm": 456}""")
                else -> throw IllegalStateException("unexpected url: ${request.url}")
            }
            return ProviderHttpResponse(200, body.toByteArray())
        }

        private fun envelope(data: String) =
            """{"success":true,"message":"","data":$data}""".toByteArray().decodeToString()
    }

    private fun credential(baseURL: String = "https://newapi.example.com") = Credential(
        id = UUID.fromString("11111111-1111-4111-8111-111111111111"),
        providerId = ProviderId.NewAPI,
        credentialKind = CredentialKind.BearerApiKey,
        name = "New API",
        metadata = mapOf(
            CredentialMetadataKey.BaseURL to baseURL,
            CredentialMetadataKey.UserID to "128",
        ),
    )

    @Test
    fun fetchUsage_requestsAllEndpointsWithDashboardHeaders() = runTest {
        val transport = RoutingTransport()
        val provider = NewAPIUsageProvider(transport, fixedClock)

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("newapi-token"))

        assertTrue(result.isSuccess)
        assertEquals(7, transport.requests.size)
        transport.requests.forEach { request ->
            assertEquals("GET", request.method)
            assertEquals("Bearer newapi-token", request.headers["Authorization"])
            assertEquals("128", request.headers["New-Api-User"])
        }

        val paths = transport.requests.map { it.url.substringAfter("https://newapi.example.com/") }
        assertTrue(paths.contains("api/status"))
        assertTrue(paths.contains("api/user/self"))
        assertEquals(4, paths.count { it.startsWith("api/data/self?") })
        assertEquals(1, paths.count { it.startsWith("api/log/self/stat?") })
    }

    @Test
    fun fetchUsage_mapsQuotaMetricsWithDisplayCurrency() = runTest {
        val provider = NewAPIUsageProvider(RoutingTransport(), fixedClock)

        val snapshot = provider.fetchUsage(credential(), CredentialSecret.BearerToken("token"))
            .getOrThrow()

        assertEquals(fixedClock.instant(), snapshot.fetchedAt)
        assertEquals(12, snapshot.metrics.size)

        val quota = snapshot.metrics.single { it.id == "quota-progress" }
        assertEquals("账户额度", quota.label)
        assertEquals(0, quota.used!!.compareTo(BigDecimal("3.5")))
        assertEquals(0, quota.limit!!.compareTo(BigDecimal("14")))
        assertEquals(0, quota.remaining!!.compareTo(BigDecimal("10.5")))
        assertEquals("¥", quota.currencyCode)
        assertEquals(UsageMetricUnit.Currency, quota.unit)
        assertEquals(UsageMetricPresentation.Progress, quota.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, quota.semantic)

        val today = snapshot.metrics.single { it.id == "today-token" }
        assertEquals(0, today.value!!.compareTo(BigDecimal("12")))
        assertEquals(UsageMetricUnit.Token, today.unit)

        val cost = snapshot.metrics.single { it.id == "today-token-cost" }
        assertEquals(0, cost.value!!.compareTo(BigDecimal("1.4")))
        assertEquals("¥", cost.currencyCode)

        val rpm = snapshot.metrics.single { it.id == "rpm" }
        assertEquals(0, rpm.value!!.compareTo(BigDecimal("3")))
        assertEquals(UsageMetricUnit.Request, rpm.unit)
    }

    @Test
    fun fetchUsage_supportsBaseURLThatAlreadyEndsWithApi() = runTest {
        val transport = RoutingTransport()
        val provider = NewAPIUsageProvider(transport, fixedClock)

        val result = provider.fetchUsage(
            credential(baseURL = "https://newapi.example.com/api"),
            CredentialSecret.BearerToken("token"),
        )

        assertTrue(result.isSuccess)
        assertTrue(transport.requests.any { it.url == "https://newapi.example.com/api/status" })
    }

    @Test
    fun fetchUsage_mapsProviderErrorMessage() = runTest {
        val transport = HttpTransport { request ->
            ProviderHttpResponse(
                200,
                """{"success":false,"message":"无权进行此操作，未登录且未提供 access token"}""".toByteArray(),
            )
        }
        val provider = NewAPIUsageProvider(transport, fixedClock)

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("token"))

        assertTrue(result.isFailure)
        val error = result.exceptionOrNull() as UsageProviderException.ProviderMessage
        assertTrue(error.message!!.contains("无权进行此操作"))
    }

    @Test
    fun fetchUsage_rejectsIncompleteCredentialWithoutNetworkCall() = runTest {
        val transport = RoutingTransport()
        val provider = NewAPIUsageProvider(transport, fixedClock)

        val result = provider.fetchUsage(
            credential().copy(metadata = mapOf(CredentialMetadataKey.BaseURL to "https://newapi.example.com")),
            CredentialSecret.BearerToken("token"),
        )

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidCredential)
        assertTrue(transport.requests.isEmpty())
    }
}
