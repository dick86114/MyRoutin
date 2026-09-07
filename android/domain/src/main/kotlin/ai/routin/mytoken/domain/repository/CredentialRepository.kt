package ai.routin.mytoken.domain.repository

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialSecret
import kotlinx.coroutines.flow.Flow
import java.util.UUID

interface CredentialRepository {
    fun observeCredentials(): Flow<List<Credential>>
    suspend fun save(credential: Credential, secret: CredentialSecret)
    suspend fun delete(id: UUID)
    suspend fun readSecret(id: UUID): CredentialSecret?
}
