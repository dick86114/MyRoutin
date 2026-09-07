package ai.routin.mytoken.core.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

/**
 * The three notification channels, mirroring the macOS notification groups:
 * usage threshold alerts, credential errors, and system-level reminders.
 * Channels are created no-ops below API 26 (minSdk is 29, so always supported).
 */
object NotificationChannels {

    const val USAGE_ALERTS_ID = "usage_alerts"
    const val CREDENTIAL_ERRORS_ID = "credential_errors"
    const val SYSTEM_REMINDERS_ID = "system_reminders"

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        createChannel(
            manager = manager,
            id = USAGE_ALERTS_ID,
            name = "用量提醒",
            description = "用量达到阈值或余额异常时提醒",
            importance = NotificationManager.IMPORTANCE_HIGH,
        )
        createChannel(
            manager = manager,
            id = CREDENTIAL_ERRORS_ID,
            name = "凭证错误",
            description = "凭证失效或后台刷新持续失败时提醒",
            importance = NotificationManager.IMPORTANCE_DEFAULT,
        )
        createChannel(
            manager = manager,
            id = SYSTEM_REMINDERS_ID,
            name = "系统提醒",
            description = "应用维护与系统级提醒",
            importance = NotificationManager.IMPORTANCE_LOW,
        )
    }

    private fun createChannel(
        manager: NotificationManager,
        id: String,
        name: String,
        description: String,
        importance: Int,
    ) {
        manager.createNotificationChannel(
            NotificationChannel(id, name, importance).apply { this.description = description },
        )
    }
}
