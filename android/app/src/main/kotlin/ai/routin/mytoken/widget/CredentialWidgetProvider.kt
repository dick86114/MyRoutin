package ai.routin.mytoken.widget

import ai.routin.mytoken.MyTokenApplication
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class CredentialWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val graph = (context.applicationContext as MyTokenApplication).graph
                kotlinx.coroutines.withTimeout(15_000L) {
                    CredentialWidgetUpdater.updateAll(context, graph)
                }
            } catch (_: Exception) {
                // 超时保护：系统会在下次 APPWIDGET_UPDATE 时重试
            } finally {
                pendingResult.finish()
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WidgetRefresher.ACTION_REFRESH) {
            WidgetRefresher.enqueue(
                context,
                intent.getIntExtra(
                    WidgetRefresher.EXTRA_WIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                ),
            )
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val store = WidgetSelectionStore(context)
        appWidgetIds.forEach(store::remove)
    }
}
