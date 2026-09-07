package ai.routin.mytoken.core.security

import java.util.UUID

/**
 * Storage for secret bytes. Implementations must protect contents at rest
 * (e.g. Android Keystore-wrapped encryption) and treat inputs as opaque.
 */
interface SecretStore {
    suspend fun save(id: UUID, secret: ByteArray)
    suspend fun read(id: UUID): ByteArray?
    suspend fun delete(id: UUID)
}
