package ai.routin.mytoken.widget

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf

/** User-initiated widget refreshes reuse the app's single background refresh delegate. */
internal object WidgetRefresher {

    const val ACTION_REFRESH = "ai.routin.mytoken.action.WIDGET_REFRESH"
    const val EXTRA_WIDGET_ID = "appWidgetId"
    private const val UNIQUE_WORK_NAME = "mytoken-widget-refresh"

    fun refreshPendingIntent(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, CredentialWidgetProvider::class.java)
            .setAction(ACTION_REFRESH)
            .putExtra(EXTRA_WIDGET_ID, appWidgetId)
        return PendingIntent.getBroadcast(
            context,
            appWidgetId + 200_000,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun enqueue(context: Context, appWidgetId: Int) {
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInputData(workDataOf(EXTRA_WIDGET_ID to appWidgetId))
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            "$UNIQUE_WORK_NAME-$appWidgetId",
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }
}
