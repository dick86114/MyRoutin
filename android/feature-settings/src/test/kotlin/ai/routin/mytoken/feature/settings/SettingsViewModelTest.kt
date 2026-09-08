package ai.routin.mytoken.feature.settings

import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var refreshStore: FakeRefreshSettingsStore
    private lateinit var displayStore: FakeDisplaySettingsStore
    private lateinit var notificationStore: FakeNotificationSettingsStore
    private lateinit var updateController: FakeAppUpdateController

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        refreshStore = FakeRefreshSettingsStore()
        displayStore = FakeDisplaySettingsStore()
        notificationStore = FakeNotificationSettingsStore()
        updateController = FakeAppUpdateController()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel() = SettingsViewModel(
        refreshStore,
        displayStore,
        notificationStore,
        updateController,
    )

    @Test
    fun initialStateLoadsDefaults() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        val state = vm.state.value
        assertFalse(state.isLoading)
        assertTrue(state.refresh.autoRefreshEnabled)
        assertEquals(15, state.refresh.refreshIntervalMinutes)
        assertTrue(state.refresh.openAppRefresh)
        assertTrue(state.refresh.retryOnFailure)
        assertTrue(state.display.showDisabledCredentials)
    }

    @Test
    fun refreshIntervalChangePersistsToStore() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setRefreshIntervalMinutes(5)
        advanceUntilIdle()

        assertEquals(5, refreshStore.state.value.refreshIntervalMinutes)
        assertEquals(5, vm.state.value.refresh.refreshIntervalMinutes)
    }

    @Test
    fun refreshIntervalOutsideAllowedValuesIsIgnored() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setRefreshIntervalMinutes(3)
        advanceUntilIdle()

        assertEquals(15, refreshStore.state.value.refreshIntervalMinutes)
    }

    @Test
    fun refreshTogglesPersistToStore() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setAutoRefreshEnabled(false)
        vm.setWifiOnly(true)
        vm.setOpenAppRefresh(false)
        vm.setRetryOnFailure(false)
        advanceUntilIdle()

        val refresh = refreshStore.state.value
        assertFalse(refresh.autoRefreshEnabled)
        assertTrue(refresh.wifiOnly)
        assertFalse(refresh.openAppRefresh)
        assertFalse(refresh.retryOnFailure)
    }

    @Test
    fun displayChangesPersistToStore() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setShowDisabledCredentials(false)
        vm.setDefaultExpandGroups(false)
        vm.setShowUsageProgress(false)
        vm.setShowBalance(false)
        vm.setShowResetTime(false)
        advanceUntilIdle()

        val display = displayStore.state.value
        assertFalse(display.showDisabledCredentials)
        assertFalse(display.defaultExpandGroups)
        assertFalse(display.showUsageProgress)
        assertFalse(display.showBalance)
        assertFalse(display.showResetTime)
    }

    @Test
    fun initialStateLoadsNotificationDefaults() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        val notifications = vm.state.value.notifications
        assertTrue(notifications.notificationsEnabled)
        assertEquals(50, notifications.lowThresholdPercent)
        assertEquals(80, notifications.highThresholdPercent)
        assertTrue(notifications.credentialFailureAlertsEnabled)
    }

    @Test
    fun notificationTogglesPersistToStore() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setNotificationsEnabled(false)
        vm.setCredentialFailureAlertsEnabled(false)
        advanceUntilIdle()

        assertFalse(notificationStore.state.value.notificationsEnabled)
        assertFalse(notificationStore.state.value.credentialFailureAlertsEnabled)
    }

    @Test
    fun thresholdChangesPersistToStore() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setLowAlertThreshold(30)
        advanceUntilIdle()

        assertEquals(30, notificationStore.state.value.lowThresholdPercent)
        assertEquals(80, notificationStore.state.value.highThresholdPercent)
        assertEquals(30, vm.state.value.notifications.lowThresholdPercent)

        vm.setHighAlertThreshold(90)
        advanceUntilIdle()
        assertEquals(90, notificationStore.state.value.highThresholdPercent)
    }

    @Test
    fun invalidThresholdChangesAreIgnored() = runTest(dispatcher) {
        val vm = viewModel()
        advanceUntilIdle()

        vm.setLowAlertThreshold(0)
        vm.setLowAlertThreshold(100)
        vm.setLowAlertThreshold(80) // >= high (80) → ignored
        vm.setHighAlertThreshold(20) // <= low (50) → ignored
        vm.setHighAlertThreshold(101)
        advanceUntilIdle()

        val notifications = notificationStore.state.value
        assertEquals(50, notifications.lowThresholdPercent)
        assertEquals(80, notifications.highThresholdPercent)
    }
}
