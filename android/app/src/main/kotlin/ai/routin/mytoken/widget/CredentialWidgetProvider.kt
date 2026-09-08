package ai.routin.mytoken.widget

import ai.routin.mytoken.MyTokenApplication
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
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
                runCatching {
                    // 兜底渲染：即使 AppGraph 初始化失败也要显示引导
                    val manager = AppWidgetManager.getInstance(context)
                    val ids = manager.getAppWidgetIds(
                        ComponentName(context, CredentialWidgetProvider::class.java)
                    )
                    ids.forEach { id ->
                        manager.updateAppWidget(
                            id,
                            CredentialWidgetRenderer.render(
                                context = context,
                                appWidgetId = id,
                                credential = null,
                                snapshot = null,
                                statusText = "打开应用后重试",
                                items = emptyList(),
                            ),
                        )
                    }
                }
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
