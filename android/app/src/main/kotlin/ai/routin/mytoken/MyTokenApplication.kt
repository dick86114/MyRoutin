package ai.routin.mytoken

import ai.routin.mytoken.core.notifications.NotificationChannels
import ai.routin.mytoken.core.refresh.RefreshScheduling
import ai.routin.mytoken.core.refresh.RefreshWorker
import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Application-scoped graph + background refresh scheduling. The worker's delegate
 * is provided from here so a cold background process can refresh without an
 * Activity; notification channels are ensured at process start (Android 10+).
 */
class MyTokenApplication : Application() {

    val graph: AppGraph by lazy { AppGraph(this) }

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()

        NotificationChannels.ensureChannels(this)
        RefreshWorker.delegateProvider = { AppBackgroundRefreshDelegate(graph) }

        // Keep the periodic WorkManager schedule in sync with the refresh settings.
        appScope.launch {
            graph.refreshSettingsStore.settings
                .map { settings ->
                    RefreshScheduling.plan(
                        autoRefreshEnabled = settings.autoRefreshEnabled,
                        refreshIntervalMinutes = settings.refreshIntervalMinutes,
                        wifiOnly = settings.wifiOnly,
                        retryOnFailure = settings.retryOnFailure,
                    )
                }
                .distinctUntilChanged()
                .collect { plan ->
                    // WorkManager may be unavailable in restricted test environments;
                    // scheduling failure must never crash the app process.
                    runCatching { RefreshScheduling.apply(this@MyTokenApplication, plan) }
                }
        }
    }
}
