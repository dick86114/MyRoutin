package ai.routin.mytoken.update

import ai.routin.mytoken.feature.settings.AppUpdateController
import ai.routin.mytoken.feature.settings.AppUpdateUiState
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * GitHub Release 自更新。APK 只来自本仓库的 HTTPS release asset；
 * 下载完成后交给系统安装器，Android 仍会展示最终安装确认。
 */
class GitHubAppUpdateController(
    private val context: Context,
    private val currentVersionName: String,
    private val repository: String = "dick86114/MyToken",
    private val network: suspend (String, Map<String, String>) -> UpdateResponse = ::request,
) : AppUpdateController {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val _state = MutableStateFlow<AppUpdateUiState>(AppUpdateUiState.Idle)
    private var downloadedUpdate: DownloadedUpdate? = null

    override val state: StateFlow<AppUpdateUiState> = _state.asStateFlow()

    override fun checkForUpdates() {
        scope.launch {
            runCatching {
                mutex.withLock {
                    _state.update { AppUpdateUiState.Checking }
                    val release = fetchLatestRelease()
                    if (compareVersions(release.version, currentVersionName) <= 0) {
                        AppUpdateUiState.UpToDate(currentVersionName)
                    } else {
                        AppUpdateUiState.Available(
                            version = release.version,
                            releaseNotes = release.notes,
                            downloadUrl = release.downloadUrl,
                        )
                    }
                }
            }.onSuccess { nextState ->
                _state.update { nextState }
            }.onFailure { error ->
                _state.update { AppUpdateUiState.Error(error.userMessage()) }
            }
        }
    }

    override fun downloadAndInstall(version: String, downloadUrl: String) {
        val currentState = _state.value
        if (currentState !is AppUpdateUiState.Available ||
            currentState.version != version ||
            currentState.downloadUrl != downloadUrl
        ) {
            return
        }
        scope.launch {
            runCatching {
                mutex.withLock {
                    downloadAndInstall(
                        AvailableRelease(
                            version = version,
                            notes = currentState.releaseNotes,
                            downloadUrl = downloadUrl,
                        ),
                    )
                }
            }.onFailure { error ->
                _state.update { AppUpdateUiState.Error(error.userMessage()) }
            }
        }
    }

    override fun openInstallPermissionSettings() {
        val intent = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            .setData(Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }

    override fun installDownloadedUpdate() {
        val update = downloadedUpdate ?: return
        if (!canRequestInstalls()) {
            _state.update {
                AppUpdateUiState.NeedsInstallPermission(update.version)
            }
            return
        }
        install(update)
    }

    private suspend fun downloadAndInstall(update: AvailableRelease) {
        _state.update { AppUpdateUiState.Downloading(progress = null) }
        val file = download(update)
        downloadedUpdate = DownloadedUpdate(version = update.version, file = file)

        if (!canRequestInstalls()) {
            _state.update { AppUpdateUiState.NeedsInstallPermission(update.version) }
            return
        }
        install(downloadedUpdate ?: return)
    }

    private suspend fun download(update: AvailableRelease): File = withContext(Dispatchers.IO) {
        val directory = context.getExternalFilesDir("updates") ?: File(context.filesDir, "updates").apply { mkdirs() }
        directory.mkdirs()
        val target = File(directory, "MyToken-${update.version}.apk")
        val temporary = File(directory, "${target.name}.part")
        target.delete()
        temporary.delete()

        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(update.downloadUrl, headers = emptyMap())
            if (connection.responseCode !in 200..299) {
                throw IOException("更新包下载失败（HTTP ${connection.responseCode}）")
            }
            val total = connection.contentLengthLong
            val input = connection.inputStream
            val output = temporary.outputStream()
            val buffer = ByteArray(64 * 1024)
            var downloaded = 0L
            var lastReported = -1L

            input.use { source ->
                output.use { destination ->
                    while (true) {
                        val count = source.read(buffer)
                        if (count == -1) break
                        destination.write(buffer, 0, count)
                        downloaded += count
                        if (total > 0) {
                            val progress = (downloaded * 100 / total).toInt()
                            if (progress.toLong() != lastReported) {
                                lastReported = progress.toLong()
                                _state.update {
                                    AppUpdateUiState.Downloading(progress = progress / 100f)
                                }
                            }
                        }
                    }
                }
            }

            if (total > 0 && downloaded != total) {
                throw IOException("更新包下载不完整")
            }
            if (!temporary.renameTo(target)) {
                temporary.copyTo(target, overwrite = true)
                temporary.delete()
            }
            target
        } catch (error: Throwable) {
            temporary.delete()
            throw error
        } finally {
            connection?.disconnect()
        }
    }

    private suspend fun fetchLatestRelease(): AvailableRelease {
        val body = network(
            "https://api.github.com/repos/$repository/releases/latest",
            mapOf(
                "Accept" to "application/vnd.github+json",
                "X-GitHub-Api-Version" to "2022-11-28",
            ),
        ).body
        val json = JSONObject(body)
        val tag = json.optString("tag_name")
        val version = tag.removePrefix("v").takeIf { it.isNotEmpty() }
            ?: throw IOException("发布版本号无效")
        val asset = json.optJSONArray("assets")
            ?.let { assets ->
                buildList {
                    for (index in 0 until assets.length()) {
                        add(assets.getJSONObject(index))
                    }
                }
            }
            ?.mapNotNull { asset ->
                val name = asset.optString("name")
                val url = asset.optString("browser_download_url")
                APK_ASSET_REGEX.matchEntire(name)?.let { match ->
                    val isDebug = match.groupValues[2].isNotEmpty()
                    ReleaseAsset(name = name, url = url, version = match.groupValues[1], isDebug = isDebug)
                }
            }
            ?.sortedWith(compareBy({ it.isDebug }, { it.version }))
            ?.firstOrNull()
            ?: throw IOException("最新发布没有 Android 安装包")

        return AvailableRelease(
            version = version,
            notes = json.optString("body"),
            downloadUrl = asset.url,
        )
    }

    private fun install(update: DownloadedUpdate) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.update.fileprovider",
            update.file,
        )
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
            .onSuccess {
                _state.update { AppUpdateUiState.ReadyToInstall(update.version) }
            }
            .onFailure { error ->
                _state.update { AppUpdateUiState.Error(error.userMessage()) }
            }
    }

    private fun canRequestInstalls(): Boolean =
        context.packageManager.canRequestPackageInstalls()

    private data class DownloadedUpdate(
        val version: String,
        val file: File,
    )

    private data class AvailableRelease(
        val version: String,
        val notes: String,
        val downloadUrl: String,
    )

    private data class ReleaseAsset(
        val name: String,
        val url: String,
        val version: String,
        val isDebug: Boolean,
    )

    companion object {
        private val APK_ASSET_REGEX = Regex(
            "^MyToken-(\\d+(?:\\.\\d+)+)-android(-debug)?\\.apk$",
            option = RegexOption.IGNORE_CASE,
        )
        private const val APK_MIME = "application/vnd.android.package-archive"

        internal fun compareVersions(left: String, right: String): Int {
            val leftParts = left.split('.').map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
            val rightParts = right.split('.').map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
            for (index in 0 until maxOf(leftParts.size, rightParts.size)) {
                val difference = leftParts.getOrElse(index) { 0 } - rightParts.getOrElse(index) { 0 }
                if (difference != 0) return difference
            }
            return 0
        }

        private suspend fun request(url: String, headers: Map<String, String>): UpdateResponse =
            withContext(Dispatchers.IO) {
                val connection = openConnection(url, headers)
                try {
                    val code = connection.responseCode
                    if (code !in 200..299) throw IOException("GitHub 更新检查失败（HTTP $code）")
                    UpdateResponse(connection.inputStream.bufferedReader().use { it.readText() })
                } finally {
                    connection.disconnect()
                }
            }

        private fun openConnection(url: String, headers: Map<String, String>): HttpURLConnection {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "MyToken-Android-Updater")
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            return connection
        }

        private fun Throwable.userMessage(): String = when (this) {
            is IOException -> message ?: "网络异常，请稍后重试"
            else -> "检查更新失败，请稍后重试"
        }
    }
}

data class UpdateResponse(val body: String)
