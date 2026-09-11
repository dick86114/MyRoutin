package ai.routin.mytoken.update

import ai.routin.mytoken.feature.settings.AppUpdateController
import ai.routin.mytoken.feature.settings.AppReleaseHistoryItem
import ai.routin.mytoken.feature.settings.AppReleaseHistoryUiState
import ai.routin.mytoken.feature.settings.AppUpdateUiState
import android.content.Context
import android.content.Intent
import android.text.Html
import android.util.Xml
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
    /** 返回当前镜像前缀；空值/空白表示 GitHub 直连。由 App 层接 DataStore。 */
    private val mirrorBaseProvider: suspend () -> String? = { null },
    private val network: suspend (String, Map<String, String>) -> UpdateResponse = ::request,
    private val probeStatus: (suspend (String) -> Int)? = null,
) : AppUpdateController {

    private val probe: suspend (String) -> Int
        get() = probeStatus ?: { url -> headStatus(url) }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val _state = MutableStateFlow<AppUpdateUiState>(AppUpdateUiState.Idle)
    private val _releaseHistoryState =
        MutableStateFlow<AppReleaseHistoryUiState>(AppReleaseHistoryUiState.Idle)
    private var downloadedUpdate: DownloadedUpdate? = null

    override val state: StateFlow<AppUpdateUiState> = _state.asStateFlow()
    override val releaseHistoryState: StateFlow<AppReleaseHistoryUiState> =
        _releaseHistoryState.asStateFlow()

    override fun checkForUpdates() {
        scope.launch {
            runCatching {
                mutex.withLock {
                    _state.update { AppUpdateUiState.Checking }
                    val mirror = mirrorBase()
                    val release = fetchLatestRelease(mirror)
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

    override fun loadReleaseHistory() {
        if (_releaseHistoryState.value is AppReleaseHistoryUiState.Loading) return
        scope.launch {
            _releaseHistoryState.value = AppReleaseHistoryUiState.Loading
            runCatching {
                fetchReleaseHistoryWithFallback(mirrorBase())
            }.onSuccess { releases ->
                _releaseHistoryState.value = AppReleaseHistoryUiState.Loaded(releases)
            }.onFailure {
                _releaseHistoryState.value = AppReleaseHistoryUiState.Error("更新日志加载失败，请稍后重试")
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
        val mirror = mirrorBase()
        val directory = context.getExternalFilesDir("updates") ?: File(context.filesDir, "updates").apply { mkdirs() }
        directory.mkdirs()
        val target = File(directory, "MyToken-${update.version}.apk")
        val temporary = File(directory, "${target.name}.part")
        target.delete()
        temporary.delete()

        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(applyMirror(update.downloadUrl, mirror), headers = emptyMap())
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

    private suspend fun mirrorBase(): String? =
        mirrorBaseProvider()?.takeIf { it.isNotBlank() }

    private fun applyMirror(url: String, mirror: String?): String =
        if (mirror != null && url.startsWith("https://github.com/")) "$mirror/$url" else url

    private suspend fun fetchLatestRelease(mirror: String?): AvailableRelease {
        val release: AvailableRelease = try {
            fetchLatestReleaseFromApi()
        } catch (error: IOException) {
            // CDN 模式下 API 直连失败时，改走镜像的 Atom 源完成检测。
            if (mirror != null) {
                fetchLatestReleaseFromAtom(mirror)
            } else {
                throw error
            }
        }
        return release.copy(downloadUrl = applyMirror(release.downloadUrl, mirror))
    }

    private suspend fun fetchReleaseHistory(mirror: String?): List<AppReleaseHistoryItem> {
        val result = mutableListOf<AppReleaseHistoryItem>()
        val seenVersions = mutableSetOf<String>()
        var page = 1
        while (page <= 50) {
            val body = network(
                "https://api.github.com/repos/$repository/releases?per_page=100&page=$page",
                mapOf(
                    "Accept" to "application/vnd.github+json",
                    "X-GitHub-Api-Version" to "2022-11-28",
                ),
            ).body
            val releases = org.json.JSONArray(body)
            for (index in 0 until releases.length()) {
                val release = releases.getJSONObject(index)
                val match = ANDROID_RELEASE_TAG_REGEX.matchEntire(release.optString("tag_name")) ?: continue
                val version = match.groupValues[1]
                if (!seenVersions.add(version)) continue
                val releaseUrl = release.optString("html_url")
                    .takeIf { it.isNotBlank() }
                    ?.let { applyMirror(it, mirror) }
                    ?: continue
                result += AppReleaseHistoryItem(
                    version = version,
                    releaseNotes = release.optString("body"),
                    releaseUrl = releaseUrl,
                    publishedAt = release.optString("published_at").takeIf { it.isNotBlank() },
                )
            }
            if (releases.length() < 100) break
            page += 1
        }
        return result.sortedWith { left, right ->
            compareVersions(right.version, left.version)
        }
    }

    private suspend fun fetchReleaseHistoryFromHtml(
        mirror: String?,
    ): List<AppReleaseHistoryItem> {
        val result = mutableListOf<AppReleaseHistoryItem>()
        var page = 1
        while (page <= 50) {
            val body = network(
                applyMirror("https://github.com/$repository/releases?page=$page", mirror),
                mapOf("Accept" to "text/html,application/xhtml+xml"),
            ).body
            val releases = parseHtmlReleaseHistory(body)
            if (page > 1 && releases.isEmpty()) break
            result += releases
            if (!body.contains("rel=\"next\"")) break
            page += 1
        }
        if (result.isEmpty()) throw IOException("更新历史为空")
        return result.distinctBy { it.version }.sortedWith { left, right ->
            compareVersions(right.version, left.version)
        }
    }

    private suspend fun fetchReleaseHistoryWithFallback(
        mirror: String?,
    ): List<AppReleaseHistoryItem> = try {
        fetchReleaseHistory(mirror)
    } catch (error: IOException) {
        try {
            fetchReleaseHistoryFromHtml(mirror)
        } catch (_: Exception) {
            fetchReleaseHistoryFromAtom(mirror)
        }
    }

    private suspend fun fetchReleaseHistoryFromAtom(
        mirror: String?,
    ): List<AppReleaseHistoryItem> {
        val body = network(
            applyMirror("https://github.com/$repository/releases.atom", mirror),
            mapOf("Accept" to "application/atom+xml"),
        ).body
        val seenVersions = mutableSetOf<String>()
        return parseAndroidAtomReleases(body)
            .mapNotNull { release ->
                if (!seenVersions.add(release.version)) return@mapNotNull null
                AppReleaseHistoryItem(
                    version = release.version,
                    releaseNotes = release.notes,
                    releaseUrl = applyMirror(release.releaseUrl, mirror),
                    publishedAt = release.publishedAt,
                )
            }
            .sortedWith { left, right ->
                compareVersions(right.version, left.version)
            }
    }

    private suspend fun fetchLatestReleaseFromApi(): AvailableRelease {
        val body = network(
            "https://api.github.com/repos/$repository/releases?per_page=100",
            mapOf(
                "Accept" to "application/vnd.github+json",
                "X-GitHub-Api-Version" to "2022-11-28",
            ),
        ).body
        val releases = org.json.JSONArray(body)
        val json = (0 until releases.length())
            .asSequence()
            .map { releases.getJSONObject(it) }
            .filter { it.optString("tag_name").startsWith("android-v") }
            .maxWithOrNull(Comparator { left, right ->
                    compareVersions(
                        left.optString("tag_name").removePrefix("android-").removePrefix("v"),
                        right.optString("tag_name").removePrefix("android-").removePrefix("v"),
                    )
                })
            ?: throw IOException("暂无 Android 发布版本")
        val tag = json.optString("tag_name").removePrefix("android-")
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

    /**
     * Atom 源不含资产列表，按命名约定探测下载地址（优先正式包，再回退 debug 包）。
     */
    private suspend fun fetchLatestReleaseFromAtom(mirror: String): AvailableRelease {
        val body = network(
            applyMirror("https://github.com/$repository/releases.atom", mirror),
            mapOf("Accept" to "application/atom+xml"),
        ).body
        val tag = parseLatestAndroidTag(body)
            ?: throw IOException("暂无 Android 发布版本")
        val version = tag.removePrefix("android-").removePrefix("v").takeIf { it.isNotEmpty() }
            ?: throw IOException("发布版本号无效")
        val assetName = probeAtomAssetName(version, mirror)
            ?: throw IOException("最新发布没有 Android 安装包")
        val downloadUrl = "https://github.com/$repository/releases/download/$tag/$assetName"
        return AvailableRelease(
            version = version,
            notes = "",
            downloadUrl = downloadUrl,
        )
    }

    private suspend fun probeAtomAssetName(version: String, mirror: String): String? {
        val candidates = listOf(
            "MyToken-$version-android.apk",
            "MyToken-$version-android-debug.apk",
        )
        for (name in candidates) {
            val url = applyMirror(
                "https://github.com/$repository/releases/download/android-v$version/$name",
                mirror,
            )
            val status = runCatching { probe(url) }.getOrNull() ?: continue
            if (status in 200..299) return name
        }
        return null
    }

    private suspend fun headStatus(url: String): Int = withContext(Dispatchers.IO) {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "HEAD"
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", "MyToken-Android-Updater")
            connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    private fun parseHtmlReleaseHistory(body: String): List<AppReleaseHistoryItem> {
        val sectionRegex = Regex("<section id=\"release-([^\"]+)\"")
        val matches = sectionRegex.findAll(body).toList()
        return matches.mapIndexedNotNull { index, match ->
            val tagName = match.groupValues[1]
            val version = tagName.takeIf { ANDROID_RELEASE_TAG_REGEX.matches(it) }
                ?.removePrefix("android-v")
                ?: return@mapIndexedNotNull null
            val blockStart = match.range.first
            val blockEnd = matches.getOrNull(index + 1)?.range?.first ?: body.length
            val block = body.substring(blockStart, blockEnd)
            val publishedAt = Regex("datetime=\"([^\"]+)\"")
                .find(block)
                ?.groupValues
                ?.getOrNull(1)
            val notesHtml = extractDivInnerHtml(
                block = block,
                marker = "data-test-selector=\"body-content\"",
            ).orEmpty()
            val notes = Html.fromHtml(notesHtml, Html.FROM_HTML_MODE_LEGACY)
                .toString()
                .trim()
            AppReleaseHistoryItem(
                version = version,
                releaseNotes = notes,
                releaseUrl = "https://github.com/$repository/releases/tag/$tagName",
                publishedAt = publishedAt,
            )
        }
    }

    private fun extractDivInnerHtml(block: String, marker: String): String? {
        val markerIndex = block.indexOf(marker)
        if (markerIndex < 0) return null
        val openingEnd = block.indexOf('>', startIndex = markerIndex)
        if (openingEnd < 0) return null
        val contentStart = openingEnd + 1
        val tokenRegex = Regex("</?div\\b[^>]*>", RegexOption.IGNORE_CASE)
        var depth = 0
        for (match in tokenRegex.findAll(block, contentStart)) {
            val token = match.value
            if (token.startsWith("</")) {
                if (depth == 0) return block.substring(contentStart, match.range.first)
                depth -= 1
            } else if (!token.endsWith("/>")) {
                depth += 1
            }
        }
        return null
    }

    /** 解析 Atom feed 里最新的 android-vX.Y.Z 条目，返回 tag（如 android-v0.0.4）。 */
    private fun parseLatestAndroidTag(body: String): String? =
        parseAndroidAtomReleases(body).firstOrNull()?.let { "android-v${it.version}" }

    private fun parseAndroidAtomReleases(body: String): List<AndroidAtomRelease> {
        val parser = Xml.newPullParser()
        parser.setFeature(org.xmlpull.v1.XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        parser.setInput(body.reader())
        var event = parser.eventType
        var inEntry = false
        var currentText = StringBuilder()
        var version: String? = null
        var releaseUrl: String? = null
        var notes = ""
        var publishedAt: String? = null
        val releases = mutableListOf<AndroidAtomRelease>()
        while (event != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
            when (event) {
                org.xmlpull.v1.XmlPullParser.START_TAG -> {
                    when (parser.name) {
                        "entry" -> {
                            inEntry = true
                            currentText = StringBuilder()
                            version = null
                            releaseUrl = null
                            notes = ""
                            publishedAt = null
                        }
                        "link" -> if (inEntry && parser.getAttributeValue(null, "rel") == "alternate") {
                            releaseUrl = parser.getAttributeValue(null, "href")
                        }
                    }
                    currentText = StringBuilder()
                }
                org.xmlpull.v1.XmlPullParser.TEXT -> if (inEntry) currentText.append(parser.text)
                org.xmlpull.v1.XmlPullParser.END_TAG -> when (parser.name) {
                    "id" -> if (inEntry && version == null) {
                        version = androidVersion(currentText.toString().trim().substringAfterLast('/'))
                    }
                    "title" -> if (inEntry && version == null) {
                        version = Regex("android-v\\d+(?:\\.\\d+)+")
                            .find(currentText.toString().trim())
                            ?.value
                            ?.let(::androidVersion)
                    }
                    "content" -> if (inEntry) notes = currentText.toString().trim()
                    "published", "updated" -> if (inEntry && publishedAt == null) {
                        publishedAt = currentText.toString().trim().takeIf { it.isNotBlank() }
                    }
                    "entry" -> {
                        val currentVersion = version
                        val currentUrl = releaseUrl
                        if (currentVersion != null && currentUrl != null) {
                            releases += AndroidAtomRelease(
                                version = currentVersion,
                                releaseUrl = currentUrl,
                                notes = notes,
                                publishedAt = publishedAt,
                            )
                        }
                        inEntry = false
                    }
                }
            }
            event = parser.next()
        }
        return releases
    }

    private fun androidVersion(tag: String?): String? =
        tag?.takeIf { ANDROID_RELEASE_TAG_REGEX.matches(it) }?.removePrefix("android-v")

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

    private data class AndroidAtomRelease(
        val version: String,
        val releaseUrl: String,
        val notes: String,
        val publishedAt: String?,
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
        private val ANDROID_RELEASE_TAG_REGEX = Regex("^android-v(\\d+(?:\\.\\d+)+)$")
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
