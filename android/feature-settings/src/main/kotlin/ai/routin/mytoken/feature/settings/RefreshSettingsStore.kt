package ai.routin.mytoken.feature.settings

import ai.routin.mytoken.data.preferences.AppPreferencesRepository
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

/**
 * Single-source-of-truth adapter over the Task 5 [AppPreferencesRepository] DataStore
 * (`mytoken_settings`). Refresh settings have exactly one persisted key per semantic:
 * refreshIntervalMinutes / wifiOnly / openAppRefresh reuse the existing Task 5 keys, and
 * autoRefreshEnabled / retryOnFailure live as new keys in the same store — there is no
 * second refresh-settings DataStore.
 */
class AppPreferencesRefreshSettingsStore(
    private val preferencesRepository: AppPreferencesRepository,
) : RefreshSettingsStore {

    override val settings: Flow<RefreshSettings> = preferencesRepository.preferences.map { prefs ->
        RefreshSettings(
            autoRefreshEnabled = prefs.autoRefreshEnabled,
            refreshIntervalMinutes = prefs.refreshIntervalMinutes,
            wifiOnly = prefs.wifiOnly,
            openAppRefresh = prefs.openAppRefresh,
            retryOnFailure = prefs.retryOnFailure,
        )
    }

    override suspend fun setAutoRefreshEnabled(enabled: Boolean) {
        preferencesRepository.setAutoRefreshEnabled(enabled)
    }

    override suspend fun setRefreshIntervalMinutes(minutes: Int) {
        require(minutes in RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES) {
            "refreshIntervalMinutes must be one of ${RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES}"
        }
        preferencesRepository.setRefreshIntervalMinutes(minutes)
    }

    override suspend fun setWifiOnly(enabled: Boolean) {
        preferencesRepository.setWifiOnly(enabled)
    }

    override suspend fun setOpenAppRefresh(enabled: Boolean) {
        preferencesRepository.setOpenAppRefresh(enabled)
    }

    override suspend fun setRetryOnFailure(enabled: Boolean) {
        preferencesRepository.setRetryOnFailure(enabled)
    }
}
