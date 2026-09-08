package ai.routin.mytoken.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
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
    val notificationsEnabled: Boolean = true,
    val alertLowThresholdPercent: Int = 50,
    val alertHighThresholdPercent: Int = 80,
    val credentialFailureAlertsEnabled: Boolean = true
) {
    companion object {
        const val DEFAULT_REFRESH_INTERVAL_MINUTES = 15
        val ALLOWED_REFRESH_INTERVAL_MINUTES = setOf(1, 5, 15, 30)
        const val DEFAULT_ALERT_LOW_THRESHOLD_PERCENT = 50
        const val DEFAULT_ALERT_HIGH_THRESHOLD_PERCENT = 80
    }
}

/** 更新通道设置；mirrorBase 为空表示 GitHub 直连，非空表示走该镜像前缀。 */
data class UpdatePreferences(
    val updateMirrorBase: String = "",
)

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
            notificationsEnabled = prefs[NOTIFICATIONS_ENABLED] ?: true,
            alertLowThresholdPercent = prefs[ALERT_LOW_THRESHOLD_PERCENT]
                ?: AppPreferences.DEFAULT_ALERT_LOW_THRESHOLD_PERCENT,
            alertHighThresholdPercent = prefs[ALERT_HIGH_THRESHOLD_PERCENT]
                ?: AppPreferences.DEFAULT_ALERT_HIGH_THRESHOLD_PERCENT,
            credentialFailureAlertsEnabled = prefs[CREDENTIAL_FAILURE_ALERTS_ENABLED] ?: true
        )
    }

    val updatePreferences: Flow<UpdatePreferences> = context.preferencesDataStore.data.map { prefs ->
        UpdatePreferences(
            updateMirrorBase = prefs[UPDATE_MIRROR_BASE].orEmpty().trim(),
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

    /** Usage alert thresholds; low must be lower than high (macOS parity). */
    suspend fun setAlertThresholds(lowPercent: Int, highPercent: Int) {
        require(lowPercent in 1..99 && highPercent in 1..99 && lowPercent < highPercent) {
            "alert thresholds must satisfy 0 < low < high <= 99"
        }
        context.preferencesDataStore.edit {
            it[ALERT_LOW_THRESHOLD_PERCENT] = lowPercent
            it[ALERT_HIGH_THRESHOLD_PERCENT] = highPercent
        }
    }

    suspend fun setCredentialFailureAlertsEnabled(enabled: Boolean) {
        context.preferencesDataStore.edit { it[CREDENTIAL_FAILURE_ALERTS_ENABLED] = enabled }
    }

    suspend fun setUpdateMirrorBase(base: String) {
        context.preferencesDataStore.edit {
            it[UPDATE_MIRROR_BASE] = base.trim().trimEnd('/')
        }
    }

    private companion object {
        val AUTO_REFRESH_ENABLED = booleanPreferencesKey("autoRefreshEnabled")
        val REFRESH_INTERVAL_MINUTES = intPreferencesKey("refreshIntervalMinutes")
        val WIFI_ONLY = booleanPreferencesKey("wifiOnly")
        val OPEN_APP_REFRESH = booleanPreferencesKey("openAppRefresh")
        val RETRY_ON_FAILURE = booleanPreferencesKey("retryOnFailure")
        val NOTIFICATIONS_ENABLED = booleanPreferencesKey("notificationsEnabled")
        val ALERT_LOW_THRESHOLD_PERCENT = intPreferencesKey("alertLowThresholdPercent")
        val ALERT_HIGH_THRESHOLD_PERCENT = intPreferencesKey("alertHighThresholdPercent")
        val CREDENTIAL_FAILURE_ALERTS_ENABLED = booleanPreferencesKey("credentialFailureAlertsEnabled")
        val UPDATE_MIRROR_BASE = stringPreferencesKey("updateMirrorBase")
    }
}
