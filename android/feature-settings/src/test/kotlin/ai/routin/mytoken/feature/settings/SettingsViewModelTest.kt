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

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        refreshStore = FakeRefreshSettingsStore()
        displayStore = FakeDisplaySettingsStore()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel() = SettingsViewModel(refreshStore, displayStore)

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
        assertEquals(CardDensity.STANDARD, state.display.cardDensity)
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

        vm.setCardDensity(CardDensity.COMPACT)
        vm.setShowDisabledCredentials(false)
        vm.setDefaultExpandGroups(false)
        vm.setShowUsageProgress(false)
        vm.setShowBalance(false)
        vm.setShowResetTime(false)
        advanceUntilIdle()

        val display = displayStore.state.value
        assertEquals(CardDensity.COMPACT, display.cardDensity)
        assertFalse(display.showDisabledCredentials)
        assertFalse(display.defaultExpandGroups)
        assertFalse(display.showUsageProgress)
        assertFalse(display.showBalance)
        assertFalse(display.showResetTime)
    }
}
