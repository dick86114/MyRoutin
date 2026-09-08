package ai.routin.mytoken.feature.settings

import ai.routin.mytoken.data.preferences.AppPreferencesRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** 更新通道偏好：mirrorBase 为空 = GitHub 直连，非空 = CDN 镜像前缀。 */
data class UpdateSettings(
    val mirrorBase: String = "",
)

interface UpdateSettingsStore {
    val settings: Flow<UpdateSettings>
    suspend fun setMirrorBase(base: String)
}

class AppPreferencesUpdateSettingsStore(
    private val preferencesRepository: AppPreferencesRepository,
) : UpdateSettingsStore {

    override val settings: Flow<UpdateSettings> = preferencesRepository.updatePreferences.map { prefs ->
        UpdateSettings(mirrorBase = prefs.updateMirrorBase)
    }

    override suspend fun setMirrorBase(base: String) {
        preferencesRepository.setUpdateMirrorBase(base)
    }
}
