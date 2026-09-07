package ai.routin.mytoken.feature.settings

import ai.routin.mytoken.data.preferences.AppPreferencesRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Notification preferences. Thresholds are global settings (the Android metadata
 * allowlist has no per-credential threshold key — Task 9 confirmed), mirroring the
 * macOS default 50/80 semantics; per-credential overrides remain a pure-evaluator
 * capability without persistence.
 */
data class NotificationSettings(
    val notificationsEnabled: Boolean = true,
    val lowThresholdPercent: Int = DEFAULT_LOW_THRESHOLD_PERCENT,
    val highThresholdPercent: Int = DEFAULT_HIGH_THRESHOLD_PERCENT,
    val credentialFailureAlertsEnabled: Boolean = true,
) {
    companion object {
        const val DEFAULT_LOW_THRESHOLD_PERCENT = 50
        const val DEFAULT_HIGH_THRESHOLD_PERCENT = 80
        const val MIN_THRESHOLD_PERCENT = 1
        const val MAX_THRESHOLD_PERCENT = 99
    }
}

interface NotificationSettingsStore {
    val settings: Flow<NotificationSettings>
    suspend fun setNotificationsEnabled(enabled: Boolean)
    suspend fun setAlertThresholds(lowPercent: Int, highPercent: Int)
    suspend fun setCredentialFailureAlertsEnabled(enabled: Boolean)
}

/** Single-source-of-truth adapter over the Task 5 [AppPreferencesRepository] DataStore. */
class AppPreferencesNotificationSettingsStore(
    private val preferencesRepository: AppPreferencesRepository,
) : NotificationSettingsStore {

    override val settings: Flow<NotificationSettings> =
        preferencesRepository.preferences.map { prefs ->
            NotificationSettings(
                notificationsEnabled = prefs.notificationsEnabled,
                lowThresholdPercent = prefs.alertLowThresholdPercent,
                highThresholdPercent = prefs.alertHighThresholdPercent,
                credentialFailureAlertsEnabled = prefs.credentialFailureAlertsEnabled,
            )
        }

    override suspend fun setNotificationsEnabled(enabled: Boolean) {
        preferencesRepository.setNotificationsEnabled(enabled)
    }

    override suspend fun setAlertThresholds(lowPercent: Int, highPercent: Int) {
        require(
            lowPercent in NotificationSettings.MIN_THRESHOLD_PERCENT..NotificationSettings.MAX_THRESHOLD_PERCENT &&
                highPercent in NotificationSettings.MIN_THRESHOLD_PERCENT..NotificationSettings.MAX_THRESHOLD_PERCENT &&
                lowPercent < highPercent,
        ) {
            "alert thresholds must satisfy 0 < low < high <= 99"
        }
        preferencesRepository.setAlertThresholds(lowPercent, highPercent)
    }

    override suspend fun setCredentialFailureAlertsEnabled(enabled: Boolean) {
        preferencesRepository.setCredentialFailureAlertsEnabled(enabled)
    }
}
