package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.repository.CredentialRepository
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/** In-memory [CredentialRepository] fake shared by the credentials feature tests. */
class FakeCredentialRepository : CredentialRepository {
    val credentials = MutableStateFlow<List<Credential>>(emptyList())
    val secrets = MutableStateFlow<Map<UUID, CredentialSecret>>(emptyMap())
    val savedSecrets = MutableStateFlow<Map<UUID, CredentialSecret>>(emptyMap())
    val deletedIds = MutableStateFlow<List<UUID>>(emptyList())
    var readSecretError: AppError? = null

    override fun observeCredentials(): Flow<List<Credential>> = credentials

    override suspend fun save(credential: Credential, secret: CredentialSecret) {
        savedSecrets.update { it + (credential.id to secret) }
        secrets.update { it + (credential.id to secret) }
        credentials.update { current ->
            (current.filterNot { it.id == credential.id } + credential)
                .sortedWith(compareBy({ it.sortOrder }, { it.name }))
        }
    }

    override suspend fun delete(id: UUID) {
        deletedIds.update { it + id }
        secrets.update { it - id }
        credentials.update { current -> current.filterNot { it.id == id } }
    }

    override suspend fun readSecret(id: UUID): CredentialSecret? {
        readSecretError?.let { throw it }
        return secrets.value[id]
    }
}
