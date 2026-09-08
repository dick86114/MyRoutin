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

interface AppUpdateController {
    val state: StateFlow<AppUpdateUiState>

    fun checkForUpdates()

    fun downloadAndInstall(version: String, downloadUrl: String)

    fun openInstallPermissionSettings()

    fun installDownloadedUpdate()
}
