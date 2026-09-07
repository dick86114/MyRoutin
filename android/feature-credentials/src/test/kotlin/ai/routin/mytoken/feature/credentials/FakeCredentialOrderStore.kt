package ai.routin.mytoken.feature.credentials

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/** In-memory [CredentialOrderStore] fake. */
class FakeCredentialOrderStore : CredentialOrderStore {
    val orderState = MutableStateFlow<List<String>>(emptyList())
    val pinnedState = MutableStateFlow<Set<String>>(emptySet())
    var savedOrders = 0

    override val order: Flow<List<String>> = orderState
    override val pinnedIds: Flow<Set<String>> = pinnedState

    override suspend fun saveOrder(ids: List<String>) {
        savedOrders++
        orderState.value = ids
    }

    override suspend fun setPinned(id: String, pinned: Boolean) {
        pinnedState.update { if (pinned) it + id else it - id }
    }
}
