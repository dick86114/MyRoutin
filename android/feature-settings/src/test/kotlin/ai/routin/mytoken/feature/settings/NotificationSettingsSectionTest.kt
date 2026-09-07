package ai.routin.mytoken.feature.settings

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Robolectric Compose rendering of the 通知 settings section (Task 10). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NotificationSettingsSectionTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun rendersTogglesAndDefaultThresholds() {
        composeRule.setContent {
            MaterialTheme {
                NotificationSettingsSection(
                    settings = NotificationSettings(),
                    permissionGranted = true,
                    onRequestPermission = {},
                    onNotificationsEnabledChange = {},
                    onCredentialFailureAlertsChange = {},
                    onLowThresholdChange = {},
                    onHighThresholdChange = {},
                )
            }
        }

        composeRule.onNodeWithText("通知").assertIsDisplayed()
        composeRule.onNodeWithText("启用提醒").assertIsDisplayed()
        composeRule.onNodeWithText("用量提醒低阈值").assertIsDisplayed()
        composeRule.onNodeWithText("50%").assertIsDisplayed()
        composeRule.onNodeWithText("用量提醒高阈值").assertIsDisplayed()
        composeRule.onNodeWithText("80%").assertIsDisplayed()
        composeRule.onNodeWithText("凭证失效提醒").assertIsDisplayed()
        composeRule.onNodeWithText("系统通知权限：已允许").assertIsDisplayed()
        composeRule.onNodeWithText("去授权").assertDoesNotExist()
    }

    @Test
    fun thresholdSteppersEmitChanges() {
        var lowChange = 0
        var highChange = 0
        composeRule.setContent {
            MaterialTheme {
                NotificationSettingsSection(
                    settings = NotificationSettings(),
                    permissionGranted = true,
                    onRequestPermission = {},
                    onNotificationsEnabledChange = {},
                    onCredentialFailureAlertsChange = {},
                    onLowThresholdChange = { lowChange = it },
                    onHighThresholdChange = { highChange = it },
                )
            }
        }

        composeRule.onNodeWithContentDescription("用量提醒低阈值 减少").performClick()
        assertEquals(45, lowChange)
        composeRule.onNodeWithContentDescription("用量提醒高阈值 增加").performClick()
        assertEquals(85, highChange)
    }

    @Test
    fun deniedPermissionShowsStatusAndAuthorizationEntry() {
        var requested = 0
        composeRule.setContent {
            MaterialTheme {
                NotificationSettingsSection(
                    settings = NotificationSettings(),
                    permissionGranted = false,
                    onRequestPermission = { requested++ },
                    onNotificationsEnabledChange = {},
                    onCredentialFailureAlertsChange = {},
                    onLowThresholdChange = {},
                    onHighThresholdChange = {},
                )
            }
        }

        composeRule.onNodeWithText("系统通知权限：未授予，提醒将静默").assertIsDisplayed()
        composeRule.onNodeWithText("去授权").performClick()
        assertEquals(1, requested)
    }

    @Test
    fun togglesEmitChanges() {
        var notificationsEnabled: Boolean? = null
        var failureAlerts: Boolean? = null
        composeRule.setContent {
            MaterialTheme {
                NotificationSettingsSection(
                    settings = NotificationSettings(),
                    permissionGranted = true,
                    onRequestPermission = {},
                    onNotificationsEnabledChange = { notificationsEnabled = it },
                    onCredentialFailureAlertsChange = { failureAlerts = it },
                    onLowThresholdChange = {},
                    onHighThresholdChange = {},
                )
            }
        }

        composeRule.onNodeWithContentDescription("启用提醒").performClick()
        composeRule.onNodeWithContentDescription("凭证失效提醒").performClick()
        assertFalse(notificationsEnabled!!)
        assertFalse(failureAlerts!!)
    }
}
