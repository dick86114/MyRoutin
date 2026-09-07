package ai.routin.mytoken.feature.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Refresh-related preferences consumed by the in-app refresh behavior and (Task 10) the scheduler. */
data class RefreshSettings(
    val autoRefreshEnabled: Boolean = true,
    val refreshIntervalMinutes: Int = DEFAULT_REFRESH_INTERVAL_MINUTES,
    val wifiOnly: Boolean = false,
    val openAppRefresh: Boolean = true,
    val retryOnFailure: Boolean = true,
) {
    companion object {
        const val DEFAULT_REFRESH_INTERVAL_MINUTES = 15
        val ALLOWED_REFRESH_INTERVAL_MINUTES = setOf(1, 5, 15, 30)
    }
}

interface RefreshSettingsStore {
    val settings: Flow<RefreshSettings>
    suspend fun setAutoRefreshEnabled(enabled: Boolean)
    suspend fun setRefreshIntervalMinutes(minutes: Int)
    suspend fun setWifiOnly(enabled: Boolean)
    suspend fun setOpenAppRefresh(enabled: Boolean)
    suspend fun setRetryOnFailure(enabled: Boolean)
}

private val Context.refreshSettingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "mytoken_refresh_settings"
)

/** Android-local DataStore store; Task 10's background scheduler should read these values. */
class DataStoreRefreshSettingsStore(private val context: Context) : RefreshSettingsStore {

    override val settings: Flow<RefreshSettings> = context.refreshSettingsDataStore.data.map { prefs ->
        RefreshSettings(
            autoRefreshEnabled = prefs[AUTO_REFRESH] ?: true,
            refreshIntervalMinutes = prefs[REFRESH_INTERVAL]
                ?: RefreshSettings.DEFAULT_REFRESH_INTERVAL_MINUTES,
            wifiOnly = prefs[WIFI_ONLY] ?: false,
            openAppRefresh = prefs[OPEN_APP_REFRESH] ?: true,
            retryOnFailure = prefs[RETRY_ON_FAILURE] ?: true,
        )
    }

    override suspend fun setAutoRefreshEnabled(enabled: Boolean) =
        edit { it[AUTO_REFRESH] = enabled }

    override suspend fun setRefreshIntervalMinutes(minutes: Int) {
        require(minutes in RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES) {
            "refreshIntervalMinutes must be one of ${RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES}"
        }
        edit { it[REFRESH_INTERVAL] = minutes }
    }

    override suspend fun setWifiOnly(enabled: Boolean) = edit { it[WIFI_ONLY] = enabled }

    override suspend fun setOpenAppRefresh(enabled: Boolean) = edit { it[OPEN_APP_REFRESH] = enabled }

    override suspend fun setRetryOnFailure(enabled: Boolean) = edit { it[RETRY_ON_FAILURE] = enabled }

    private suspend fun edit(transform: (androidx.datastore.preferences.core.MutablePreferences) -> Unit) {
        context.refreshSettingsDataStore.edit(transform)
    }

    private companion object {
        val AUTO_REFRESH = booleanPreferencesKey("autoRefreshEnabled")
        val REFRESH_INTERVAL = intPreferencesKey("refreshIntervalMinutes")
        val WIFI_ONLY = booleanPreferencesKey("wifiOnly")
        val OPEN_APP_REFRESH = booleanPreferencesKey("openAppRefresh")
        val RETRY_ON_FAILURE = booleanPreferencesKey("retryOnFailure")
    }
}
