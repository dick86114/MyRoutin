package ai.routin.mytoken

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Smoke test for the Task 9 wiring: the real MainActivity renders the bottom
 * navigation and switches to the credential list and settings screens wired to
 * the real AppGraph dependencies.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class MyTokenAppTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun bottomNavigationSwitchesToCredentialsAndSettings() {
        composeRule.waitForIdle()

        composeRule.onNodeWithText("首页").assertIsDisplayed()
        composeRule.onNodeWithText("凭证").assertIsDisplayed()
        composeRule.onNodeWithText("设置").assertIsDisplayed()

        composeRule.onNodeWithText("凭证").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("搜索凭证").assertIsDisplayed()

        composeRule.onNodeWithText("设置").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("刷新").assertIsDisplayed()

        // The 通知 section (Task 10) pushed 数据迁移 below the fold; scroll to it.
        repeat(4) {
            composeRule.onNodeWithTag("settings_list").performTouchInput { swipeUp() }
            composeRule.waitForIdle()
        }
        composeRule.onNodeWithText("从 Mac 导入").assertIsDisplayed()
    }
}
