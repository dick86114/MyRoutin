package ai.routin.mytoken.update

import ai.routin.mytoken.feature.settings.AppUpdateUiState
import ai.routin.mytoken.feature.settings.AppReleaseHistoryUiState
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.IOException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class GitHubAppUpdateControllerTest {

    private val atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/android-v0.0.9</id>
            <updated>2026-09-08T12:00:00Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/android-v0.0.9" />
            <title>MyToken Android v0.0.9</title>
          </entry>
        </feed>
    """.trimIndent()

    @Test
    fun cdn模式下API失败走镜像Atom并改写下载地址() = runBlocking {
        val requested = mutableListOf<String>()
        val controller = GitHubAppUpdateController(
            context = ApplicationProvider.getApplicationContext<Context>(),
            currentVersionName = "0.0.1",
            mirrorBaseProvider = { "https://ghfast.top" },
            network = { url, _ ->
                requested.add(url)
                if (url.startsWith("https://api.github.com")) throw IOException("blocked")
                UpdateResponse(atom)
            },
            probeStatus = { _ -> 200 },
        )

        controller.checkForUpdates()
        val state = withTimeout(5_000) {
            // 等终态而不是“非 Checking”：checkForUpdates 异步启动时状态仍是 Idle，
            // “非 Checking”会立即匹配到 Idle 造成竞态（CI 上必然复现）。
            controller.state.first {
                it is AppUpdateUiState.Available ||
                    it is AppUpdateUiState.Error ||
                    it is AppUpdateUiState.UpToDate
            }
        }

        assertTrue(
            "requests=$requested",
            requested.any { it.startsWith("https://ghfast.top/https://github.com/") },
        )
        assertTrue(state is AppUpdateUiState.Available)
        val available = state as AppUpdateUiState.Available
        assertTrue(available.downloadUrl.startsWith("https://ghfast.top/https://github.com/"))
        assertTrue(available.downloadUrl.endsWith("MyToken-0.0.9-android.apk"))
    }

    @Test
    fun 历史版本只保留Android发布并按版本倒序去重() = runBlocking {
        val body = """
        [
          {"tag_name":"android-v0.0.8","html_url":"https://github.com/dick86114/MyToken/releases/tag/android-v0.0.8","body":"旧版本","published_at":"2026-08-01T10:00:00Z"},
          {"tag_name":"macos-v0.0.9","html_url":"https://github.com/dick86114/MyToken/releases/tag/macos-v0.0.9","body":"macOS","published_at":"2026-09-08T12:00:00Z"},
          {"tag_name":"android-v0.0.9","html_url":"https://github.com/dick86114/MyToken/releases/tag/android-v0.0.9","body":"新版本","published_at":"2026-09-09T12:00:00Z"},
          {"tag_name":"android-v0.0.9","html_url":"https://github.com/dick86114/MyToken/releases/tag/android-v0.0.9-copy","body":"重复版本","published_at":"2026-09-10T12:00:00Z"}
        ]
        """.trimIndent()
        val controller = GitHubAppUpdateController(
            context = ApplicationProvider.getApplicationContext<Context>(),
            currentVersionName = "0.0.9",
            network = { _, _ -> UpdateResponse(body) },
        )

        controller.loadReleaseHistory()
        val state = withTimeout(5_000) {
            controller.releaseHistoryState.first { it is AppReleaseHistoryUiState.Loaded }
        } as AppReleaseHistoryUiState.Loaded

        assertEquals(listOf("0.0.9", "0.0.8"), state.releases.map { it.version })
        assertEquals("新版本", state.releases.first().releaseNotes)
        assertFalse(state.releases.any { it.releaseNotes == "macOS" })
    }

    @Test
    fun 历史版本在API限流时回退到AtomFeed() = runBlocking {
        val historyAtom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/android-v0.0.9</id>
            <updated>2026-09-09T12:00:00Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/android-v0.0.9" />
            <title>MyToken Android v0.0.9</title>
            <content type="html">&lt;p&gt;当前版本&lt;/p&gt;</content>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1/android-v0.0.8</id>
            <updated>2026-08-01T10:00:00Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/android-v0.0.8" />
            <title>MyToken Android v0.0.8</title>
            <content type="html">&lt;p&gt;旧版本&lt;/p&gt;</content>
          </entry>
        </feed>
        """.trimIndent()
        val controller = GitHubAppUpdateController(
            context = ApplicationProvider.getApplicationContext<Context>(),
            currentVersionName = "0.0.9",
            network = { url, _ ->
                if (url.startsWith("https://api.github.com")) throw IOException("rate limited")
                UpdateResponse(historyAtom)
            },
        )

        controller.loadReleaseHistory()
        val state = withTimeout(5_000) {
            controller.releaseHistoryState.first { it is AppReleaseHistoryUiState.Loaded }
        } as AppReleaseHistoryUiState.Loaded

        assertEquals(listOf("0.0.9", "0.0.8"), state.releases.map { it.version })
        assertEquals("<p>当前版本</p>", state.releases.first().releaseNotes)
    }
}
