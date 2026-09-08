package ai.routin.mytoken.widget

import android.content.Context
import java.util.UUID

/** Stores one selected credential per home-screen widget instance. */
class WidgetSelectionStore(context: Context) {

    private val preferences = context.applicationContext
        .getSharedPreferences("mytoken_widgets", Context.MODE_PRIVATE)

    fun selectedCredentialId(appWidgetId: Int): UUID? {
        val raw = preferences.getString(key(appWidgetId), null) ?: return null
        return runCatching { UUID.fromString(raw) }.getOrNull()
    }

    fun setSelectedCredential(appWidgetId: Int, credentialId: UUID) {
        preferences.edit().putString(key(appWidgetId), credentialId.toString()).apply()
    }

    fun remove(appWidgetId: Int) {
        preferences.edit().remove(key(appWidgetId)).apply()
    }

    private fun key(appWidgetId: Int) = "credential_$appWidgetId"
}
