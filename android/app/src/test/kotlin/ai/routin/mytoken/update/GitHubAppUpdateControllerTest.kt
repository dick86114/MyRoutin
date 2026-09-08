package ai.routin.mytoken.update

import ai.routin.mytoken.data.preferences.AppPreferencesRepository
import ai.routin.mytoken.feature.settings.AppUpdateUiState
import androidx.test.core.app.ApplicationProvider
import java.io.IOException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
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
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val preferences = AppPreferencesRepository(context)
        preferences.setUpdateMirrorBase("https://ghfast.top")
        val requested = mutableListOf<String>()
        val controller = GitHubAppUpdateController(
            context = context,
            currentVersionName = "0.0.1",
            preferences = preferences,
            network = { url, _ ->
                requested.add(url)
                if (url.startsWith("https://api.github.com")) throw IOException("blocked")
                UpdateResponse(atom)
            },
            probeStatus = { _ -> 200 },
        )

        controller.checkForUpdates()
        val state = withTimeout(5_000) {
            controller.state.first { it !is AppUpdateUiState.Checking }
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
}
