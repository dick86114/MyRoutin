package ai.routin.mytoken.feature.credentials

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Android-local credential ordering, kept fully independent of the macOS sort:
 * transfer imports carry the Mac's sortOrder on each credential, so the phone-side
 * manual order is persisted in a separate DataStore (never synced back to Mac).
 */
interface CredentialOrderStore {
    /** Ordered credential IDs (as strings). IDs missing from the store fall back to repository order. */
    val order: Flow<List<String>>

    /** Credential IDs pinned by the user; pinned rows float to the top of their provider group. */
    val pinnedIds: Flow<Set<String>>

    suspend fun saveOrder(ids: List<String>)
    suspend fun setPinned(id: String, pinned: Boolean)
}

private val Context.credentialOrderDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "mytoken_credential_order"
)

class DataStoreCredentialOrderStore(private val context: Context) : CredentialOrderStore {

    override val order: Flow<List<String>> = context.credentialOrderDataStore.data.map { prefs ->
        prefs[ORDER_KEY]
            ?.split('\n')
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?: emptyList()
    }

    override val pinnedIds: Flow<Set<String>> = context.credentialOrderDataStore.data.map { prefs ->
        prefs[PINNED_KEY] ?: emptySet()
    }

    override suspend fun saveOrder(ids: List<String>) {
        context.credentialOrderDataStore.edit { prefs ->
            prefs[ORDER_KEY] = ids.joinToString("\n")
        }
    }

    override suspend fun setPinned(id: String, pinned: Boolean) {
        context.credentialOrderDataStore.edit { prefs ->
            val current = prefs[PINNED_KEY] ?: emptySet()
            prefs[PINNED_KEY] = if (pinned) current + id else current - id
        }
    }

    private companion object {
        val ORDER_KEY = stringPreferencesKey("credentialOrder")
        val PINNED_KEY = stringSetPreferencesKey("pinnedCredentialIds")
    }
}

/**
 * Removes a deleted credential from the persisted order and pinned sets so IDs
 * of deleted credentials never pile up. Every delete path (credential list and
 * home detail) must go through this helper.
 */
suspend fun CredentialOrderStore.pruneCredential(id: UUID) {
    val idString = id.toString()
    saveOrder(order.first().filter { it != idString })
    setPinned(idString, false)
}
