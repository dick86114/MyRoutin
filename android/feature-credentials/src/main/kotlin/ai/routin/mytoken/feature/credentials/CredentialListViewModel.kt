package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class CredentialListUiState(
    val isLoading: Boolean = true,
    val items: List<Credential> = emptyList(),
    val pendingDeletion: Credential? = null,
    val errorMessage: String? = null,
)

class CredentialListViewModel(
    private val repository: ai.routin.mytoken.domain.repository.CredentialRepository,
    private val orderStore: CredentialOrderStore,
) : ViewModel() {

    private val pendingDeletion = MutableStateFlow<Credential?>(null)
    private val errorMessage = MutableStateFlow<String?>(null)
    private val pendingOrder = MutableStateFlow<List<String>?>(null)

    private data class CoreState(
        val credentials: List<Credential> = emptyList(),
        val order: List<String> = emptyList(),
    )

    private val core = combine(
        repository.observeCredentials(),
        orderStore.order,
        pendingOrder,
    ) { credentials, order, localOrder -> CoreState(credentials, localOrder ?: order) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, CoreState())

    val state: StateFlow<CredentialListUiState> = combine(
        core,
        pendingDeletion,
        errorMessage,
    ) { core, pending, error ->
        CredentialListUiState(
            isLoading = false,
            items = orderedCredentials(core),
            pendingDeletion = pending,
            errorMessage = error,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, CredentialListUiState())

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

    fun move(fromIndex: Int, toIndex: Int) {
        val items = orderedCredentials(core.value)
        if (fromIndex !in items.indices || toIndex !in items.indices || fromIndex == toIndex) return
        val reordered = items.toMutableList().apply { add(toIndex, removeAt(fromIndex)) }
        val orderIds = reordered.map { it.id.toString() }
        pendingOrder.value = orderIds
        viewModelScope.launch {
            try {
                orderStore.saveOrder(orderIds)
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (_: Throwable) {
                errorMessage.value = "排序保存失败，请重试"
            }
        }
    }

    private fun orderedCredentials(core: CoreState): List<Credential> {
        val byId = core.credentials.associateBy { it.id.toString() }
        val ordered = core.order.filter { byId.containsKey(it) }.distinct().mapNotNull(byId::get)
        val remainder = core.credentials.filter { it.id.toString() !in core.order.toSet() }
        return ordered + remainder
    }
}

object ProviderNames {
    fun displayName(providerId: ProviderId): String = when (providerId) {
        ProviderId.Routin -> "Routin"
        ProviderId.DeepSeek -> "DeepSeek"
        ProviderId.Glm -> "智谱 GLM"
        ProviderId.Volcengine -> "火山方舟"
        ProviderId.NewAPI -> "New API"
        ProviderId.CommandCode -> "Command Code"
    }
}
