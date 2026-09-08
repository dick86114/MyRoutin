package ai.routin.mytoken

import android.Manifest
import android.app.NotificationManager
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.lifecycle.Lifecycle
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The Settings page notification-permission status must be reactive: toggling
 * notification availability (what a POST_NOTIFICATIONS revocation causes on real
 * devices) and returning to the app (ON_STOP → ON_RESTART → ON_RESUME, no activity
 * recreation) updates the visible status.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class MainActivityNotificationPermissionTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private fun toggleNotifications(activity: MainActivity, enabled: Boolean) {
        val manager = activity.getSystemService(NotificationManager::class.java)
        shadowOf(manager).setNotificationsEnabled(enabled)
        // Real devices also drop the runtime permission when notifications are disabled.
        if (enabled) {
            shadowOf(activity).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            shadowOf(activity).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun relaunchThroughLifecycle() {
        val scenario = composeRule.activityRule.scenario
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.moveToState(Lifecycle.State.RESUMED)
    }

    private fun openSettingsAndScrollToPermissionStatus() {
        composeRule.waitForIdle()
        composeRule.onNodeWithContentDescription("设置").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("settings_list").performScrollToNode(
            hasText("系统通知权限：已允许"),
        )
    }

    @Test
    fun permissionStatusUpdatesOnLifecycleResume() {
        composeRule.activityRule.scenario.onActivity { toggleNotifications(it, enabled = true) }
        openSettingsAndScrollToPermissionStatus()
        composeRule.onNodeWithText("系统通知权限：已允许").assertIsDisplayed()

        // Simulate revocation in system settings + return to the app.
        composeRule.activityRule.scenario.onActivity { toggleNotifications(it, enabled = false) }
        relaunchThroughLifecycle()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("系统通知权限：未授予，提醒将静默").assertIsDisplayed()

        // Re-granting reflects again on the next resume.
        composeRule.activityRule.scenario.onActivity { toggleNotifications(it, enabled = true) }
        relaunchThroughLifecycle()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("系统通知权限：已允许").assertIsDisplayed()
    }
}
