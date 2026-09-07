package ai.routin.mytoken.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Whole-screen state rendered by [SettingsScreen]. */
data class SettingsUiState(
    val isLoading: Boolean = true,
    val refresh: RefreshSettings = RefreshSettings(),
    val display: DisplaySettings = DisplaySettings(),
)

/**
 * Settings state holder. All preferences are Android-local; macOS-only options
 * (menu bar style, login item, window behavior) are intentionally absent.
 */
class SettingsViewModel(
    private val refreshStore: RefreshSettingsStore,
    private val displayStore: DisplaySettingsStore,
) : ViewModel() {

    val state: StateFlow<SettingsUiState> = combine(
        refreshStore.settings,
        displayStore.settings,
    ) { refresh, display ->
        SettingsUiState(isLoading = false, refresh = refresh, display = display)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, SettingsUiState())

    fun setAutoRefreshEnabled(enabled: Boolean) = launch { refreshStore.setAutoRefreshEnabled(enabled) }

    fun setRefreshIntervalMinutes(minutes: Int) {
        if (minutes !in RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES) return
        launch { refreshStore.setRefreshIntervalMinutes(minutes) }
    }

    fun setWifiOnly(enabled: Boolean) = launch { refreshStore.setWifiOnly(enabled) }

    fun setOpenAppRefresh(enabled: Boolean) = launch { refreshStore.setOpenAppRefresh(enabled) }

    fun setRetryOnFailure(enabled: Boolean) = launch { refreshStore.setRetryOnFailure(enabled) }

    fun setCardDensity(density: CardDensity) = launch { displayStore.setCardDensity(density) }

    fun setShowDisabledCredentials(enabled: Boolean) =
        launch { displayStore.setShowDisabledCredentials(enabled) }

    fun setDefaultExpandGroups(enabled: Boolean) =
        launch { displayStore.setDefaultExpandGroups(enabled) }

    fun setShowUsageProgress(enabled: Boolean) =
        launch { displayStore.setShowUsageProgress(enabled) }

    fun setShowBalance(enabled: Boolean) = launch { displayStore.setShowBalance(enabled) }

    fun setShowResetTime(enabled: Boolean) = launch { displayStore.setShowResetTime(enabled) }

    private fun launch(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }
}
