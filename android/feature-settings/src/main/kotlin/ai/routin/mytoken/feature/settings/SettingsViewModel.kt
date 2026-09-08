package ai.routin.mytoken.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Whole-screen state rendered by [SettingsScreen]. */
data class SettingsUiState(
    val isLoading: Boolean = true,
    val refresh: RefreshSettings = RefreshSettings(),
    val display: DisplaySettings = DisplaySettings(),
    val notifications: NotificationSettings = NotificationSettings(),
    val update: UpdateSettings = UpdateSettings(),
)

/**
 * Settings state holder. All preferences are Android-local; macOS-only options
 * (menu bar style, login item, window behavior) are intentionally absent.
 */
class SettingsViewModel(
    private val refreshStore: RefreshSettingsStore,
    private val displayStore: DisplaySettingsStore,
    private val notificationStore: NotificationSettingsStore,
    private val updateStore: UpdateSettingsStore,
    private val updateController: AppUpdateController,
) : ViewModel() {

    val state: StateFlow<SettingsUiState> = combine(
        refreshStore.settings,
        displayStore.settings,
        notificationStore.settings,
        updateStore.settings,
    ) { refresh, display, notifications, update ->
        currentNotifications = notifications
        SettingsUiState(
            isLoading = false,
            refresh = refresh,
            display = display,
            notifications = notifications,
            update = update,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, SettingsUiState())

    val updateState: StateFlow<AppUpdateUiState> = updateController.state

    fun checkForUpdates() = updateController.checkForUpdates()

    fun downloadAndInstall(version: String, downloadUrl: String) =
        updateController.downloadAndInstall(version, downloadUrl)

    fun openInstallPermissionSettings() = updateController.openInstallPermissionSettings()

    fun installDownloadedUpdate() = updateController.installDownloadedUpdate()

    @Volatile
    private var currentNotifications: NotificationSettings = NotificationSettings()

    fun setAutoRefreshEnabled(enabled: Boolean) = launch { refreshStore.setAutoRefreshEnabled(enabled) }

    fun setRefreshIntervalMinutes(minutes: Int) {
        if (minutes !in RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES) return
        launch { refreshStore.setRefreshIntervalMinutes(minutes) }
    }

    fun setWifiOnly(enabled: Boolean) = launch { refreshStore.setWifiOnly(enabled) }

    fun setOpenAppRefresh(enabled: Boolean) = launch { refreshStore.setOpenAppRefresh(enabled) }

    fun setRetryOnFailure(enabled: Boolean) = launch { refreshStore.setRetryOnFailure(enabled) }

    fun setThemeMode(mode: AppThemeMode) = launch { displayStore.setThemeMode(mode) }

    fun setShowDisabledCredentials(enabled: Boolean) =
        launch { displayStore.setShowDisabledCredentials(enabled) }

    fun setDefaultExpandGroups(enabled: Boolean) =
        launch { displayStore.setDefaultExpandGroups(enabled) }

    fun setShowUsageProgress(enabled: Boolean) =
        launch { displayStore.setShowUsageProgress(enabled) }

    fun setShowBalance(enabled: Boolean) = launch { displayStore.setShowBalance(enabled) }

    fun setShowResetTime(enabled: Boolean) = launch { displayStore.setShowResetTime(enabled) }

    fun setNotificationsEnabled(enabled: Boolean) =
        launch { notificationStore.setNotificationsEnabled(enabled) }

    fun setCredentialFailureAlertsEnabled(enabled: Boolean) =
        launch { notificationStore.setCredentialFailureAlertsEnabled(enabled) }

    fun setUpdateMirrorBase(base: String) = launch { updateStore.setMirrorBase(base) }

    fun setLowAlertThreshold(percent: Int) {
        if (!isValidThreshold(percent)) return
        if (percent >= currentNotifications.highThresholdPercent) return
        launch { notificationStore.setAlertThresholds(percent, currentNotifications.highThresholdPercent) }
    }

    fun setHighAlertThreshold(percent: Int) {
        if (!isValidThreshold(percent)) return
        if (percent <= currentNotifications.lowThresholdPercent) return
        launch { notificationStore.setAlertThresholds(currentNotifications.lowThresholdPercent, percent) }
    }

    private fun isValidThreshold(percent: Int) =
        percent in NotificationSettings.MIN_THRESHOLD_PERCENT..NotificationSettings.MAX_THRESHOLD_PERCENT

    private fun launch(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }
}
