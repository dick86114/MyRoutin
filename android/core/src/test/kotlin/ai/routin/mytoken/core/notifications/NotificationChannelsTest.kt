package ai.routin.mytoken.core.notifications

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NotificationChannelsTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun ensureChannelsCreatesTheThreeChannels() {
        NotificationChannels.ensureChannels(context)

        val manager = context.getSystemService(NotificationManager::class.java)
        val usage = manager.getNotificationChannel(NotificationChannels.USAGE_ALERTS_ID)
        val errors = manager.getNotificationChannel(NotificationChannels.CREDENTIAL_ERRORS_ID)
        val system = manager.getNotificationChannel(NotificationChannels.SYSTEM_REMINDERS_ID)

        assertNotNull(usage)
        assertNotNull(errors)
        assertNotNull(system)

        assertEquals(NotificationManager.IMPORTANCE_HIGH, usage.importance)
        assertEquals("用量提醒", usage.name)
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, errors.importance)
        assertEquals("凭证错误", errors.name)
        assertEquals(NotificationManager.IMPORTANCE_LOW, system.importance)
        assertEquals("系统提醒", system.name)
    }

    @Test
    fun ensureChannelsIsIdempotent() {
        NotificationChannels.ensureChannels(context)
        NotificationChannels.ensureChannels(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        assertEquals(3, manager.notificationChannels.size)
    }
}
