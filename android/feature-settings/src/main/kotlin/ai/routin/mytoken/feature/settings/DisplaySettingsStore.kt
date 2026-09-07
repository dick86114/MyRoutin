package ai.routin.mytoken.feature.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Home-card density, mirroring the macOS popover's compact/standard modes. */
enum class CardDensity { STANDARD, COMPACT }

/** Android-only home display preferences; none of these sync to the Mac. */
data class DisplaySettings(
    val cardDensity: CardDensity = CardDensity.STANDARD,
    val showDisabledCredentials: Boolean = true,
    val defaultExpandGroups: Boolean = true,
    val showUsageProgress: Boolean = true,
    val showBalance: Boolean = true,
    val showResetTime: Boolean = true,
)

interface DisplaySettingsStore {
    val settings: Flow<DisplaySettings>
    suspend fun setCardDensity(density: CardDensity)
    suspend fun setShowDisabledCredentials(enabled: Boolean)
    suspend fun setDefaultExpandGroups(enabled: Boolean)
    suspend fun setShowUsageProgress(enabled: Boolean)
    suspend fun setShowBalance(enabled: Boolean)
    suspend fun setShowResetTime(enabled: Boolean)
}

private val Context.displaySettingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "mytoken_display_settings"
)

class DataStoreDisplaySettingsStore(private val context: Context) : DisplaySettingsStore {

    override val settings: Flow<DisplaySettings> = context.displaySettingsDataStore.data.map { prefs ->
        DisplaySettings(
            cardDensity = prefs[CARD_DENSITY]?.let { stored ->
                CardDensity.entries.firstOrNull { it.name == stored }
            } ?: CardDensity.STANDARD,
            showDisabledCredentials = prefs[SHOW_DISABLED] ?: true,
            defaultExpandGroups = prefs[DEFAULT_EXPAND] ?: true,
            showUsageProgress = prefs[SHOW_USAGE_PROGRESS] ?: true,
            showBalance = prefs[SHOW_BALANCE] ?: true,
            showResetTime = prefs[SHOW_RESET_TIME] ?: true,
        )
    }

    override suspend fun setCardDensity(density: CardDensity) =
        edit { it[CARD_DENSITY] = density.name }

    override suspend fun setShowDisabledCredentials(enabled: Boolean) =
        edit { it[SHOW_DISABLED] = enabled }

    override suspend fun setDefaultExpandGroups(enabled: Boolean) =
        edit { it[DEFAULT_EXPAND] = enabled }

    override suspend fun setShowUsageProgress(enabled: Boolean) =
        edit { it[SHOW_USAGE_PROGRESS] = enabled }

    override suspend fun setShowBalance(enabled: Boolean) =
        edit { it[SHOW_BALANCE] = enabled }

    override suspend fun setShowResetTime(enabled: Boolean) =
        edit { it[SHOW_RESET_TIME] = enabled }

    private suspend fun edit(transform: (androidx.datastore.preferences.core.MutablePreferences) -> Unit) {
        context.displaySettingsDataStore.edit(transform)
    }

    private companion object {
        val CARD_DENSITY = stringPreferencesKey("cardDensity")
        val SHOW_DISABLED = booleanPreferencesKey("showDisabledCredentials")
        val DEFAULT_EXPAND = booleanPreferencesKey("defaultExpandGroups")
        val SHOW_USAGE_PROGRESS = booleanPreferencesKey("showUsageProgress")
        val SHOW_BALANCE = booleanPreferencesKey("showBalance")
        val SHOW_RESET_TIME = booleanPreferencesKey("showResetTime")
    }
}
