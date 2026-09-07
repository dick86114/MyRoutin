package ai.routin.mytoken.feature.settings

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

class FakeRefreshSettingsStore(initial: RefreshSettings = RefreshSettings()) : RefreshSettingsStore {
    val state = MutableStateFlow(initial)
    override val settings: Flow<RefreshSettings> = state

    override suspend fun setAutoRefreshEnabled(enabled: Boolean) =
        state.update { it.copy(autoRefreshEnabled = enabled) }

    override suspend fun setRefreshIntervalMinutes(minutes: Int) {
        require(minutes in RefreshSettings.ALLOWED_REFRESH_INTERVAL_MINUTES)
        state.update { it.copy(refreshIntervalMinutes = minutes) }
    }

    override suspend fun setWifiOnly(enabled: Boolean) = state.update { it.copy(wifiOnly = enabled) }

    override suspend fun setOpenAppRefresh(enabled: Boolean) =
        state.update { it.copy(openAppRefresh = enabled) }

    override suspend fun setRetryOnFailure(enabled: Boolean) =
        state.update { it.copy(retryOnFailure = enabled) }
}

class FakeDisplaySettingsStore(initial: DisplaySettings = DisplaySettings()) : DisplaySettingsStore {
    val state = MutableStateFlow(initial)
    override val settings: Flow<DisplaySettings> = state

    override suspend fun setCardDensity(density: CardDensity) =
        state.update { it.copy(cardDensity = density) }

    override suspend fun setShowDisabledCredentials(enabled: Boolean) =
        state.update { it.copy(showDisabledCredentials = enabled) }

    override suspend fun setDefaultExpandGroups(enabled: Boolean) =
        state.update { it.copy(defaultExpandGroups = enabled) }

    override suspend fun setShowUsageProgress(enabled: Boolean) =
        state.update { it.copy(showUsageProgress = enabled) }

    override suspend fun setShowBalance(enabled: Boolean) =
        state.update { it.copy(showBalance = enabled) }

    override suspend fun setShowResetTime(enabled: Boolean) =
        state.update { it.copy(showResetTime = enabled) }
}
