package ai.routin.mytoken.feature.settings

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class SettingsScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val refreshStore = FakeRefreshSettingsStore()
    private val displayStore = FakeDisplaySettingsStore()

    private fun setContent(onOpenTransfer: () -> Unit = {}) {
        val releaseHistoryState = AppReleaseHistoryUiState.Loaded(
            listOf(
                AppReleaseHistoryItem(
                    version = "0.1.0",
                    releaseNotes = "当前版本修复内容",
                    releaseUrl = "https://example.com/0.1.0",
                    publishedAt = "2026-09-11T00:00:00Z",
                ),
                AppReleaseHistoryItem(
                    version = "0.0.9",
                    releaseNotes = "历史版本修复内容",
                    releaseUrl = "https://example.com/0.0.9",
                    publishedAt = "2026-09-01T00:00:00Z",
                ),
            ),
        )
        composeRule.setContent {
            MaterialTheme {
                SettingsScreen(
                    state = SettingsUiState(
                        isLoading = false,
                        refresh = refreshStore.state.value,
                        display = displayStore.state.value,
                    ),
                    appVersion = "0.1.0",
                    releaseHistoryState = releaseHistoryState,
                    onAutoRefreshChange = { refreshStore.state.value = refreshStore.state.value.copy(autoRefreshEnabled = it) },
                    onIntervalChange = { refreshStore.state.value = refreshStore.state.value.copy(refreshIntervalMinutes = it) },
                    onWifiOnlyChange = { refreshStore.state.value = refreshStore.state.value.copy(wifiOnly = it) },
                    onOpenAppRefreshChange = { refreshStore.state.value = refreshStore.state.value.copy(openAppRefresh = it) },
                    onRetryOnFailureChange = { refreshStore.state.value = refreshStore.state.value.copy(retryOnFailure = it) },
                    onThemeModeChange = { displayStore.state.value = displayStore.state.value.copy(themeMode = it) },
                    onOpenTransfer = onOpenTransfer,
                )
            }
        }
    }

    @Test
    fun rendersRefreshAndDisplaySections() {
        setContent()

        composeRule.onNodeWithText("刷新").assertIsDisplayed()
        composeRule.onNodeWithText("自动刷新").assertIsDisplayed()
        composeRule.onNodeWithText("5分钟").assertIsDisplayed()
        composeRule.onNodeWithText("15分钟").assertIsDisplayed()
        composeRule.onNodeWithText("打开应用时刷新").assertIsDisplayed()
    }

    @Test
    fun intervalChipsReflectCurrentSelection() {
        setContent()

        composeRule.onNodeWithText("15分钟").assertIsSelected()
    }

    @Test
    fun intervalChipClickUpdatesSelection() {
        setContent()

        composeRule.onNodeWithText("5分钟").performClick()
        composeRule.waitUntil(5_000) { refreshStore.state.value.refreshIntervalMinutes == 5 }

        assertEquals(5, refreshStore.state.value.refreshIntervalMinutes)
    }

    @Test
    fun switchInteractionPersists() {
        setContent()

        composeRule.onNodeWithContentDescription("自动刷新").performClick()
        composeRule.waitUntil(5_000) { !refreshStore.state.value.autoRefreshEnabled }

        assertFalse(refreshStore.state.value.autoRefreshEnabled)
    }

    @Test
    fun migrationEntryInvokesCallback() {
        var opened = 0
        setContent(onOpenTransfer = { opened++ })

        // The 通知 section (Task 10) pushed 数据迁移 below the fold; scroll to it.
        repeat(4) {
            composeRule.onNodeWithTag("settings_list").performTouchInput { swipeUp() }
            composeRule.waitForIdle()
        }
        composeRule.onNodeWithText("从 Mac 导入").assertIsDisplayed()
        composeRule.onNodeWithText("从 Mac 导入").performClick()

        assertEquals(1, opened)
    }

    @Test
    fun aboutSectionShowsVersionAndHelpWithoutMacOnlyOptions() {
        setContent()

        // Scroll the (lazy) settings list down until the 关于 section is composed.
        repeat(4) {
            composeRule.onNodeWithTag("settings_list").performTouchInput { swipeUp() }
            composeRule.waitForIdle()
        }
        composeRule.onNodeWithText("关于").assertIsDisplayed()
        composeRule.onNodeWithText("MyToken 0.1.0", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("GitHub").assertIsDisplayed()
        composeRule.onNodeWithText("当前版本更新日志").assertIsDisplayed()
        composeRule.onNodeWithText("当前版本修复内容").assertIsDisplayed()

        composeRule.onNodeWithTag("release_history_button").performClick()
        composeRule.onNodeWithText("历史版本更新日志").assertIsDisplayed()
        composeRule.onNodeWithText("历史版本修复内容").assertIsDisplayed()

        // macOS-only settings must not appear on Android.
        composeRule.onNodeWithText("菜单栏").assertDoesNotExist()
        composeRule.onNodeWithText("登录项").assertDoesNotExist()
        assertTrue(displayStore.state.value.showDisabledCredentials)
    }
}
