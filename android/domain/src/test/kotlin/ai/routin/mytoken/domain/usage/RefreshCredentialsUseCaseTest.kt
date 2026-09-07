package ai.routin.mytoken.domain.usage

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.repository.CredentialRepository
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class RefreshCredentialsUseCaseTest {

    private class FakeCredentialRepository(
        credentials: List<Credential>,
        private val secrets: Map<UUID, CredentialSecret> = emptyMap(),
    ) : CredentialRepository {
        private val flow = MutableStateFlow(credentials)
        override fun observeCredentials(): Flow<List<Credential>> = flow
        override suspend fun save(credential: Credential, secret: CredentialSecret) = Unit
        override suspend fun delete(id: UUID) = Unit
        override suspend fun readSecret(id: UUID): CredentialSecret? = secrets[id]
    }

    private class FakeProvider(
        override val providerId: ProviderId,
        private val delayMs: Long = 0,
        private val behavior: suspend (Credential) -> Result<UsageSnapshot>,
    ) : UsageProvider {
        val calls = AtomicInteger(0)
        private val active = AtomicInteger(0)
        val maxActive = AtomicInteger(0)

        override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
            calls.incrementAndGet()
            val current = active.incrementAndGet()
            maxActive.updateAndGet { old -> maxOf(old, current) }
            try {
                if (delayMs > 0) delay(delayMs)
                return behavior(credential)
            } finally {
                active.decrementAndGet()
            }
        }
    }

    private fun snapshot(credentialId: UUID, used: Int = 1): UsageSnapshot = UsageSnapshot(
        credentialId = credentialId,
        fetchedAt = Instant.parse("2026-09-07T04:00:00Z"),
        metrics = listOf(
            UsageMetric(
                id = "fiveHour",
                label = "5 小时",
                used = used.toBigDecimal(),
                limit = 100.toBigDecimal(),
                remaining = (100 - used).toBigDecimal(),
                unit = UsageMetricUnit.Currency,
                presentation = UsageMetricPresentation.Progress,
                semantic = UsageMetricSemantic.UsedQuota
            )
        )
    )

    private fun credential(id: String, providerId: ProviderId, enabled: Boolean = true) = Credential(
        id = UUID.fromString(id),
        providerId = providerId,
        credentialKind = CredentialKind.BearerApiKey,
        name = "示例",
        isEnabled = enabled
    )

    @Test
    fun refreshAll_marksReadyOnSuccess() = runTest {
        val cred = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val secret = CredentialSecret.BearerToken("token")
        val provider = FakeProvider(ProviderId.Routin) { Result.success(snapshot(cred.id)) }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(cred), mapOf(cred.id to secret)),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        useCase.refreshAll()

        val state = useCase.states.value.getValue(cred.id)
        assertEquals(RefreshStatus.Ready, state.status)
        assertEquals(1, state.snapshot!!.metrics.size)
        assertFalse(state.isStale)
        assertNull(state.error)
        assertEquals(1, provider.calls.get())
    }

    @Test
    fun refreshAll_marksDisabledCredentialsWithoutFetching() = runTest {
        val enabled = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val disabled = credential("22222222-2222-4222-8222-222222222222", ProviderId.DeepSeek, enabled = false)
        val provider = FakeProvider(ProviderId.Routin) { Result.success(snapshot(enabled.id)) }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(
                listOf(enabled, disabled),
                mapOf(enabled.id to CredentialSecret.BearerToken("t"))
            ),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        useCase.refreshAll()

        assertEquals(RefreshStatus.Ready, useCase.states.value.getValue(enabled.id).status)
        assertEquals(RefreshStatus.Disabled, useCase.states.value.getValue(disabled.id).status)
        assertEquals(1, provider.calls.get())
    }

    @Test
    fun refreshAll_failureKeepsLastSuccessAndMarksStale() = runTest {
        val cred = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val secret = CredentialSecret.BearerToken("token")
        var succeed = true
        val provider = FakeProvider(ProviderId.Routin) {
            if (succeed) Result.success(snapshot(cred.id)) else Result.failure(
                UsageProviderException.Unauthorized()
            )
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(cred), mapOf(cred.id to secret)),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        useCase.refreshAll()
        succeed = false
        useCase.refreshAll()

        val state = useCase.states.value.getValue(cred.id)
        assertEquals(RefreshStatus.Failed, state.status)
        assertNotNull(state.snapshot)
        assertEquals(1, state.snapshot!!.metrics.size)
        assertTrue(state.isStale)
        assertTrue(state.error is AppError.Authentication)
    }

    @Test
    fun refreshAll_failureWithoutPreviousSnapshotHasNoSnapshot() = runTest {
        val cred = credential("11111111-1111-4111-8111-111111111111", ProviderId.Glm)
        val secret = CredentialSecret.ApiKey("key")
        val provider = FakeProvider(ProviderId.Glm) {
            Result.failure(UsageProviderException.RateLimited())
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(cred), mapOf(cred.id to secret)),
            providers = mapOf(ProviderId.Glm to provider),
            maxConcurrency = 2
        )

        useCase.refreshAll()

        val state = useCase.states.value.getValue(cred.id)
        assertEquals(RefreshStatus.Failed, state.status)
        assertNull(state.snapshot)
        assertFalse(state.isStale)
        assertTrue(state.error is AppError.Network)
    }

    @Test
    fun refreshAll_tracksPerCredentialStatesIndependently() = runTest {
        val ok = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val failing = credential("22222222-2222-4222-8222-222222222222", ProviderId.DeepSeek)
        val secrets = mapOf(
            ok.id to CredentialSecret.BearerToken("t"),
            failing.id to CredentialSecret.ApiKey("k")
        )
        val routin = FakeProvider(ProviderId.Routin) { Result.success(snapshot(ok.id)) }
        val deepseek = FakeProvider(ProviderId.DeepSeek) {
            Result.failure(UsageProviderException.InvalidResponse())
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(ok, failing), secrets),
            providers = mapOf(ProviderId.Routin to routin, ProviderId.DeepSeek to deepseek),
            maxConcurrency = 4
        )

        useCase.refreshAll()

        assertEquals(RefreshStatus.Ready, useCase.states.value.getValue(ok.id).status)
        assertEquals(RefreshStatus.Failed, useCase.states.value.getValue(failing.id).status)
        assertTrue(useCase.states.value.getValue(failing.id).error is AppError.Decode)
    }

    @Test
    fun refreshAll_limitsConcurrentFetches() = runTest {
        val credentials = (0 until 6).map { index ->
            credential(
                "0000000%d-1111-4111-8111-11111111111%d".format(index, index),
                ProviderId.Routin
            )
        }
        val secrets = credentials.associate { it.id to CredentialSecret.BearerToken("t") }
        val provider = FakeProvider(ProviderId.Routin, delayMs = 1_000) {
            Result.success(snapshot(it.id))
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(credentials, secrets),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        useCase.refreshAll()

        assertEquals(2, provider.maxActive.get())
        assertEquals(6, provider.calls.get())
    }

    @Test
    fun refreshAll_doesNotFabricateValuesForUnsupportedMetrics() = runTest {
        val cred = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val secret = CredentialSecret.BearerToken("token")
        val emptySnapshot = snapshot(cred.id).copy(metrics = emptyList())
        val provider = FakeProvider(ProviderId.Routin) { Result.success(emptySnapshot) }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(cred), mapOf(cred.id to secret)),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        useCase.refreshAll()

        val state = useCase.states.value.getValue(cred.id)
        assertEquals(RefreshStatus.Ready, state.status)
        assertTrue(state.snapshot!!.metrics.isEmpty())
    }

    @Test
    fun refreshAll_mapsMissingSecretAndUnknownProviderToErrors() = runTest {
        val noSecret = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val noProvider = credential("22222222-2222-4222-8222-222222222222", ProviderId.NewAPI)
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(noSecret, noProvider)),
            providers = mapOf(ProviderId.Routin to FakeProvider(ProviderId.Routin) {
                Result.success(snapshot(noSecret.id))
            }),
            maxConcurrency = 2
        )

        useCase.refreshAll()

        val noSecretState = useCase.states.value.getValue(noSecret.id)
        assertEquals(RefreshStatus.Failed, noSecretState.status)
        assertTrue(noSecretState.error is AppError.Storage)
        val noProviderState = useCase.states.value.getValue(noProvider.id)
        assertEquals(RefreshStatus.Failed, noProviderState.status)
        assertTrue(noProviderState.error is AppError.Unknown)
    }

    @Test
    fun refresh_cancellationFromProviderPropagatesAndDoesNotMarkFailed() = runTest {
        val cred = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val secret = CredentialSecret.BearerToken("token")
        val provider = FakeProvider(ProviderId.Routin) {
            throw CancellationException("refresh cancelled")
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(cred), mapOf(cred.id to secret)),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        assertFailsWith<CancellationException> {
            useCase.refresh(cred)
        }

        val state = useCase.states.value.getValue(cred.id)
        assertEquals(RefreshStatus.Loading, state.status)
        assertNull(state.error)
    }

    @Test
    fun refresh_cancellationMidFetchPropagatesAndDoesNotMarkFailed() = runTest {
        val cred = credential("11111111-1111-4111-8111-111111111111", ProviderId.Routin)
        val secret = CredentialSecret.BearerToken("token")
        val provider = FakeProvider(ProviderId.Routin, delayMs = 1_000_000) {
            Result.success(snapshot(cred.id))
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(listOf(cred), mapOf(cred.id to secret)),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = 2
        )

        val job = launch { useCase.refresh(cred) }
        runCurrent()
        job.cancelAndJoin()

        val state = useCase.states.value.getValue(cred.id)
        assertEquals(RefreshStatus.Loading, state.status)
        assertNull(state.error)
    }

    /**
     * Lost-update regression: releases [maxConcurrency] fetches simultaneously on real
     * worker threads (Dispatchers.Default) so their Ready-state writes collide. With the
     * non-atomic read-modify-write `update()`, whole credentials could stay stuck in
     * Loading after a wave; with the atomic `MutableStateFlow.update {}` CAS loop, every
     * credential must end Ready. Repeated rounds make any lost update surface reliably.
     */
    @Test
    fun refreshAll_concurrentStateUpdatesDoNotLoseCredentials() {
        val credentials = (0 until 32).map { index ->
            credential(
                "%08d-1111-4111-8111-111111111111".format(index),
                ProviderId.Routin
            )
        }
        val secrets = credentials.associate { it.id to CredentialSecret.BearerToken("t") }
        val maxConcurrency = 8
        val inFlight = AtomicInteger(0)
        var release = CompletableDeferred<Unit>()
        val provider = FakeProvider(ProviderId.Routin) { cred ->
            if (inFlight.incrementAndGet() >= maxConcurrency) {
                release.complete(Unit)
            }
            release.await()
            Result.success(snapshot(cred.id))
        }
        val useCase = RefreshCredentialsUseCase(
            repository = FakeCredentialRepository(credentials, secrets),
            providers = mapOf(ProviderId.Routin to provider),
            maxConcurrency = maxConcurrency
        )

        runBlocking {
            withContext(Dispatchers.Default) {
                repeat(20) {
                    release = CompletableDeferred()
                    inFlight.set(0)
                    useCase.refreshAll()
                }
            }
        }

        val nonReady = useCase.states.value.filterValues { it.status != RefreshStatus.Ready }
        assertTrue(
            nonReady.isEmpty(),
            "credentials stuck in non-Ready state after concurrent refresh: $nonReady"
        )
    }
}
