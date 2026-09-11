package ai.routin.mytoken.feature.settings

import kotlinx.coroutines.flow.StateFlow

/** Android 自更新链路暴露给设置页的状态。 */
sealed interface AppUpdateUiState {
    data object Idle : AppUpdateUiState

    data object Checking : AppUpdateUiState

    data class UpToDate(val currentVersion: String) : AppUpdateUiState

    data class Available(
        val version: String,
        val releaseNotes: String,
        val downloadUrl: String,
    ) : AppUpdateUiState

    data class Downloading(val progress: Float?) : AppUpdateUiState

    data class ReadyToInstall(val version: String) : AppUpdateUiState

    data class NeedsInstallPermission(val version: String) : AppUpdateUiState

    data class Error(val message: String) : AppUpdateUiState
}

data class AppReleaseHistoryItem(
    val version: String,
    val releaseNotes: String,
    val releaseUrl: String,
    val publishedAt: String?,
)

sealed interface AppReleaseHistoryUiState {
    data object Idle : AppReleaseHistoryUiState

    data object Loading : AppReleaseHistoryUiState

    data class Loaded(val releases: List<AppReleaseHistoryItem>) : AppReleaseHistoryUiState

    data class Error(val message: String) : AppReleaseHistoryUiState
}

interface AppUpdateController {
    val state: StateFlow<AppUpdateUiState>
    val releaseHistoryState: StateFlow<AppReleaseHistoryUiState>

    fun checkForUpdates()

    fun loadReleaseHistory()

    fun downloadAndInstall(version: String, downloadUrl: String)

    fun openInstallPermissionSettings()

    fun installDownloadedUpdate()
}
