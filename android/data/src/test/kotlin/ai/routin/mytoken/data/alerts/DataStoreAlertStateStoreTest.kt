package ai.routin.mytoken.data.alerts

import ai.routin.mytoken.core.alerts.AlertNotificationState
import ai.routin.mytoken.core.alerts.AlertWindowKey
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DataStoreAlertStateStoreTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val store = DataStoreAlertStateStore(context)

    @Test
    fun emptyByDefaultThenStateRoundTripsAndClears() = runTest {
        // Defaults (asserted before any write; the store is process-local).
        val initial = store.load()
        assertTrue(initial.triggeredWindows.isEmpty())
        assertTrue(initial.invalidNotifiedCredentials.isEmpty())

        val credentialId = UUID.fromString("00000000-0000-0000-0000-000000000001")
        val key = AlertWindowKey(credentialId, "m1", "1788281600", 80)
        store.save(
            AlertNotificationState(
                triggeredWindows = setOf(key),
                invalidNotifiedCredentials = setOf(credentialId),
            ),
        )
        val loaded = store.load()
        assertEquals(setOf(key), loaded.triggeredWindows)
        assertEquals(setOf(credentialId), loaded.invalidNotifiedCredentials)

        store.save(AlertNotificationState())
        val cleared = store.load()
        assertTrue(cleared.triggeredWindows.isEmpty())
        assertTrue(cleared.invalidNotifiedCredentials.isEmpty())
    }
}
