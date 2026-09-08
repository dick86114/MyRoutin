package ai.routin.mytoken

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
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

        composeRule.onNodeWithContentDescription("首页").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("凭证").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("设置").assertIsDisplayed()

        composeRule.onNodeWithContentDescription("凭证").performClick()
        composeRule.waitForIdle()
        composeRule.onAllNodesWithText("凭证")[0].assertIsDisplayed()

        composeRule.onNodeWithContentDescription("设置").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("刷新").assertIsDisplayed()

        // The notification section pushes transfer below the fold.
        composeRule.onNodeWithTag("settings_list").performScrollToNode(
            hasText("从 Mac 导入"),
        )
    }
}
