package ai.routin.mytoken.core.refresh

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/** Outcome of one full background refresh pass. */
enum class RefreshOutcome { Succeeded, Failed }

/**
 * Performs the actual background refresh. Implemented in the app module so the
 * worker (in :core) can stay free of repository/provider wiring; the app supplies
 * the same shared [ai.routin.mytoken.domain.usage.RefreshCredentialsUseCase] the
 * foreground uses, so concurrent in-app refreshes never duplicate requests.
 */
fun interface BackgroundRefreshDelegate {
    suspend fun refreshAll(): RefreshOutcome
}

/** Persists the last successful / failed refresh timestamps (DataStore-backed in :data). */
interface RefreshStatusStore {
    suspend fun recordSuccess(attemptAtEpochMillis: Long)
    suspend fun recordFailure(attemptAtEpochMillis: Long)
}

enum class RetryDecision { Retry, GiveUp }

/** Failure handling: honor the user's retryOnFailure preference. */
object RefreshRetryPolicy {
    fun decide(retryOnFailure: Boolean): RetryDecision =
        if (retryOnFailure) RetryDecision.Retry else RetryDecision.GiveUp
}

/**
 * Periodic background refresh. The delegate is injected via [delegateProvider] by
 * the Application at process start, so the worker works in a cold background
 * process without a DI framework. No foreground/persistent service is involved.
 */
class RefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val delegate = delegateProvider?.invoke() ?: return Result.failure()
        return when (delegate.refreshAll()) {
            RefreshOutcome.Succeeded -> Result.success()
            RefreshOutcome.Failed -> when (
                RefreshRetryPolicy.decide(inputData.getBoolean(KEY_RETRY_ON_FAILURE, true))
            ) {
                RetryDecision.Retry -> Result.retry()
                RetryDecision.GiveUp -> Result.success()
            }
        }
    }

    companion object {
        const val KEY_RETRY_ON_FAILURE = "retryOnFailure"

        /** Set by MyTokenApplication before any worker can run. */
        @Volatile
        var delegateProvider: (() -> BackgroundRefreshDelegate?)? = null
    }
}

data class RefreshWorkPlan(
    val intervalMinutes: Long,
    val requireUnmetered: Boolean,
    val retryOnFailure: Boolean,
    val requireBatteryNotLow: Boolean,
)

/**
 * Translates refresh preferences into a periodic WorkManager schedule.
 * Pure decision logic ([plan]) is JVM-testable; WorkManager calls are isolated
 * in [buildRequest] / [apply].
 */
object RefreshScheduling {

    const val UNIQUE_WORK_NAME = "mytoken-background-refresh"

    /** WorkManager refuses periodic intervals below 15 minutes; shorter settings clamp up. */
    const val MIN_PERIODIC_INTERVAL_MINUTES = 15L

    /**
     * Settings intervals at/above this value also wait for a battery that is not low;
     * shorter intervals skip the constraint (explicit low-battery policy, see [plan]).
     */
    const val BATTERY_CONSTRAINT_MIN_INTERVAL_MINUTES = 15

    /**
     * Returns the plan for the given settings, or `null` when background refresh is
     * disabled (the caller must cancel the enqueued work).
     */
    fun plan(
        autoRefreshEnabled: Boolean,
        refreshIntervalMinutes: Int,
        wifiOnly: Boolean,
        retryOnFailure: Boolean,
    ): RefreshWorkPlan? {
        if (!autoRefreshEnabled) return null
        return RefreshWorkPlan(
            intervalMinutes = maxOf(MIN_PERIODIC_INTERVAL_MINUTES, refreshIntervalMinutes.toLong()),
            requireUnmetered = wifiOnly,
            retryOnFailure = retryOnFailure,
            // Low-battery policy: at the standard 15/30-minute cadence the refresh waits
            // for a battery that is not low; short intervals (1/5 min, already clamped to
            // 15 for scheduling) keep refreshing on low battery so users who explicitly
            // asked for near-real-time monitoring are not silently starved.
            requireBatteryNotLow = refreshIntervalMinutes >= BATTERY_CONSTRAINT_MIN_INTERVAL_MINUTES,
        )
    }

    fun buildRequest(plan: RefreshWorkPlan): PeriodicWorkRequest {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(
                if (plan.requireUnmetered) NetworkType.UNMETERED else NetworkType.CONNECTED,
            )
            .setRequiresBatteryNotLow(plan.requireBatteryNotLow)
            .build()
        return PeriodicWorkRequestBuilder<RefreshWorker>(plan.intervalMinutes, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .setInputData(workDataOf(RefreshWorker.KEY_RETRY_ON_FAILURE to plan.retryOnFailure))
            .build()
    }

    /**
     * Applies the plan: (re)enqueues the unique periodic work with UPDATE semantics —
     * scheduling drift is left to the OS. A `null` plan cancels background refresh.
     */
    fun apply(context: Context, plan: RefreshWorkPlan?) {
        val workManager = WorkManager.getInstance(context)
        if (plan == null) {
            workManager.cancelUniqueWork(UNIQUE_WORK_NAME)
            return
        }
        workManager.enqueueUniquePeriodicWork(
            UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            buildRequest(plan),
        )
    }
}
