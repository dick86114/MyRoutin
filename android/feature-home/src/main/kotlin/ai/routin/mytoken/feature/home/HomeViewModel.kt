package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.repository.CredentialRepository
import ai.routin.mytoken.domain.usage.CredentialUsageState
import ai.routin.mytoken.domain.usage.RefreshCredentialsUseCase
import ai.routin.mytoken.domain.usage.RefreshStatus
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Data freshness buckets, mirroring the macOS popover freshness semantics. */
enum class FreshnessLevel { NEVER, JUST_NOW, RECENT, OLD, EXPIRED }

data class Freshness(val level: FreshnessLevel, val text: String)

/** Formats snapshot age into user-visible freshness labels (刚刚/相对时间/已过期/从未刷新). */
object FreshnessFormatter {
    fun of(fetchedAt: Instant?, now: Instant): Freshness {
        if (fetchedAt == null) return Freshness(FreshnessLevel.NEVER, "从未刷新")
        val duration = Duration.between(fetchedAt, now)
        val minutes = duration.toMinutes()
        return when {
            minutes < 2 -> Freshness(FreshnessLevel.JUST_NOW, "刚刚更新")
            minutes < 60 -> Freshness(FreshnessLevel.RECENT, "${minutes}分钟前更新")
            duration.toHours() < 24 -> Freshness(FreshnessLevel.OLD, "${duration.toHours()}小时前更新")
            else -> Freshness(FreshnessLevel.EXPIRED, "数据已过期")
        }
    }
}

/** Presentation state of one credential card on the home screen. */
data class CredentialCardUi(
    val credential: Credential,
    val status: RefreshStatus,
    val snapshot: UsageSnapshot?,
    val isStale: Boolean,
    val error: AppError?,
    val freshness: Freshness,
)

/** One collapsible provider section on the home screen. */
data class ProviderGroupUi(
    val providerId: ProviderId,
    val displayName: String,
    val isCollapsed: Boolean,
    val cards: List<CredentialCardUi>,
)

/** Whole-screen state rendered by [HomeScreen]. Single source: [HomeViewModel.state]. */
data class HomeUiState(
    val isLoading: Boolean = true,
    val groups: List<ProviderGroupUi> = emptyList(),
    val credentialCount: Int = 0,
    val isRefreshingAll: Boolean = false,
    val lastUpdatedAt: Instant? = null,
    val lastUpdatedText: String? = null,
)

/**
 * Home dashboard state holder. Unidirectional flow:
 * CredentialRepository + RefreshCredentialsUseCase states -> [state] (StateFlow) -> Compose.
 */
class HomeViewModel(
    private val repository: CredentialRepository,
    private val refreshUseCase: RefreshCredentialsUseCase,
    private val clock: Clock = Clock.systemUTC(),
    refreshOnStart: Boolean = true,
    private val nowTickIntervalMillis: Long? = DEFAULT_NOW_TICK_MILLIS,
) : ViewModel() {

    private val collapsedGroups = MutableStateFlow<Set<ProviderId>>(emptySet())
    private val isRefreshingAll = MutableStateFlow(false)
    private val nowTick = MutableStateFlow(0L)

    /** Credential IDs whose refresh is currently in flight (guarded by [inFlightMutex]). */
    private val inFlight = mutableSetOf<UUID>()
    private val inFlightMutex = Mutex()

    /** Atomically claims [id]; returns false when a refresh for it is already running. */
    private suspend fun tryBeginRefresh(id: UUID): Boolean = inFlightMutex.withLock {
        inFlight.add(id)
    }

    private suspend fun endRefresh(id: UUID) {
        inFlightMutex.withLock { inFlight.remove(id) }
    }

    init {
        // Re-render relative freshness labels periodically; disabled in tests via null interval.
        if (nowTickIntervalMillis != null) {
            viewModelScope.launch {
                while (true) {
                    delay(nowTickIntervalMillis)
                    nowTick.update { it + 1 }
                }
            }
        }
        if (refreshOnStart) {
            refreshAll()
        }
    }

    val state: StateFlow<HomeUiState> =
        combine(
            repository.observeCredentials(),
            refreshUseCase.states,
            collapsedGroups,
            isRefreshingAll,
            nowTick,
        ) { credentials, usageStates, collapsed, refreshingAll, _ ->
            buildState(credentials, usageStates, collapsed, refreshingAll)
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = HomeUiState(isLoading = true),
        )

    /**
     * Refreshes every enabled credential. Duplicate suppression:
     * - a second [refreshAll] while one is running is a no-op (CAS on the flag);
     * - a credential already being refreshed (by this call or by [refreshCredential])
     *   is skipped, so no duplicate concurrent provider request is issued.
     */
    fun refreshAll() {
        if (!isRefreshingAll.compareAndSet(expect = false, update = true)) return
        viewModelScope.launch {
            try {
                val credentials = repository.observeCredentials().first()
                coroutineScope {
                    credentials.forEach { credential ->
                        if (tryBeginRefresh(credential.id)) {
                            launch {
                                try {
                                    refreshUseCase.refresh(credential)
                                } finally {
                                    endRefresh(credential.id)
                                }
                            }
                        }
                    }
                }
            } finally {
                isRefreshingAll.value = false
            }
        }
    }

    /**
     * Refreshes one credential; failures keep its last snapshot and mark it stale.
     * A call while the same credential is already refreshing is a no-op.
     */
    fun refreshCredential(credential: Credential) {
        viewModelScope.launch {
            if (tryBeginRefresh(credential.id)) {
                try {
                    refreshUseCase.refresh(credential)
                } finally {
                    endRefresh(credential.id)
                }
            }
        }
    }

    fun toggleGroup(providerId: ProviderId) {
        collapsedGroups.update { current ->
            if (providerId in current) current - providerId else current + providerId
        }
    }

    private fun buildState(
        credentials: List<Credential>,
        usageStates: Map<UUID, CredentialUsageState>,
        collapsed: Set<ProviderId>,
        isRefreshingAll: Boolean,
    ): HomeUiState {
        val now = clock.instant()
        val sorted = credentials.sortedWith(compareBy({ it.sortOrder }, { it.name }))
        val groups = ProviderId.entries
            .filter { providerId -> sorted.any { it.providerId == providerId } }
            .map { providerId ->
                val cards = sorted
                    .filter { it.providerId == providerId }
                    .map { it.toCardUi(usageStates[it.id], now) }
                ProviderGroupUi(
                    providerId = providerId,
                    displayName = ProviderCatalog.displayName(providerId),
                    isCollapsed = providerId in collapsed,
                    cards = cards,
                )
            }
        val lastUpdatedAt = usageStates.values.mapNotNull { it.snapshot?.fetchedAt }.maxOrNull()
        return HomeUiState(
            isLoading = false,
            groups = groups,
            credentialCount = credentials.size,
            isRefreshingAll = isRefreshingAll,
            lastUpdatedAt = lastUpdatedAt,
            lastUpdatedText = lastUpdatedAt?.let { FreshnessFormatter.of(it, now).text },
        )
    }

    private fun Credential.toCardUi(
        usageState: CredentialUsageState?,
        now: Instant,
    ): CredentialCardUi {
        val snapshot = usageState?.snapshot
        // A failed refresh keeps the last successful snapshot; that data is stale regardless
        // of its fetch time because the authoritative refresh did not succeed.
        val freshness = if (usageState?.status == RefreshStatus.Failed && snapshot != null) {
            Freshness(FreshnessLevel.EXPIRED, "数据已过期")
        } else {
            FreshnessFormatter.of(snapshot?.fetchedAt, now)
        }
        return CredentialCardUi(
            credential = this,
            status = usageState?.status ?: RefreshStatus.Loading,
            snapshot = snapshot,
            isStale = usageState?.isStale ?: false,
            error = usageState?.error,
            freshness = freshness,
        )
    }

    private companion object {
        const val DEFAULT_NOW_TICK_MILLIS: Long = 30_000L
    }
}
