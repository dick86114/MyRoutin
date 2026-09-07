package ai.routin.mytoken.data.alerts

import ai.routin.mytoken.core.alerts.AlertNotificationState
import ai.routin.mytoken.core.alerts.AlertStateStore
import ai.routin.mytoken.core.alerts.AlertWindowKey
import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.util.UUID
import kotlinx.coroutines.flow.first

private val Context.alertStateDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "mytoken_alert_state"
)

/**
 * DataStore-backed persistence of the MetricAlertEvaluator "notify once" bookkeeping,
 * so threshold crossings are not re-notified when the periodic worker runs in a new
 * process. Only opaque keys and UUIDs are stored — no credential material.
 */
class DataStoreAlertStateStore(private val context: Context) : AlertStateStore {

    override suspend fun load(): AlertNotificationState {
        val prefs = context.alertStateDataStore.data.first()
        val triggered = prefs[TRIGGERED_KEYS].orEmpty()
            .mapNotNull { AlertWindowKey.decode(it) }
            .toSet()
        val invalid = prefs[INVALID_NOTIFIED].orEmpty()
            .mapNotNull { runCatching { UUID.fromString(it) }.getOrNull() }
            .toSet()
        return AlertNotificationState(triggeredWindows = triggered, invalidNotifiedCredentials = invalid)
    }

    override suspend fun save(state: AlertNotificationState) {
        context.alertStateDataStore.edit { prefs ->
            prefs[TRIGGERED_KEYS] = state.triggeredWindows.map { it.encoded() }.toSet()
            prefs[INVALID_NOTIFIED] = state.invalidNotifiedCredentials.map { it.toString() }.toSet()
        }
    }

    private companion object {
        val TRIGGERED_KEYS = stringSetPreferencesKey("alertTriggeredKeys")
        val INVALID_NOTIFIED = stringSetPreferencesKey("invalidNotifiedCredentialIds")
    }
}
