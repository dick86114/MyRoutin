package ai.routin.mytoken.data.refresh

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DataStoreRefreshStatusStoreTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val store = DataStoreRefreshStatusStore(context)

    @Test
    fun defaultsStartEmptyThenRecordedTimestampsPersist() = runTest {
        // Defaults (asserted before any write; the store is process-local).
        val initial = store.status.first()
        assertNull(initial.lastSuccessAtEpochMillis)
        assertNull(initial.lastFailureAtEpochMillis)

        store.recordSuccess(1_000L)
        store.recordFailure(2_000L)
        store.recordSuccess(3_000L)

        val status = store.status.first()
        assertEquals(3_000L, status.lastSuccessAtEpochMillis)
        assertEquals(2_000L, status.lastFailureAtEpochMillis)
    }
}
