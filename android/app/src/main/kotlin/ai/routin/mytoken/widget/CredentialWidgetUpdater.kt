package ai.routin.mytoken.widget

import ai.routin.mytoken.AppGraph
import ai.routin.mytoken.R
import ai.routin.mytoken.domain.usage.RefreshStatus
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import kotlinx.coroutines.flow.first

/** Renders every existing home-screen widget from its persisted credential selection. */
internal object CredentialWidgetUpdater {

    suspend fun updateAll(context: Context, graph: AppGraph) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val ids = manager.getAppWidgetIds(ComponentName(appContext, CredentialWidgetProvider::class.java))
        ids.forEach { update(appContext, graph, manager, it) }
    }

    suspend fun update(context: Context, graph: AppGraph, appWidgetId: Int) {
        val appContext = context.applicationContext
        update(appContext, graph, AppWidgetManager.getInstance(appContext), appWidgetId)
    }

    private suspend fun update(
        context: Context,
        graph: AppGraph,
        manager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val store = WidgetSelectionStore(context)
        val credentialId = store.selectedCredentialId(appWidgetId) ?: run {
            manager.updateAppWidget(
                appWidgetId,
                CredentialWidgetRenderer.render(
                    context = context,
                    appWidgetId = appWidgetId,
                    credential = null,
                    snapshot = null,
                    statusText = "尚未选择凭证",
                ),
            )
            manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_metrics)
            return
        }
        val credential = graph.credentialRepository.observeCredentials().first().firstOrNull { it.id == credentialId }
        val snapshot = runCatching { graph.credentialRepository.cachedSnapshot(credentialId) }.getOrNull()
        val usageState = graph.refreshUseCase.states.value[credentialId]
        val statusText = when {
            usageState?.status == RefreshStatus.Loading -> "正在加载"
            usageState?.status == RefreshStatus.Disabled -> "凭证已停用 · 显示缓存数据"
            usageState?.status == RefreshStatus.Failed -> {
                val reason = usageState.error?.message ?: "更新失败"
                if (snapshot == null) "更新失败 · $reason" else "更新失败 · $reason · 显示上次成功数据"
            }
            usageState?.isStale == true && snapshot != null ->
                "显示上次成功数据 · 更新于 ${formatTime(snapshot.fetchedAt)}"
            snapshot == null -> "尚未成功更新"
            else -> "更新于 ${formatTime(snapshot.fetchedAt)}"
        }
        val views = CredentialWidgetRenderer.render(
            context = context,
            appWidgetId = appWidgetId,
            credential = credential,
            snapshot = snapshot,
            statusText = statusText,
        )
        manager.updateAppWidget(appWidgetId, views)
        manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_metrics)
    }

    private fun formatTime(instant: java.time.Instant): String =
        java.time.format.DateTimeFormatter.ofPattern("HH:mm")
            .format(instant.atZone(java.time.ZoneId.systemDefault()))
}
