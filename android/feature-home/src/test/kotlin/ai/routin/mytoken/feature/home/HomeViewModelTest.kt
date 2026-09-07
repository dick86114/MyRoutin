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
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
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

    private fun viewModel(refreshOnStart: Boolean = false) = HomeViewModel(
        repository = repository,
        refreshUseCase = RefreshCredentialsUseCase(repository, providers, clock),
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
    fun `cancelled refresh leaves loading state without error`() = runTest {
        val credential = credential("RT-1", ProviderId.Routin)
        addCredential(credential)
        val gate = CompletableDeferred<Result<UsageSnapshot>>()
        providers[ProviderId.Routin] = object : UsageProvider {
            override val providerId = ProviderId.Routin
            override suspend fun fetchUsage(
                credential: Credential,
                secret: CredentialSecret,
            ): Result<UsageSnapshot> = gate.await()
        }

        val vm = viewModel()
        backgroundScope.launch { vm.state.collect {} }
        vm.refreshAll()
        advanceUntilIdle()
        assertEquals(RefreshStatus.Loading, vm.state.value.groups.single().cards.single().status)

        // Task 7 semantics: cancellation is not a failure. The card stays Loading (展示"刷新中")
        // and can be retried by the user, instead of rendering an error.
        vm.viewModelScope.cancel()
        advanceUntilIdle()

        val card = vm.state.value.groups.single().cards.single()
        assertEquals(RefreshStatus.Loading, card.status)
        assertNull(card.error)
    }
}

/** In-memory credential repository for home tests. */
class FakeHomeCredentialRepository : CredentialRepository {
    val credentials = LinkedHashMap<UUID, Credential>()
    val secrets = LinkedHashMap<UUID, CredentialSecret>()
    private val flow = MutableStateFlow<List<Credential>>(emptyList())

    fun emit() {
        flow.value = credentials.values.toList()
    }

    override fun observeCredentials(): Flow<List<Credential>> = flow

    override suspend fun save(credential: Credential, secret: CredentialSecret) = throw UnsupportedOperationException()

    override suspend fun delete(id: UUID) = throw UnsupportedOperationException()

    override suspend fun readSecret(id: UUID): CredentialSecret? = secrets[id]
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
