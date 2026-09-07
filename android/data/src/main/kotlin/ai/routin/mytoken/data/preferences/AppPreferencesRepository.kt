package ai.routin.mytoken.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** App settings, mirroring the preferences block of transfer-schema-v1.json (subset). */
data class AppPreferences(
    val autoRefreshEnabled: Boolean = true,
    val refreshIntervalMinutes: Int = DEFAULT_REFRESH_INTERVAL_MINUTES,
    val wifiOnly: Boolean = false,
    val openAppRefresh: Boolean = true,
    val retryOnFailure: Boolean = true,
    val notificationsEnabled: Boolean = true
) {
    companion object {
        const val DEFAULT_REFRESH_INTERVAL_MINUTES = 15
        val ALLOWED_REFRESH_INTERVAL_MINUTES = setOf(1, 5, 15, 30)
    }
}

private val Context.preferencesDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "mytoken_settings"
)

class AppPreferencesRepository(private val context: Context) {

    val preferences: Flow<AppPreferences> = context.preferencesDataStore.data.map { prefs ->
        AppPreferences(
            autoRefreshEnabled = prefs[AUTO_REFRESH_ENABLED] ?: true,
            refreshIntervalMinutes = prefs[REFRESH_INTERVAL_MINUTES]
                ?: AppPreferences.DEFAULT_REFRESH_INTERVAL_MINUTES,
            wifiOnly = prefs[WIFI_ONLY] ?: false,
            openAppRefresh = prefs[OPEN_APP_REFRESH] ?: true,
            retryOnFailure = prefs[RETRY_ON_FAILURE] ?: true,
            notificationsEnabled = prefs[NOTIFICATIONS_ENABLED] ?: true
        )
    }

    suspend fun setAutoRefreshEnabled(enabled: Boolean) {
        context.preferencesDataStore.edit { it[AUTO_REFRESH_ENABLED] = enabled }
    }

    suspend fun setRefreshIntervalMinutes(minutes: Int) {
        require(minutes in AppPreferences.ALLOWED_REFRESH_INTERVAL_MINUTES) {
            "refreshIntervalMinutes must be one of ${AppPreferences.ALLOWED_REFRESH_INTERVAL_MINUTES}"
        }
        context.preferencesDataStore.edit { it[REFRESH_INTERVAL_MINUTES] = minutes }
    }

    suspend fun setWifiOnly(enabled: Boolean) {
        context.preferencesDataStore.edit { it[WIFI_ONLY] = enabled }
    }

    suspend fun setOpenAppRefresh(enabled: Boolean) {
        context.preferencesDataStore.edit { it[OPEN_APP_REFRESH] = enabled }
    }

    suspend fun setRetryOnFailure(enabled: Boolean) {
        context.preferencesDataStore.edit { it[RETRY_ON_FAILURE] = enabled }
    }

    suspend fun setNotificationsEnabled(enabled: Boolean) {
        context.preferencesDataStore.edit { it[NOTIFICATIONS_ENABLED] = enabled }
    }

    private companion object {
        val AUTO_REFRESH_ENABLED = booleanPreferencesKey("autoRefreshEnabled")
        val REFRESH_INTERVAL_MINUTES = intPreferencesKey("refreshIntervalMinutes")
        val WIFI_ONLY = booleanPreferencesKey("wifiOnly")
        val OPEN_APP_REFRESH = booleanPreferencesKey("openAppRefresh")
        val RETRY_ON_FAILURE = booleanPreferencesKey("retryOnFailure")
        val NOTIFICATIONS_ENABLED = booleanPreferencesKey("notificationsEnabled")
    }
}
