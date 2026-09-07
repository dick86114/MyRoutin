package ai.routin.mytoken.core.refresh

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.NetworkType
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RefreshSchedulingTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    // ---- plan() (pure decision logic) ---------------------------------------

    @Test
    fun planIsNullWhenAutoRefreshDisabled() {
        val plan = RefreshScheduling.plan(
            autoRefreshEnabled = false,
            refreshIntervalMinutes = 15,
            wifiOnly = false,
            retryOnFailure = true,
        )
        assertNull(plan)
    }

    @Test
    fun shortIntervalsClampToWorkManagerMinimum() {
        // WorkManager refuses periodic work below 15 minutes; 1/5-minute settings clamp up.
        listOf(1, 5, 15).forEach { minutes ->
            val plan = RefreshScheduling.plan(true, minutes, wifiOnly = false, retryOnFailure = true)
            assertEquals(RefreshScheduling.MIN_PERIODIC_INTERVAL_MINUTES, plan!!.intervalMinutes)
        }
        val plan = RefreshScheduling.plan(true, 30, wifiOnly = false, retryOnFailure = true)
        assertEquals(30L, plan!!.intervalMinutes)
    }

    @Test
    fun planCarriesWifiOnlyAndRetryFlags() {
        val plan = RefreshScheduling.plan(true, 15, wifiOnly = true, retryOnFailure = false)
        assertTrue(plan!!.requireUnmetered)
        assertEquals(false, plan.retryOnFailure)
    }

    // ---- explicit low-battery policy -----------------------------------------

    @Test
    fun standardIntervalsRequireBatteryNotLow() {
        // 15/30-minute cadences wait for a battery that is not low.
        assertTrue(RefreshScheduling.plan(true, 15, wifiOnly = false, retryOnFailure = true)!!.requireBatteryNotLow)
        assertTrue(RefreshScheduling.plan(true, 30, wifiOnly = false, retryOnFailure = true)!!.requireBatteryNotLow)
    }

    @Test
    fun shortIntervalsSkipTheBatteryConstraint() {
        // Users who explicitly asked for near-real-time monitoring (1/5 min) are not
        // silently starved on low battery.
        assertFalse(RefreshScheduling.plan(true, 1, wifiOnly = false, retryOnFailure = true)!!.requireBatteryNotLow)
        assertFalse(RefreshScheduling.plan(true, 5, wifiOnly = false, retryOnFailure = true)!!.requireBatteryNotLow)
    }

    @Test
    fun batteryConstraintTravelsIntoTheWorkConstraints() {
        val constrained = RefreshScheduling.buildRequest(
            RefreshWorkPlan(15, false, true, requireBatteryNotLow = true),
        )
        assertTrue(constrained.workSpec.constraints.requiresBatteryNotLow())

        val unconstrained = RefreshScheduling.buildRequest(
            RefreshWorkPlan(15, false, true, requireBatteryNotLow = false),
        )
        assertFalse(unconstrained.workSpec.constraints.requiresBatteryNotLow())
    }

    // ---- buildRequest() (constraints + input data) ---------------------------

    @Test
    fun wifiOnlyMapsToUnmeteredNetworkConstraint() {
        val request = RefreshScheduling.buildRequest(
            RefreshWorkPlan(15, requireUnmetered = true, retryOnFailure = true, requireBatteryNotLow = false),
        )
        assertEquals(NetworkType.UNMETERED, request.workSpec.constraints.requiredNetworkType)
        assertEquals(15L, request.workSpec.intervalDuration / 60_000)
    }

    @Test
    fun defaultNetworkSettingMapsToConnectedConstraint() {
        val request = RefreshScheduling.buildRequest(
            RefreshWorkPlan(30, requireUnmetered = false, retryOnFailure = true, requireBatteryNotLow = true),
        )
        assertEquals(NetworkType.CONNECTED, request.workSpec.constraints.requiredNetworkType)
        assertEquals(30L, request.workSpec.intervalDuration / 60_000)
    }

    @Test
    fun retryOnFailureFlagTravelsInWorkInputData() {
        val request = RefreshScheduling.buildRequest(
            RefreshWorkPlan(15, requireUnmetered = false, retryOnFailure = false, requireBatteryNotLow = false),
        )
        assertEquals(false, request.workSpec.input.getBoolean(RefreshWorker.KEY_RETRY_ON_FAILURE, true))
    }

    // ---- apply() (unique periodic work bookkeeping) ---------------------------

    @Test
    fun applyEnqueuesUniquePeriodicWork() {
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(context)
        RefreshScheduling.apply(context, RefreshWorkPlan(15, false, true, false))
        val workManager = WorkManager.getInstance(context)
        val infos = workManager.getWorkInfosForUniqueWork(RefreshScheduling.UNIQUE_WORK_NAME).get()
        assertEquals(1, infos.size)
    }

    @Test
    fun applyWithNullPlanCancelsBackgroundRefresh() {
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(context)
        RefreshScheduling.apply(context, RefreshWorkPlan(15, false, true, false))
        RefreshScheduling.apply(context, null)
        val workManager = WorkManager.getInstance(context)
        val infos = workManager.getWorkInfosForUniqueWork(RefreshScheduling.UNIQUE_WORK_NAME).get()
        assertTrue(
            infos.isEmpty() ||
                infos.all { it.state == androidx.work.WorkInfo.State.CANCELLED || it.state.isFinished },
        )
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RefreshWorkerTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun buildWorker(retryOnFailure: Boolean?): RefreshWorker {
        val builder = TestListenableWorkerBuilder<RefreshWorker>(context)
        if (retryOnFailure != null) {
            builder.setInputData(
                androidx.work.workDataOf(RefreshWorker.KEY_RETRY_ON_FAILURE to retryOnFailure),
            )
        }
        return builder.build() as RefreshWorker
    }

    @Test
    fun successfulRefreshReturnsSuccess() = runTest {
        RefreshWorker.delegateProvider = { BackgroundRefreshDelegate { RefreshOutcome.Succeeded } }
        try {
            assertEquals(androidx.work.ListenableWorker.Result.success(), buildWorker(null).doWork())
        } finally {
            RefreshWorker.delegateProvider = null
        }
    }

    @Test
    fun failedRefreshRetriesWhenRetryOnFailureEnabled() = runTest {
        RefreshWorker.delegateProvider = { BackgroundRefreshDelegate { RefreshOutcome.Failed } }
        try {
            assertEquals(
                androidx.work.ListenableWorker.Result.retry(),
                buildWorker(retryOnFailure = true).doWork(),
            )
        } finally {
            RefreshWorker.delegateProvider = null
        }
    }

    @Test
    fun failedRefreshFinishesWithoutRetryWhenRetryOnFailureDisabled() = runTest {
        RefreshWorker.delegateProvider = { BackgroundRefreshDelegate { RefreshOutcome.Failed } }
        try {
            assertEquals(
                androidx.work.ListenableWorker.Result.success(),
                buildWorker(retryOnFailure = false).doWork(),
            )
        } finally {
            RefreshWorker.delegateProvider = null
        }
    }

    @Test
    fun missingDelegateFailsTheWork() = runTest {
        RefreshWorker.delegateProvider = null
        assertEquals(androidx.work.ListenableWorker.Result.failure(), buildWorker(null).doWork())
    }

    @Test
    fun retryDecisionFollowsPreference() {
        assertEquals(RetryDecision.Retry, RefreshRetryPolicy.decide(true))
        assertEquals(RetryDecision.GiveUp, RefreshRetryPolicy.decide(false))
    }
}
