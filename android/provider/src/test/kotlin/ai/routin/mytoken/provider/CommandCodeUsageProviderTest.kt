package ai.routin.mytoken.provider

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.usage.UsageProviderException
import ai.routin.mytoken.provider.commandcode.CommandCodeUsageProvider
import ai.routin.mytoken.provider.http.HttpTransport
import ai.routin.mytoken.provider.http.ProviderHttpRequest
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class CommandCodeUsageProviderTest {
    private val fixedClock = Clock.fixed(Instant.parse("2026-09-10T12:00:00Z"), ZoneOffset.UTC)

    private class RoutingTransport : HttpTransport {
        val requests = mutableListOf<ProviderHttpRequest>()

        override suspend fun execute(request: ProviderHttpRequest): ProviderHttpResponse {
            requests += request
            val body = when (request.url.substringBefore("?")) {
                "https://api.commandcode.ai/alpha/whoami" ->
                    """{"success":true,"org":null,"user":{"id":"u1","userName":"alice"}}"""
                "https://api.commandcode.ai/alpha/billing/credits" ->
                    """{"credits":{"planId":"individual-goat","monthlyCredits":42,"purchasedCredits":10,"freeCredits":3},"windowLimits":{"limited":true,"fiveHour":{"used":7,"cap":14,"resetAt":1789046400000},"weekly":{"used":25,"cap":35,"resetAt":1789646400000}}}"""
                "https://api.commandcode.ai/alpha/billing/subscriptions" ->
                    """{"data":{"planId":"individual-goat","status":"active","currentPeriodStart":"2026-09-01T00:00:00Z","currentPeriodEnd":"2026-10-01T00:00:00Z"}}"""
                "https://api.commandcode.ai/alpha/usage/summary" ->
                    """{"totalCost":25.5,"totalCount":123}"""
                "https://api.commandcode.ai/provider/v1/models" ->
                    """{"object":"list","data":[{"id":"claude-sonnet-5"},{"id":"deepseek-v4-flash"}]}"""
                else -> error("unexpected url: ${request.url}")
            }
            return ProviderHttpResponse(200, body.toByteArray())
        }
    }

    private fun credential() = Credential(
        id = UUID.fromString("11111111-1111-4111-8111-111111111111"),
        providerId = ProviderId.CommandCode,
        credentialKind = CredentialKind.BearerApiKey,
        name = "Command Code",
    )

    @Test
    fun fetchUsageMapsPersonalAccountUsageAndModels() = runTest {
        val transport = RoutingTransport()
        val provider = CommandCodeUsageProvider(transport, fixedClock)

        val snapshot = provider.fetchUsage(
            credential(),
            CredentialSecret.BearerToken("cmd-token"),
        ).getOrThrow()

        assertEquals("GOAT", snapshot.planName)
        assertEquals("有效", snapshot.statusText)
        assertEquals("active", snapshot.billingMode)
        assertEquals(Instant.parse("2026-09-01T00:00:00Z"), snapshot.subscriptionStartAt)
        assertEquals(Instant.parse("2026-10-01T00:00:00Z"), snapshot.subscriptionEndAt)
        assertEquals(listOf("claude-sonnet-5", "deepseek-v4-flash"), snapshot.allowedModels)
        assertEquals(
            listOf(
                "credit-progress",
                "credit-balance",
                "monthly-remaining",
                "purchased-remaining",
                "free-remaining",
                "period-spent",
                "request-count",
                "five-hour",
                "weekly",
            ),
            snapshot.metrics.map { it.id },
        )

        val monthly = snapshot.metrics.single { it.id == "credit-progress" }
        assertEquals("月", monthly.label)
        assertEquals(0, monthly.used!!.compareTo(BigDecimal("28")))
        assertEquals(0, monthly.limit!!.compareTo(BigDecimal("83")))
        assertEquals(0, monthly.remaining!!.compareTo(BigDecimal("55")))
        assertEquals(UsageMetricUnit.Currency, monthly.unit)
        assertEquals(UsageMetricPresentation.Progress, monthly.presentation)
        assertEquals(UsageMetricSemantic.UsedQuota, monthly.semantic)

        val fiveHour = snapshot.metrics.single { it.id == "five-hour" }
        assertEquals(0, fiveHour.used!!.compareTo(BigDecimal("7")))
        assertEquals(0, fiveHour.limit!!.compareTo(BigDecimal("14")))
        assertEquals(UsageMetricHealthState.Normal, fiveHour.healthState)

        transport.requests.filter { it.url.contains("/alpha/") }.forEach { request ->
            assertFalse(request.url.contains("orgId="))
            assertEquals("Bearer cmd-token", request.headers["Authorization"])
        }
        assertEquals(
            "https://api.commandcode.ai/provider/v1/models",
            transport.requests.last().url,
        )
    }

    @Test
    fun fetchUsageMapsUnauthorized() = runTest {
        val transport = HttpTransport { ProviderHttpResponse(401, ByteArray(0)) }
        val provider = CommandCodeUsageProvider(transport, fixedClock)

        val result = provider.fetchUsage(credential(), CredentialSecret.BearerToken("bad"))

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is UsageProviderException.Unauthorized)
    }
}
