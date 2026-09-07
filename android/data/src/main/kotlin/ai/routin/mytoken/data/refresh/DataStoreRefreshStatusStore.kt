package ai.routin.mytoken.data.refresh

import ai.routin.mytoken.core.refresh.RefreshStatusStore
import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Last successful/failed background refresh timestamps, for display and diagnostics. */
data class RefreshTimestamps(
    val lastSuccessAtEpochMillis: Long? = null,
    val lastFailureAtEpochMillis: Long? = null,
)

private val Context.refreshStatusDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "mytoken_refresh_status"
)

/**
 * Dedicated small DataStore (not `mytoken_settings`): the worker records timestamps
 * on every run and must never trigger a settings-flow emission.
 */
class DataStoreRefreshStatusStore(private val context: Context) : RefreshStatusStore {

    val status: Flow<RefreshTimestamps> = context.refreshStatusDataStore.data.map { prefs ->
        RefreshTimestamps(
            lastSuccessAtEpochMillis = prefs[LAST_SUCCESS_AT],
            lastFailureAtEpochMillis = prefs[LAST_FAILURE_AT],
        )
    }

    override suspend fun recordSuccess(attemptAtEpochMillis: Long) {
        context.refreshStatusDataStore.edit { it[LAST_SUCCESS_AT] = attemptAtEpochMillis }
    }

    override suspend fun recordFailure(attemptAtEpochMillis: Long) {
        context.refreshStatusDataStore.edit { it[LAST_FAILURE_AT] = attemptAtEpochMillis }
    }

    private companion object {
        val LAST_SUCCESS_AT = longPreferencesKey("lastRefreshSuccessAt")
        val LAST_FAILURE_AT = longPreferencesKey("lastRefreshFailureAt")
    }
}
