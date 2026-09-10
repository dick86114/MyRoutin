package ai.routin.mytoken.provider

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.usage.UsageProviderException
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.deepseek.DeepSeekUsageProvider
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test

class DeepSeekUsageProviderTest {

    private val fixedClock: Clock = Clock.fixed(Instant.parse("2026-09-07T04:00:00Z"), ZoneOffset.UTC)
    private val transport = FakeHttpTransport()
    private val provider = DeepSeekUsageProvider(transport = transport, clock = fixedClock)
    private val secret = CredentialSecret.ApiKey("sk-deepseek-secret")

    private fun credential() = Credential(
        id = UUID.fromString("22222222-2222-4222-8222-222222222222"),
        providerId = ProviderId.DeepSeek,
        credentialKind = CredentialKind.ApiKey,
        name = "DeepSeek 示例"
    )

    private fun ok(body: String) = ProviderHttpResponse(200, body.toByteArray())

    private fun queueSuccess(modelsBody: String = """{"object":"list","data":[]}""") {
        transport.responses += ok(readFixture("usage/deepseek-balance.json"))
        transport.responses += ok(modelsBody)
    }

    @Test
    fun fetchUsage_sendsBearerGetRequest() = runTest {
        queueSuccess()

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.isSuccess)
        assertEquals(2, transport.requests.size)
        val request = transport.requests.first()
        assertEquals("GET", request.method)
        assertEquals("https://api.deepseek.com/user/balance", request.url)
        assertEquals("Bearer sk-deepseek-secret", request.headers["Authorization"])
        assertEquals("application/json", request.headers["Accept"])

        val models = transport.requests[1]
        assertEquals("https://api.deepseek.com/models", models.url)
        assertEquals("Bearer sk-deepseek-secret", models.headers["Authorization"])
    }

    @Test
    fun fetchUsage_mapsBalanceMetrics() = runTest {
        queueSuccess(
            """
            {"object":"list","data":[{"id":"deepseek-v4-flash"},{"id":"deepseek-v4-pro"},{"id":""}]}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertEquals(fixedClock.instant(), snapshot.fetchedAt)
        assertEquals(listOf("deepseek-v4-flash", "deepseek-v4-pro"), snapshot.allowedModels)
        assertEquals(listOf("balance", "grantedBalance", "toppedUpBalance", "availability"), snapshot.metrics.map { it.id })

        val balance = snapshot.metrics[0]
        assertEquals("余额", balance.label)
        assertEquals(0, balance.value!!.compareTo(BigDecimal("110.00")))
        assertEquals(UsageMetricUnit.Currency, balance.unit)
        assertEquals(UsageMetricPresentation.Balance, balance.presentation)
        assertEquals(UsageMetricSemantic.Balance, balance.semantic)
        assertEquals("CNY", balance.currencyCode)
        assertEquals(UsageMetricHealthState.Normal, balance.healthState)

        val granted = snapshot.metrics[1]
        assertEquals("赠金余额", granted.label)
        assertEquals(0, granted.value!!.compareTo(BigDecimal("10.00")))
        assertEquals(UsageMetricPresentation.Value, granted.presentation)
        assertEquals(UsageMetricSemantic.Value, granted.semantic)

        val toppedUp = snapshot.metrics[2]
        assertEquals("充值余额", toppedUp.label)
        assertEquals(0, toppedUp.value!!.compareTo(BigDecimal("100.00")))

        val availability = snapshot.metrics[3]
        assertEquals("账户状态", availability.label)
        assertEquals(0, availability.value!!.compareTo(BigDecimal.ONE))
        assertEquals(UsageMetricUnit.Boolean_, availability.unit)
        assertEquals(UsageMetricPresentation.Status, availability.presentation)
        assertEquals(UsageMetricSemantic.Status, availability.semantic)
        assertEquals(UsageMetricHealthState.Normal, availability.healthState)
    }

    @Test
    fun fetchUsage_keepsEmptyModelsWhenModelRequestFails() = runTest {
        transport.responses += ok(readFixture("usage/deepseek-balance.json"))
        transport.responses += ProviderHttpResponse(404, "{}".toByteArray())

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertTrue(snapshot.allowedModels.isEmpty())
        assertEquals(4, snapshot.metrics.size)
    }

    @Test
    fun fetchUsage_unavailableAccountMarksMetricsUnavailable() = runTest {
        transport.responses += ok(
            """
            {"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"110.00",
            "granted_balance":"10.00","topped_up_balance":"100.00"}]}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertEquals(UsageMetricHealthState.Unavailable, snapshot.metrics[0].healthState)
        assertEquals(UsageMetricHealthState.Unavailable, snapshot.metrics[3].healthState)
    }

    @Test
    fun fetchUsage_zeroBalanceMarksCritical() = runTest {
        transport.responses += ok(
            """
            {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"0",
            "granted_balance":"0","topped_up_balance":"0"}]}
            """.trimIndent()
        )

        val snapshot = provider.fetchUsage(credential(), secret).getOrThrow()

        assertEquals(UsageMetricHealthState.Critical, snapshot.metrics[0].healthState)
    }

    @Test
    fun fetchUsage_emptyBalanceInfosFailsWithInvalidResponse() = runTest {
        transport.responses += ok("""{"is_available":true,"balance_infos":[]}""")

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_malformedJsonFailsWithInvalidResponse() = runTest {
        transport.responses += ok("{ nope")

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_401And403MapToUnauthorized() = runTest {
        for (status in listOf(401, 403)) {
            val t = FakeHttpTransport()
            t.responses += ProviderHttpResponse(status, "{}".toByteArray())
            val result = DeepSeekUsageProvider(transport = t, clock = fixedClock).fetchUsage(credential(), secret)
            assertTrue(result.exceptionOrNull() is UsageProviderException.Unauthorized, "status=$status")
        }
    }

    @Test
    fun fetchUsage_429MapsToRateLimited() = runTest {
        transport.responses += ProviderHttpResponse(429, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.RateLimited)
    }

    @Test
    fun fetchUsage_5xxMapsToProviderUnavailable() = runTest {
        transport.responses += ProviderHttpResponse(500, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.ProviderUnavailable)
    }

    @Test
    fun fetchUsage_otherStatusMapsToInvalidResponse() = runTest {
        transport.responses += ProviderHttpResponse(404, "{}".toByteArray())

        val result = provider.fetchUsage(credential(), secret)

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidResponse)
    }

    @Test
    fun fetchUsage_errorsNeverContainTheSecret() = runTest {
        for (status in listOf(401, 403, 429, 500, 404)) {
            val t = FakeHttpTransport()
            t.responses += ProviderHttpResponse(status, "{}".toByteArray())
            val error = DeepSeekUsageProvider(transport = t, clock = fixedClock)
                .fetchUsage(credential(), secret)
                .exceptionOrNull()
            assertTrue(error!!.message?.contains(secret.key) != true)
        }
    }

    @Test
    fun fetchUsage_rejectsEmptySecretWithoutNetworkCall() = runTest {
        val result = provider.fetchUsage(credential(), CredentialSecret.ApiKey(""))

        assertTrue(result.exceptionOrNull() is UsageProviderException.InvalidCredential)
        assertTrue(transport.requests.isEmpty())
    }

    private fun readFixture(name: String): String =
        javaClass.classLoader!!.getResourceAsStream(name)!!.readBytes().decodeToString()
}
