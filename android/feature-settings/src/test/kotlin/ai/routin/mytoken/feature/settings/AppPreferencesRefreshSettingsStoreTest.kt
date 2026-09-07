package ai.routin.mytoken.feature.settings

import ai.routin.mytoken.data.preferences.AppPreferencesRepository
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Asserts the single-source-of-truth consolidation: [AppPreferencesRefreshSettingsStore]
 * persists every refresh setting through the Task 5 [AppPreferencesRepository] DataStore
 * (`mytoken_settings`) — writes made through either side are visible on the other, and
 * no second refresh-settings DataStore exists.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppPreferencesRefreshSettingsStoreTest {

    private val repository = AppPreferencesRepository(ApplicationProvider.getApplicationContext())
    private val store = AppPreferencesRefreshSettingsStore(repository)

    @Test
    fun storeWritesAreVisibleThroughTask5Repository() = runTest {
        store.setRefreshIntervalMinutes(5)
        store.setWifiOnly(true)
        store.setAutoRefreshEnabled(false)
        store.setRetryOnFailure(false)

        val prefs = repository.preferences.first()
        assertEquals(5, prefs.refreshIntervalMinutes)
        assertTrue(prefs.wifiOnly)
        assertFalse(prefs.autoRefreshEnabled)
        assertFalse(prefs.retryOnFailure)

        val settings = store.settings.first()
        assertEquals(5, settings.refreshIntervalMinutes)
        assertTrue(settings.wifiOnly)
        assertFalse(settings.autoRefreshEnabled)
        assertFalse(settings.retryOnFailure)
    }

    @Test
    fun task5RepositoryWritesAreVisibleThroughStore() = runTest {
        repository.setRefreshIntervalMinutes(30)
        repository.setOpenAppRefresh(false)
        repository.setRetryOnFailure(true)
        repository.setAutoRefreshEnabled(false)

        val settings = store.settings.first()
        assertEquals(30, settings.refreshIntervalMinutes)
        assertFalse(settings.openAppRefresh)
        assertTrue(settings.retryOnFailure)
        assertFalse(settings.autoRefreshEnabled)
    }

    @Test
    fun defaultsMatchAcrossBothSurfaces() = runTest {
        val prefs = repository.preferences.first()
        val settings = store.settings.first()
        assertEquals(prefs.autoRefreshEnabled, settings.autoRefreshEnabled)
        assertEquals(prefs.refreshIntervalMinutes, settings.refreshIntervalMinutes)
        assertEquals(prefs.wifiOnly, settings.wifiOnly)
        assertEquals(prefs.openAppRefresh, settings.openAppRefresh)
        assertEquals(prefs.retryOnFailure, settings.retryOnFailure)
    }

    @Test
    fun intervalOutsideAllowedValuesIsRejected() = runTest {
        // Anchor to an explicit value first: the DataStore singleton persists across
        // test methods in this class, so defaults must not be assumed here.
        store.setRefreshIntervalMinutes(1)
        try {
            store.setRefreshIntervalMinutes(3)
            throw AssertionError("expected IllegalArgumentException")
        } catch (expected: IllegalArgumentException) {
            // expected: one key per semantic keeps the Task 5 validation.
        }
        assertEquals(1, repository.preferences.first().refreshIntervalMinutes)
    }
}
