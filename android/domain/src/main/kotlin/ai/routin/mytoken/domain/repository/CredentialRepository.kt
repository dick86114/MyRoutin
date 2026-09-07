package ai.routin.mytoken.domain.repository

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.UsageSnapshot
import kotlinx.coroutines.flow.Flow
import java.util.UUID

interface CredentialRepository {
    fun observeCredentials(): Flow<List<Credential>>
    suspend fun save(credential: Credential, secret: CredentialSecret)
    suspend fun delete(id: UUID)
    suspend fun readSecret(id: UUID): CredentialSecret?

    /**
     * Caches the latest usage snapshot for a credential. Implementations remove
     * cached snapshots together with the credential on delete. Best-effort:
     * callers must treat a thrown error as a non-fatal cache miss, never as a
     * refresh failure.
     */
    suspend fun cacheSnapshot(snapshot: UsageSnapshot)

    /** Reads the last cached usage snapshot for a credential, or null when none. */
    suspend fun cachedSnapshot(id: UUID): UsageSnapshot?
}
