package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** One credential row inside a provider group. */
data class CredentialRowUi(
    val credential: Credential,
    val isPinned: Boolean,
)

/** One provider group of the credential list. */
data class CredentialGroupUi(
    val providerId: ProviderId,
    val displayName: String,
    val rows: List<CredentialRowUi>,
)

/** Whole-screen state rendered by [CredentialListScreen]. */
data class CredentialListUiState(
    val isLoading: Boolean = true,
    val searchQuery: String = "",
    val groups: List<CredentialGroupUi> = emptyList(),
    val credentialCount: Int = 0,
    val pendingDeletion: Credential? = null,
    val errorMessage: String? = null,
)

/**
 * Credential management state holder. Ordering is Android-local: the phone-side manual
 * order lives in [CredentialOrderStore] and is never written back to macOS.
 */
class CredentialListViewModel(
    private val repository: ai.routin.mytoken.domain.repository.CredentialRepository,
    private val orderStore: CredentialOrderStore,
) : ViewModel() {

    private val searchQuery = kotlinx.coroutines.flow.MutableStateFlow("")
    private val pendingDeletion = kotlinx.coroutines.flow.MutableStateFlow<Credential?>(null)
    private val errorMessage = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)

    private data class CoreState(
        val credentials: List<Credential> = emptyList(),
        val order: List<String> = emptyList(),
        val pinned: Set<String> = emptySet(),
        val searchQuery: String = "",
    )

    private val core = combine(
        repository.observeCredentials(),
        orderStore.order,
        orderStore.pinnedIds,
        searchQuery,
    ) { credentials, order, pinned, query ->
        CoreState(credentials, order, pinned, query)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, CoreState())

    val state: StateFlow<CredentialListUiState> = combine(
        core,
        pendingDeletion,
        errorMessage,
    ) { core, pending, error ->
        CredentialListUiState(
            isLoading = false,
            searchQuery = core.searchQuery,
            groups = buildGroups(core),
            credentialCount = countVisible(core),
            pendingDeletion = pending,
            errorMessage = error,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, CredentialListUiState())

    fun setSearchQuery(query: String) {
        searchQuery.value = query
    }

    fun requestDelete(credential: Credential) {
        pendingDeletion.value = credential
    }

    fun dismissDelete() {
        pendingDeletion.value = null
    }

    fun confirmDelete() {
        val target = pendingDeletion.value ?: return
        pendingDeletion.value = null
        viewModelScope.launch {
            try {
                repository.delete(target.id)
                // Keep the persisted order clean so IDs of deleted credentials never pile up.
                orderStore.pruneCredential(target.id)
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (_: Throwable) {
                errorMessage.value = "删除失败，请重试"
            }
        }
    }

    fun toggleEnabled(credential: Credential) {
        viewModelScope.launch {
            val secret = try {
                repository.readSecret(credential.id)
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            if (secret == null) {
                errorMessage.value = "凭证密钥缺失，无法修改启用状态"
                return@launch
            }
            try {
                repository.save(credential.copy(isEnabled = !credential.isEnabled), secret)
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (_: Throwable) {
                errorMessage.value = "保存失败，请重试"
            }
        }
    }

    fun setPinned(credential: Credential, pinned: Boolean) {
        viewModelScope.launch {
            orderStore.setPinned(credential.id.toString(), pinned)
        }
    }

    /**
     * Long-press drag reorder within one provider group. Index shift is computed by the
     * caller from the drag distance; invalid shifts are ignored.
     *
     * The move is applied to the FULL (unfiltered) credential list, so credentials hidden
     * by an active search filter keep their relative positions in the persisted order —
     * the persisted list is always a permutation of every credential ID. The UI keeps the
     * drag handle disabled while a search filter is active (see [CredentialListScreen]).
     */
    fun moveWithinGroup(providerId: ProviderId, fromRow: Int, toRow: Int) {
        val core = core.value
        val ordered = orderedCredentials(core)
        val groupRows = ordered.filter { it.providerId == providerId }
        if (fromRow !in groupRows.indices || toRow !in groupRows.indices || fromRow == toRow) return
        val reordered = groupRows.toMutableList().apply {
            add(toRow, removeAt(fromRow))
        }
        val newIds = mutableListOf<String>()
        var groupIndex = 0
        for (credential in ordered) {
            if (credential.providerId == providerId) {
                newIds.add(reordered[groupIndex++].id.toString())
            } else {
                newIds.add(credential.id.toString())
            }
        }
        viewModelScope.launch {
            orderStore.saveOrder(newIds)
        }
    }

    fun consumeError() {
        errorMessage.value = null
    }

    private fun buildGroups(core: CoreState): List<CredentialGroupUi> {
        val ordered = orderedCredentials(core)
        val query = core.searchQuery.trim()
        val pinnedSet = core.pinned
        return ordered
            .groupBy { it.providerId }
            .map { (providerId, credentials) ->
                val visible = if (query.isEmpty()) {
                    credentials
                } else {
                    credentials.filter { it.name.contains(query, ignoreCase = true) }
                }
                val sorted = visible.sortedByDescending { pinnedSet.contains(it.id.toString()) }
                CredentialGroupUi(
                    providerId = providerId,
                    displayName = ProviderNames.displayName(providerId),
                    rows = sorted.map { CredentialRowUi(it, pinnedSet.contains(it.id.toString())) },
                )
            }
            .filter { it.rows.isNotEmpty() }
    }

    /** Applies the Android-local order; credentials missing from it keep repository order. */
    private fun orderedCredentials(core: CoreState): List<Credential> {
        val byId = core.credentials.associateBy { it.id.toString() }
        val orderedIds = core.order.filter { byId.containsKey(it) }.distinct()
        val remainder = core.credentials.filter { it.id.toString() !in orderedIds.toSet() }
        return orderedIds.mapNotNull { byId[it] } + remainder
    }

    private fun countVisible(core: CoreState): Int = buildGroups(core).sumOf { it.rows.size }
}

/** Provider display names, mirrored from feature-home's ProviderCatalog for this module. */
object ProviderNames {
    fun displayName(providerId: ProviderId): String = when (providerId) {
        ProviderId.Routin -> "Routin"
        ProviderId.DeepSeek -> "DeepSeek"
        ProviderId.Glm -> "智谱 GLM"
        ProviderId.Volcengine -> "火山方舟"
        ProviderId.NewAPI -> "New API"
    }
}
