package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.UsageProvider
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow

/** Scriptable [UsageProvider] fake: returns the queued result at most once per call. */
class FakeUsageProvider(override val providerId: ProviderId) : UsageProvider {
    val requests = MutableStateFlow<List<Pair<Credential, CredentialSecret>>>(emptyList())
    private val queue = ArrayDeque<Result<UsageSnapshot>>()

    fun enqueue(result: Result<UsageSnapshot>) {
        queue.addLast(result)
    }

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        requests.value = requests.value + (credential to secret)
        val result = queue.removeFirstOrNull()
            ?: Result.failure(IllegalStateException("no scripted response"))
        // Shape must match the real contract: a cold flow-like single emission.
        return result
    }
}

/** Repository variant whose credential stream can be set once (for editor load tests). */
class StaticCredentialRepository(
    initialCredentials: List<Credential> = emptyList(),
    initialSecrets: Map<UUID, CredentialSecret> = emptyMap(),
) : ai.routin.mytoken.domain.repository.CredentialRepository {
    val credentials = MutableStateFlow(initialCredentials)
    val secrets = initialSecrets.toMutableMap()
    val saved = MutableStateFlow<List<Pair<Credential, CredentialSecret>>>(emptyList())
    val deleted = MutableStateFlow<List<UUID>>(emptyList())

    override fun observeCredentials(): Flow<List<Credential>> = flow {
        emit(credentials.value)
        credentials.collect { emit(it) }
    }

    override suspend fun save(credential: Credential, secret: CredentialSecret) {
        saved.value = saved.value + (credential to secret)
        secrets[credential.id] = secret
        credentials.value = credentials.value.filterNot { it.id == credential.id } + credential
    }

    override suspend fun delete(id: UUID) {
        deleted.value = deleted.value + id
        credentials.value = credentials.value.filterNot { it.id == id }
    }

    override suspend fun readSecret(id: UUID): CredentialSecret? = secrets[id]
}

internal fun snapshot(credentialId: UUID) = UsageSnapshot(
    credentialId = credentialId,
    fetchedAt = Instant.parse("2026-09-07T12:00:00Z"),
    metrics = emptyList(),
)
