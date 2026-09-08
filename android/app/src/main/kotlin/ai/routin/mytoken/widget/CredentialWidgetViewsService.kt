package ai.routin.mytoken.widget

import ai.routin.mytoken.MyTokenApplication
import ai.routin.mytoken.MainActivity
import ai.routin.mytoken.R
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

class CredentialWidgetViewsService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        CredentialWidgetViewsFactory(
            context = applicationContext,
            appWidgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                intent.getIntExtra(WidgetRefresher.EXTRA_WIDGET_ID, -1),
            ),
        )

    companion object {
        private const val ACTION_BIND = "ai.routin.mytoken.action.BIND_CREDENTIAL_WIDGET"
        private const val URI_BASE = "mytoken://credential-widget"

        /**
         * The data URI is required: extras are not part of Intent.filterEquals, so
         * two widgets can otherwise be handed the same cached RemoteViewsFactory.
         */
        fun bindIntent(context: android.content.Context, appWidgetId: Int): Intent =
            Intent(context, CredentialWidgetViewsService::class.java)
                .setAction(ACTION_BIND)
                .setData(Uri.withAppendedPath(Uri.parse(URI_BASE), appWidgetId.toString()))
                .putExtra(WidgetRefresher.EXTRA_WIDGET_ID, appWidgetId)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
    }
}

internal class CredentialWidgetViewsFactory(
    private val context: android.content.Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {

    private data class ListState(
        val credentialId: java.util.UUID? = null,
        val items: List<WidgetMetricDisplay> = emptyList(),
    )

    private var state = ListState()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val graph = (context.applicationContext as MyTokenApplication).graph
        val credentialId = WidgetSelectionStore(context)
            .selectedCredentialId(appWidgetId)
            ?: return
        val credential = runBlocking {
            graph.credentialRepository.observeCredentials().first().firstOrNull { it.id == credentialId }
        } ?: return
        val snapshot = runBlocking {
            runCatching { graph.credentialRepository.cachedSnapshot(credentialId) }.getOrNull()
        }
        val safeSnapshot = snapshot?.takeIf { it.credentialId == credential.id }
        state = ListState(
            credentialId = credential.id,
            items = CredentialWidgetRenderer.displayItems(credential.providerId, safeSnapshot),
        )
    }

    override fun onDestroy() {
        state = ListState()
    }

    override fun getCount(): Int = state.items.size

    override fun getViewAt(position: Int): RemoteViews {
        val item = state.items.getOrNull(position)
            ?: WidgetMetricDisplay(label = "", value = "", detail = "")
        val views = CredentialWidgetRenderer.metricItemViews(context, item)
        state.credentialId?.let { credentialId ->
            views.setOnClickFillInIntent(
                R.id.widget_metric_item,
                Intent().putExtra(MainActivity.EXTRA_CREDENTIAL_ID, credentialId.toString()),
            )
        }
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}
