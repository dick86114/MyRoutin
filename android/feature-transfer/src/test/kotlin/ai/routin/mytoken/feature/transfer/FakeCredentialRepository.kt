package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.repository.CredentialRepository
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

/** In-memory [CredentialRepository] with failure injection, used by transfer tests. */
open class FakeCredentialRepository : CredentialRepository {
    val credentials = LinkedHashMap<UUID, Credential>()
    val secrets = LinkedHashMap<UUID, CredentialSecret>()
    val cachedSnapshots = LinkedHashMap<UUID, ai.routin.mytoken.domain.model.UsageSnapshot>()
    val savedCalls = mutableListOf<UUID>()

    /** When set, the Nth (0-based) [save] call throws; subsequent calls also throw. */
    var failSaveFromIndex: Int? = null
    private var saveIndex = 0

    private val flow = MutableStateFlow<List<Credential>>(emptyList())

    private fun refresh() {
        flow.value = credentials.values.toList()
    }

    override fun observeCredentials(): Flow<List<Credential>> = flow

    override suspend fun save(credential: Credential, secret: CredentialSecret) {
        val index = saveIndex++
        if (failSaveFromIndex != null && index >= failSaveFromIndex!!) {
            throw AppError.Storage("injected storage failure")
        }
        if (secret.kind != credential.credentialKind) {
            throw AppError.Storage("kind mismatch")
        }
        credentials[credential.id] = credential
        secrets[credential.id] = secret
        savedCalls.add(credential.id)
        refresh()
    }

    override suspend fun delete(id: UUID) {
        credentials.remove(id)
        secrets.remove(id)
        refresh()
    }

    override suspend fun readSecret(id: UUID): CredentialSecret? = secrets[id]

    override suspend fun cacheSnapshot(snapshot: ai.routin.mytoken.domain.model.UsageSnapshot) {
        cachedSnapshots[snapshot.credentialId] = snapshot
    }

    override suspend fun cachedSnapshot(id: UUID): ai.routin.mytoken.domain.model.UsageSnapshot? =
        cachedSnapshots[id]
}
