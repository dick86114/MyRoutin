package ai.routin.mytoken.domain.usage

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.repository.CredentialRepository
import java.time.Clock
import java.util.UUID
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** Per-credential refresh status. */
enum class RefreshStatus { Loading, Ready, Failed, Disabled }

/**
 * State of a single credential's usage refresh. A failed refresh keeps the last
 * successful snapshot and marks it stale; no fabricated metric values are produced.
 */
data class CredentialUsageState(
    val status: RefreshStatus,
    val snapshot: UsageSnapshot? = null,
    val isStale: Boolean = false,
    val error: AppError? = null,
)

/**
 * Refreshes usage for all enabled credentials, each with an independent state.
 * Concurrency across credentials is limited to [maxConcurrency] simultaneous fetches.
 */
class RefreshCredentialsUseCase(
    private val repository: CredentialRepository,
    private val providers: Map<ProviderId, UsageProvider>,
    private val clock: Clock = Clock.systemUTC(),
    private val maxConcurrency: Int = DEFAULT_MAX_CONCURRENCY,
) {
    init {
        require(maxConcurrency >= 1) { "maxConcurrency must be positive" }
    }

    private val semaphore = Semaphore(maxConcurrency)
    private val _states = MutableStateFlow<Map<UUID, CredentialUsageState>>(emptyMap())
    val states: StateFlow<Map<UUID, CredentialUsageState>> = _states.asStateFlow()

    /** Refreshes every credential; disabled credentials are reported as [RefreshStatus.Disabled]. */
    suspend fun refreshAll() {
        val credentials = repository.observeCredentials().first()
        coroutineScope {
            credentials.forEach { credential ->
                if (credential.isEnabled) {
                    launch { refresh(credential) }
                } else {
                    setDisabled(credential.id)
                }
            }
        }
    }

    /** Refreshes a single credential, preserving the previous snapshot on failure. */
    suspend fun refresh(credential: Credential) {
        if (!credential.isEnabled) {
            setDisabled(credential.id)
            return
        }
        update(credential.id) { previous ->
            CredentialUsageState(
                status = RefreshStatus.Loading,
                snapshot = previous.snapshot,
                isStale = previous.isStale
            )
        }
        semaphore.withPermit {
            val result = runCatching {
                val provider = providers[credential.providerId]
                    ?: throw UsageProviderException.InvalidCredential(
                        "暂不支持该供应商的用量查询"
                    )
                val secret = repository.readSecret(credential.id)
                    ?: throw AppError.Storage("凭证密钥缺失，请重新导入")
                provider.fetchUsage(credential, secret).getOrThrow()
            }
            update(credential.id) { previous ->
                result.fold(
                    onSuccess = { snapshot ->
                        CredentialUsageState(
                            status = RefreshStatus.Ready,
                            snapshot = snapshot,
                            isStale = false
                        )
                    },
                    onFailure = { error ->
                        CredentialUsageState(
                            status = RefreshStatus.Failed,
                            snapshot = previous.snapshot,
                            isStale = previous.snapshot != null,
                            error = mapError(error)
                        )
                    }
                )
            }
        }
    }

    private fun setDisabled(id: UUID) {
        update(id) { CredentialUsageState(status = RefreshStatus.Disabled) }
    }

    private fun update(id: UUID, transform: (CredentialUsageState) -> CredentialUsageState) {
        val current = _states.value
        _states.value = current + (id to transform(current[id] ?: CredentialUsageState(RefreshStatus.Loading)))
    }

    private fun mapError(error: Throwable): AppError = when (error) {
        is AppError -> error
        is UsageProviderException.Unauthorized -> AppError.Authentication(error.message)
        is UsageProviderException.RateLimited -> AppError.Network(error.message)
        is UsageProviderException.Transport -> AppError.Network(error.message)
        is UsageProviderException.ProviderUnavailable -> AppError.Network(error.message)
        is UsageProviderException.ProviderMessage -> AppError.Network(error.message)
        is UsageProviderException.InvalidResponse -> AppError.Decode(error.message)
        is UsageProviderException.InvalidCredential -> AppError.Unknown(error.message)
        else -> AppError.Unknown(error.message ?: "刷新用量失败")
    }

    companion object {
        const val DEFAULT_MAX_CONCURRENCY: Int = 4
    }
}
