package ai.routin.mytoken.widget

import ai.routin.mytoken.MyTokenApplication
import ai.routin.mytoken.domain.usage.RefreshStatus
import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.flow.first

/** Refreshes only the credential selected by one home-screen widget instance. */
class WidgetRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val appWidgetId = inputData.getInt(
            WidgetRefresher.EXTRA_WIDGET_ID,
            -1,
        )
        if (appWidgetId < 0) return Result.failure()

        val graph = (applicationContext as MyTokenApplication).graph
        val credentialId = WidgetSelectionStore(applicationContext)
            .selectedCredentialId(appWidgetId)
            ?: return Result.failure()
        val credential = graph.credentialRepository.observeCredentials()
            .first()
            .firstOrNull { it.id == credentialId }
            ?: return Result.failure()

        graph.refreshUseCase.refresh(credential)
        val status = graph.refreshUseCase.states.value[credentialId]?.status
        CredentialWidgetUpdater.update(applicationContext, graph, appWidgetId)
        return if (status == RefreshStatus.Ready) Result.success() else Result.failure()
    }
}
