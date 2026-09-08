package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.repository.CredentialRepository
import ai.routin.mytoken.domain.usage.RefreshCredentialsUseCase
import ai.routin.mytoken.domain.usage.RefreshStatus
import ai.routin.mytoken.domain.usage.UsageProvider
import java.math.BigDecimal
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val now = Instant.parse("2026-09-07T12:00:00Z")
    private val clock = Clock.fixed(now, ZoneOffset.UTC)

    private lateinit var repository: FakeHomeCredentialRepository
    private lateinit var providers: MutableMap<ProviderId, UsageProvider>

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = FakeHomeCredentialRepository()
        providers = mutableMapOf()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel(
        refreshOnStart: Boolean = false,
        credentialOrderIds: Flow<List<String>> = MutableStateFlow(emptyList()),
    ) = HomeViewModel(
        repository = repository,
        refreshUseCase = RefreshCredentialsUseCase(repository, providers, clock),
        credentialOrderIds = credentialOrderIds,
        clock = clock,
        refreshOnStart = refreshOnStart,
        nowTickIntervalMillis = null,
    )

    private fun credential(
        name: String,
        provider: ProviderId,
        sortOrder: Int = 0,
        enabled: Boolean = true,
    ) = Credential(
        id = UUID.randomUUID(),
        providerId = provider,
        credentialKind = CredentialKind.ApiKey,
        name = name,
        isEnabled = enabled,
        sortOrder = sortOrder,
    )

    private fun addCredential(credential: Credential) {
        repository.credentials[credential.id] = credential
        repository.secrets[credential.id] = CredentialSecret.ApiKey("test-key")
        repository.emit()
    }

    private fun progressMetric(
        id: String,
        label: String,
        used: Double,
        limit: Double,
        remaining: Double? = null,
    ) = UsageMetric(
        id = id,
        label = label,
        used = BigDecimal.valueOf(used),
        limit = BigDecimal.valueOf(limit),
        remaining = remaining?.let { BigDecimal.valueOf(it) },
        unit = UsageMetricUnit.Token,
        presentation = UsageMetricPresentation.Progress,
        semantic = UsageMetricSemantic.UsedQuota,
        healthState = UsageMetricHealthState.Unknown,
    )

    private fun balanceMetric(value: Double) = UsageMetric(
        id = "balance",
        label = "余额",
        value = BigDecimal.valueOf(value),
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Balance,
        semantic = UsageMetricSemantic.Balance,
        currencyCode = "CNY",
        healthState = UsageMetricHealthState.Normal,
    )

    private fun snapshot(credentialId: UUID, vararg metrics: UsageMetric) =
        UsageSnapshot(credentialId, now, metrics.toList())

    @Test
    fun `now tick advances periodically pauses when disabled and resumes`() = runTest {
        val vm = HomeViewModel(
            repository = repository,
            refreshUseCase = RefreshCredentialsUseCase(repository, providers, clock),
            clock = clock,
            refreshOnStart = false,
            nowTickIntervalMillis = 30_000,
            nowTickDispatcher = StandardTestDispatcher(testScheduler),
        )
        backgroundScope.launch { vm.state.collect {} }

        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(1, vm.nowTick.value)

        vm.setNowTickEnabled(false)
        advanceTimeBy(90_000)
        runCurrent()
        assertEquals("paused ticker must not advance", 1, vm.nowTick.value)

        vm.setNowTickEnabled(true)
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(2, vm.nowTick.value)

        // The tick loop lives in viewModelScope (not a child of TestScope);
        // cancel it so runTest's quiescence check can terminate.
        vm.viewModelScope.cancel()
        advanceUntilIdle()
    }

    @Test
    fun `groups credentials by provider in provider order`() = runTest {
        addCredential(credential("DS-1", ProviderId.DeepSeek))
        addCredential(credential("GLM-1", ProviderId.Glm))
        addCredential(credential("RT-1", ProviderId.Routin))
        addCredential(credential("RT-2", ProviderId.Routin, sortOrder = 1))

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        advanceUntilIdle()

        val state = vm.state.value
        assertFalse(state.isLoading)
        assertEquals(3, state.groups.size)
        assertEquals(
            listOf(ProviderId.Routin, ProviderId.DeepSeek, ProviderId.Glm),
            state.groups.map { it.providerId },
        )
        assertEquals(listOf("RT-1", "RT-2"), state.groups[0].cards.map { it.credential.name })
        assertEquals(4, state.credentialCount)
    }

    @Test
    fun `home cards follow global credential order`() = runTest {
        addCredential(credential("DS", ProviderId.DeepSeek, sortOrder = 0))
        addCredential(credential("RT", ProviderId.Routin, sortOrder = 1))
        addCredential(credential("GLM", ProviderId.Glm, sortOrder = 2))

        val orderFlow = MutableStateFlow(
            listOf("RT", "GLM", "DS").mapNotNull { raw ->
                repository.credentials.values.firstOrNull { it.name == raw }?.id.toString()
            },
        )
        val vm = viewModel(credentialOrderIds = orderFlow)
        backgroundScope.launch { vm.state.collect {} }
        advanceUntilIdle()

        assertEquals(
            listOf("RT", "GLM", "DS"),
            vm.state.value.cards.map { it.credential.name },
        )
    }

    @Test
    fun `refreshAll populates ready cards with snapshots`() = runTest {
        val credential = credential("RT-1", ProviderId.Routin)
        addCredential(credential)
        providers[ProviderId.Routin] = FakeUsageProvider(
            ProviderId.Routin,
            Result.success(snapshot(credential.id, progressMetric("fiveHour", "5 小时", 4.2, 10.0, 5.8))),
        )

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()

        val card = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Ready, card.status)
        assertNotNull(card.snapshot)
        assertFalse(card.isStale)
        assertNull(card.error)
        assertEquals("刚刚更新", card.freshness.text)
    }

    @Test
    fun `failed refresh keeps last snapshot and marks stale`() = runTest {
        val credential = credential("RT-1", ProviderId.Routin)
        addCredential(credential)
        val fake = FakeUsageProvider(ProviderId.Routin, Result.success(snapshot(credential.id, balanceMetric(20.0))))
        providers[ProviderId.Routin] = fake

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()

        fake.next = Result.failure(AppError.Authentication("凭证无效"))
        vm.refreshAll()
        advanceUntilIdle()

        val card = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Failed, card.status)
        assertNotNull(card.snapshot)
        assertTrue(card.isStale)
        assertEquals("凭证无效", card.error?.message)
        assertEquals("数据已过期", card.freshness.text)
    }

    @Test
    fun `failed refresh without snapshot shows error without freshness`() = runTest {
        val credential = credential("DS-1", ProviderId.DeepSeek)
        addCredential(credential)
        providers[ProviderId.DeepSeek] = FakeUsageProvider(
            ProviderId.DeepSeek,
            Result.failure(AppError.Network("网络连接失败")),
        )

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()

        val card = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Failed, card.status)
        assertNull(card.snapshot)
        assertTrue(card.isStale.not())
        assertEquals("网络连接失败", card.error?.message)
        assertEquals("从未刷新", card.freshness.text)
    }

    @Test
    fun `disabled credential reports disabled state`() = runTest {
        addCredential(credential("OFF", ProviderId.Glm, enabled = false))

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()

        val card = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Disabled, card.status)
    }

    @Test
    fun `refreshOnStart triggers initial refresh`() = runTest {
        val credential = credential("RT-1", ProviderId.Routin)
        addCredential(credential)
        val fake = FakeUsageProvider(ProviderId.Routin, Result.success(snapshot(credential.id, balanceMetric(1.0))))
        providers[ProviderId.Routin] = fake

        val vm = viewModel(refreshOnStart = true)
        backgroundScope.launch { vm.state.collect {} }
        advanceUntilIdle()

        assertEquals(1, fake.fetchCalls)
        assertEquals(RefreshStatus.Ready, vm.state.value.groups.single().cards.single().status)
    }

    @Test
    fun `startup seeds cached snapshot so card shows data instead of an empty refreshing placeholder`() = runTest {
        val credential = credential("RT-1", ProviderId.Routin)
        addCredential(credential)
        val cached = UsageSnapshot(credential.id, now.minus(Duration.ofHours(3)), listOf(balanceMetric(20.0)))
        repository.cachedSnapshots[credential.id] = cached
        // The startup refresh is gated mid-flight: the seeded snapshot must stay
        // visible on the card while the network round trip is pending.
        val gate = CompletableDeferred<Unit>()
        providers[ProviderId.Routin] = GatedUsageProvider(ProviderId.Routin, gate, now)

        val vm = viewModel(refreshOnStart = true)
        backgroundScope.launch { vm.state.collect {} }
        advanceUntilIdle()

        val card = vm.state.value.groups.single().cards.single()
        assertEquals(cached, card.snapshot)
        assertTrue(card.isStale)

        gate.complete(Unit)
        advanceUntilIdle()
        val refreshedCard = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Ready, refreshedCard.status)
        assertFalse(refreshedCard.isStale)
    }

    @Test
    fun `toggleGroup collapses and expands section`() = runTest {
        addCredential(credential("RT-1", ProviderId.Routin))

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        advanceUntilIdle()

        assertFalse(vm.state.value.groups.single().isCollapsed)
        vm.toggleGroup(ProviderId.Routin)
        advanceUntilIdle()
        assertTrue(vm.state.value.groups.single().isCollapsed)
        vm.toggleGroup(ProviderId.Routin)
        advanceUntilIdle()
        assertFalse(vm.state.value.groups.single().isCollapsed)
    }

    @Test
    fun `lastUpdatedAt is max snapshot time across credentials`() = runTest {
        val older = credential("RT-1", ProviderId.Routin)
        val newer = credential("DS-1", ProviderId.DeepSeek)
        addCredential(older)
        addCredential(newer)
        providers[ProviderId.Routin] = FakeUsageProvider(
            ProviderId.Routin,
            Result.success(UsageSnapshot(older.id, now.minus(Duration.ofHours(2)), emptyList())),
        )
        providers[ProviderId.DeepSeek] = FakeUsageProvider(
            ProviderId.DeepSeek,
            Result.success(UsageSnapshot(newer.id, now.minus(Duration.ofMinutes(5)), emptyList())),
        )

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()

        assertEquals(now.minus(Duration.ofMinutes(5)), vm.state.value.lastUpdatedAt)
        assertEquals("5分钟前更新", vm.state.value.lastUpdatedText)
    }

    @Test
    fun `empty repository yields empty groups`() = runTest {
        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        advanceUntilIdle()

        val state = vm.state.value
        assertFalse(state.isLoading)
        assertEquals(0, state.groups.size)
        assertEquals(0, state.credentialCount)
    }

    @Test
    fun `freshness formatter distinguishes never just now recent old expired`() {
        fun at(offset: Duration) = FreshnessFormatter.of(now.minus(offset), now)

        assertEquals(FreshnessLevel.NEVER, FreshnessFormatter.of(null, now).level)
        assertEquals("从未刷新", FreshnessFormatter.of(null, now).text)
        assertEquals(FreshnessLevel.JUST_NOW, at(Duration.ofSeconds(30)).level)
        assertEquals("刚刚更新", at(Duration.ofSeconds(90)).text)
        assertEquals(FreshnessLevel.RECENT, at(Duration.ofMinutes(5)).level)
        assertEquals("5分钟前更新", at(Duration.ofMinutes(5)).text)
        assertEquals(FreshnessLevel.OLD, at(Duration.ofHours(3)).level)
        assertEquals("3小时前更新", at(Duration.ofHours(3)).text)
        assertEquals(FreshnessLevel.EXPIRED, at(Duration.ofHours(30)).level)
        assertEquals("数据已过期", at(Duration.ofHours(30)).text)
    }

    @Test
    fun `refreshAll twice concurrently issues one fetch per credential`() = runTest {
        val rt = credential("RT-1", ProviderId.Routin)
        val ds = credential("DS-1", ProviderId.DeepSeek)
        addCredential(rt)
        addCredential(ds)
        val gate = CompletableDeferred<Unit>()
        val rtProvider = GatedUsageProvider(ProviderId.Routin, gate, now)
        val dsProvider = GatedUsageProvider(ProviderId.DeepSeek, gate, now)
        providers[ProviderId.Routin] = rtProvider
        providers[ProviderId.DeepSeek] = dsProvider

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }

        vm.refreshAll()
        vm.refreshAll() // duplicate while the first pass is still in flight
        advanceUntilIdle()

        assertEquals("duplicate refreshAll must not re-fetch Routin", 1, rtProvider.fetchCalls)
        assertEquals("duplicate refreshAll must not re-fetch DeepSeek", 1, dsProvider.fetchCalls)

        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals(1, rtProvider.fetchCalls)
        assertEquals(1, dsProvider.fetchCalls)
        vm.state.value.groups.forEach { group ->
            group.cards.forEach { card ->
                assertEquals(RefreshStatus.Ready, card.status)
            }
        }
    }

    @Test
    fun `duplicate single-credential refresh issues one fetch`() = runTest {
        val rt = credential("RT-1", ProviderId.Routin)
        addCredential(rt)
        val gate = CompletableDeferred<Unit>()
        val provider = GatedUsageProvider(ProviderId.Routin, gate, now)
        providers[ProviderId.Routin] = provider

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }

        vm.refreshCredential(rt)
        vm.refreshCredential(rt) // duplicate retry while first is still in flight
        advanceUntilIdle()

        assertEquals(1, provider.fetchCalls)

        gate.complete(Unit)
        advanceUntilIdle()

        assertEquals(1, provider.fetchCalls)
        assertEquals(RefreshStatus.Ready, vm.state.value.groups.single().cards.single().status)
    }

    @Test
    fun `refreshAll while single refresh in flight skips that credential and refreshes others`() = runTest {
        val rt = credential("RT-1", ProviderId.Routin)
        val ds = credential("DS-1", ProviderId.DeepSeek)
        addCredential(rt)
        addCredential(ds)
        val gate = CompletableDeferred<Unit>()
        val rtProvider = GatedUsageProvider(ProviderId.Routin, gate, now)
        val dsProvider = GatedUsageProvider(
            ProviderId.DeepSeek,
            CompletableDeferred<Unit>().apply { complete(Unit) },
            now,
        )
        providers[ProviderId.Routin] = rtProvider
        providers[ProviderId.DeepSeek] = dsProvider

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }

        vm.refreshCredential(rt)
        advanceUntilIdle() // rt suspended mid-refresh
        vm.refreshAll()
        advanceUntilIdle()

        assertEquals("in-flight single refresh must not be duplicated", 1, rtProvider.fetchCalls)
        assertEquals(1, dsProvider.fetchCalls)
        val cards = vm.state.value.groups.flatMap { it.cards }
        assertEquals(
            RefreshStatus.Loading,
            cards.single { it.credential.id == rt.id }.status,
        )
        assertEquals(
            RefreshStatus.Ready,
            cards.single { it.credential.id == ds.id }.status,
        )

        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, rtProvider.fetchCalls)
    }

    @Test
    fun `refresh left loading by cancellation keeps snapshot without error`() = runTest {
        val credential = credential("RT-1", ProviderId.Routin)
        addCredential(credential)
        val gate = CompletableDeferred<Result<UsageSnapshot>>()
        var calls = 0
        providers[ProviderId.Routin] = object : UsageProvider {
            override val providerId = ProviderId.Routin
            override suspend fun fetchUsage(
                credential: Credential,
                secret: CredentialSecret,
            ): Result<UsageSnapshot> {
                calls++
                if (calls == 1) {
                    return Result.success(snapshot(credential.id, balanceMetric(20.0)))
                }
                // Suspending forever is the observable state of a refresh cancelled
                // mid-flight: Task 7 keeps the credential in Loading with no error.
                return gate.await()
            }
        }

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()
        assertEquals(RefreshStatus.Ready, vm.state.value.groups.single().cards.single().status)

        vm.refreshAll()
        advanceUntilIdle()

        // The collection stays alive here; assertions must hold on the live flow.
        val card = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Loading, card.status)
        assertNull("cancelled refresh must not surface an error", card.error)
        assertNotNull("previous successful snapshot is kept while refreshing", card.snapshot)
        assertEquals(2, calls)

        // Cleanup only: release/cancel after assertions, never before.
        vm.viewModelScope.cancel()
        advanceUntilIdle()
        assertEquals(RefreshStatus.Loading, vm.state.value.groups.single().cards.single().status)
        assertNull(vm.state.value.groups.single().cards.single().error)
    }
}

/** In-memory credential repository for home tests. */
class FakeHomeCredentialRepository : CredentialRepository {
    val credentials = LinkedHashMap<UUID, Credential>()
    val secrets = LinkedHashMap<UUID, CredentialSecret>()
    val cachedSnapshots = LinkedHashMap<UUID, UsageSnapshot>()
    private val flow = MutableStateFlow<List<Credential>>(emptyList())

    fun emit() {
        flow.value = credentials.values.toList()
    }

    override fun observeCredentials(): Flow<List<Credential>> = flow

    override suspend fun save(credential: Credential, secret: CredentialSecret) = throw UnsupportedOperationException()

    override suspend fun delete(id: UUID) = throw UnsupportedOperationException()

    override suspend fun readSecret(id: UUID): CredentialSecret? = secrets[id]

    override suspend fun cacheSnapshot(snapshot: UsageSnapshot) {
        cachedSnapshots[snapshot.credentialId] = snapshot
    }

    override suspend fun cachedSnapshot(id: UUID): UsageSnapshot? = cachedSnapshots[id]
}

/** Usage provider fake returning a fixed result, with failure injection. */
class FakeUsageProvider(
    override val providerId: ProviderId,
    var next: Result<UsageSnapshot>,
) : UsageProvider {
    var fetchCalls = 0

    constructor(providerId: ProviderId, snapshot: UsageSnapshot) : this(providerId, Result.success(snapshot))

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        fetchCalls++
        return next
    }
}

/**
 * Usage provider that counts fetches and suspends every caller until [gate] is completed,
 * so concurrent duplicate requests are observable as an inflated [fetchCalls].
 */
class GatedUsageProvider(
    override val providerId: ProviderId,
    private val gate: CompletableDeferred<Unit>,
    private val fetchedAt: Instant,
) : UsageProvider {
    var fetchCalls = 0
        private set

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        fetchCalls++
        gate.await()
        return Result.success(UsageSnapshot(credential.id, fetchedAt, emptyList()))
    }
}
