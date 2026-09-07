package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.repository.CredentialRepository
import ai.routin.mytoken.domain.usage.UsageProvider
import ai.routin.mytoken.domain.usage.UsageProviderException
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Whole-screen state rendered by [CredentialEditorScreen]. */
data class CredentialEditorUiState(
    val isLoading: Boolean = true,
    val isNew: Boolean = true,
    val providerId: ProviderId = ProviderId.Routin,
    val credentialKind: CredentialKind = CredentialKind.BearerApiKey,
    val name: String = "",
    val apiKey: String = "",
    val accessKeyID: String = "",
    val secretAccessKey: String = "",
    val region: String = "",
    val baseURL: String = "",
    val userID: String = "",
    val websiteURL: String = "",
    val isSecretVisible: Boolean = false,
    val isSaving: Boolean = false,
    val isTestingConnection: Boolean = false,
    val testResultMessage: String? = null,
    val testSucceeded: Boolean? = null,
    val validationError: String? = null,
    val saveCompleted: Boolean = false,
)

/**
 * Editor state holder for a single credential ([credentialId] == null means "new").
 * Secrets are only held in memory for the form; persistence goes through
 * [CredentialRepository.save] so the encrypted secret store stays the single owner.
 */
class CredentialEditorViewModel(
    private val repository: CredentialRepository,
    private val providers: Map<ProviderId, UsageProvider>,
    private val credentialId: UUID? = null,
) : ViewModel() {

    private val _state = MutableStateFlow(CredentialEditorUiState())
    val state: StateFlow<CredentialEditorUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val existing = credentialId?.let { id ->
                repository.observeCredentials().first().firstOrNull { it.id == id }
            }
            if (existing == null) {
                _state.update { it.copy(isLoading = false, isNew = true) }
                return@launch
            }
            val secret = try {
                repository.readSecret(existing.id)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            val prefill = prefilledSecret(existing.credentialKind, secret)
            _state.update { current ->
                current.copy(
                    isLoading = false,
                    isNew = false,
                    providerId = existing.providerId,
                    credentialKind = existing.credentialKind,
                    name = existing.name,
                    apiKey = prefill.apiKey,
                    accessKeyID = prefill.accessKeyID,
                    secretAccessKey = prefill.secretAccessKey,
                    region = existing.metadata[CredentialMetadataKey.Region].orEmpty(),
                    baseURL = existing.metadata[CredentialMetadataKey.BaseURL].orEmpty(),
                    userID = existing.metadata[CredentialMetadataKey.UserID].orEmpty(),
                    websiteURL = existing.metadata[CredentialMetadataKey.WebsiteURL].orEmpty(),
                )
            }
        }
    }

    private fun prefilledSecret(
        kind: CredentialKind,
        secret: CredentialSecret?,
    ): CredentialEditorUiState = when (kind) {
        CredentialKind.BearerApiKey -> CredentialEditorUiState(
            apiKey = (secret as? CredentialSecret.BearerToken)?.token.orEmpty(),
        )
        CredentialKind.ApiKey -> CredentialEditorUiState(
            apiKey = (secret as? CredentialSecret.ApiKey)?.key.orEmpty(),
        )
        CredentialKind.AccessKeyPair -> CredentialEditorUiState(
            accessKeyID = (secret as? CredentialSecret.AccessKeyPair)?.accessKeyID.orEmpty(),
            secretAccessKey = (secret as? CredentialSecret.AccessKeyPair)?.secretAccessKey.orEmpty(),
        )
    }

    fun setProviderId(providerId: ProviderId) {
        _state.update {
            it.copy(
                providerId = providerId,
                credentialKind = defaultKind(providerId),
                testResultMessage = null,
                testSucceeded = null,
                validationError = null,
            )
        }
    }

    fun setName(value: String) = _state.update { it.copy(name = value) }
    fun setApiKey(value: String) = _state.update { it.copy(apiKey = value) }
    fun setAccessKeyID(value: String) = _state.update { it.copy(accessKeyID = value) }
    fun setSecretAccessKey(value: String) = _state.update { it.copy(secretAccessKey = value) }
    fun setRegion(value: String) = _state.update { it.copy(region = value) }
    fun setBaseURL(value: String) = _state.update { it.copy(baseURL = value) }
    fun setUserID(value: String) = _state.update { it.copy(userID = value) }
    fun setWebsiteURL(value: String) = _state.update { it.copy(websiteURL = value) }

    fun toggleSecretVisible() {
        _state.update { it.copy(isSecretVisible = !it.isSecretVisible) }
    }

    fun save() {
        if (_state.value.isSaving) return
        viewModelScope.launch {
            _state.update { it.copy(isSaving = true, validationError = null) }
            val validated = try {
                CredentialEditorValidation.validate(_state.value.providerId, formFields())
            } catch (error: CredentialValidationException) {
                _state.update { it.copy(isSaving = false, validationError = requireNotNull(error.message)) }
                return@launch
            }
            try {
                val existing = credentialId?.let { id ->
                    repository.observeCredentials().first().firstOrNull { it.id == id }
                }
                val id = existing?.id ?: UUID.randomUUID()
                val sortOrder = existing?.sortOrder
                    ?: (repository.observeCredentials().first().maxOfOrNull { it.sortOrder }?.plus(1) ?: 0)
                val credential = Credential(
                    id = id,
                    providerId = _state.value.providerId,
                    credentialKind = validated.credentialKind,
                    name = validated.name,
                    isEnabled = existing?.isEnabled ?: true,
                    sortOrder = sortOrder,
                    metadata = validated.metadata,
                )
                repository.save(credential, validated.secret)
                _state.update { it.copy(isSaving = false, saveCompleted = true) }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                _state.update { it.copy(isSaving = false, validationError = "保存失败，请重试") }
            }
        }
    }

    /**
     * Connection test for the currently entered form values. A failed test is only a
     * result message — saving remains possible (aligned with the macOS editor).
     */
    fun testConnection() {
        if (_state.value.isTestingConnection) return
        viewModelScope.launch {
            _state.update { it.copy(isTestingConnection = true, testResultMessage = null, testSucceeded = null) }
            val result: Result<*> = runCatching {
                val validated = CredentialEditorValidation.validate(_state.value.providerId, formFields())
                val provider = providers[_state.value.providerId]
                    ?: throw UsageProviderException.InvalidCredential("暂不支持该供应商的用量查询")
                val probe = Credential(
                    id = credentialId ?: UUID.randomUUID(),
                    providerId = _state.value.providerId,
                    credentialKind = validated.credentialKind,
                    name = validated.name,
                    metadata = validated.metadata,
                )
                provider.fetchUsage(probe, validated.secret).getOrThrow()
            }
            result.fold(
                onSuccess = {
                    _state.update {
                        it.copy(isTestingConnection = false, testSucceeded = true, testResultMessage = "连接成功")
                    }
                },
                onFailure = { error ->
                    if (error is CancellationException) throw error
                    _state.update {
                        it.copy(
                            isTestingConnection = false,
                            testSucceeded = false,
                            testResultMessage = error.message ?: "连接失败，请稍后重试",
                        )
                    }
                },
            )
        }
    }

    private fun formFields(): CredentialEditorValidation.FormFields {
        val s = _state.value
        return CredentialEditorValidation.FormFields(
            name = s.name,
            apiKey = s.apiKey,
            accessKeyID = s.accessKeyID,
            secretAccessKey = s.secretAccessKey,
            region = s.region,
            newAPIBaseURL = s.baseURL,
            newAPIUserID = s.userID,
            websiteURL = s.websiteURL,
        )
    }

    private fun defaultKind(providerId: ProviderId): CredentialKind = when (providerId) {
        ProviderId.Routin, ProviderId.NewAPI -> CredentialKind.BearerApiKey
        ProviderId.DeepSeek, ProviderId.Glm -> CredentialKind.ApiKey
        ProviderId.Volcengine -> CredentialKind.AccessKeyPair
    }
}
