package ai.routin.mytoken.data.repository

import ai.routin.mytoken.core.security.SecretStore
import ai.routin.mytoken.data.local.CredentialDao
import ai.routin.mytoken.data.local.CredentialEntity
import ai.routin.mytoken.data.local.MyTokenDatabase
import ai.routin.mytoken.data.local.UsageSnapshotDao
import ai.routin.mytoken.data.local.UsageSnapshotEntity
import ai.routin.mytoken.data.local.UsageSnapshotJsonCodec
import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.CredentialSecretCodec
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageSnapshot
import androidx.room.withTransaction
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Secure credential repository: Room for plaintext metadata and snapshot cache, [SecretStore]
 * (Android Keystore-backed in production) for encrypted secrets.
 *
 * Transaction boundary guarantees:
 * - [save] writes the secret first; if that fails, no metadata is written. If the metadata
 *   write subsequently fails, the just-written secret is rolled back (best effort), so a
 *   failed save never leaves observable metadata without a usable secret.
 * - [delete] removes the secret and, on metadata-deletion failure, restores it (best effort);
 *   metadata and snapshot cache are removed atomically.
 */
class CredentialRepositoryImpl(
    private val database: MyTokenDatabase,
    private val secretStore: SecretStore
) : ai.routin.mytoken.domain.repository.CredentialRepository {

    private val credentialDao: CredentialDao = database.credentialDao()
    private val snapshotDao: UsageSnapshotDao = database.usageSnapshotDao()

    override fun observeCredentials(): Flow<List<Credential>> =
        credentialDao.observeAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun save(credential: Credential, secret: CredentialSecret) {
        if (secret.kind != credential.credentialKind) {
            throw AppError.Storage(
                "credential kind ${credential.credentialKind.rawValue} does not match secret kind ${secret.kind.rawValue}"
            )
        }
        val encoded = CredentialSecretCodec.encode(secret).toByteArray(Charsets.UTF_8)

        secretStore.save(credential.id, encoded)
        try {
            database.withTransaction {
                credentialDao.upsert(credential.toEntity())
            }
        } catch (cause: Throwable) {
            runCatching { secretStore.delete(credential.id) }
                .onFailure { rollbackCause ->
                    // Non-fatal: the orphan encrypted secret is harmless (no metadata references it).
                    println("MyToken: failed to roll back secret after metadata failure: ${rollbackCause.message}")
                }
            throw AppError.Storage("failed to persist credential metadata", cause)
        }
    }

    override suspend fun delete(id: UUID) {
        val storedSecret = try {
            secretStore.read(id)
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to read secret for deletion", cause)
        }

        try {
            secretStore.delete(id)
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to delete secret", cause)
        }

        try {
            database.withTransaction {
                snapshotDao.deleteById(id.toString())
                credentialDao.deleteById(id.toString())
            }
        } catch (cause: Throwable) {
            if (storedSecret != null) {
                runCatching { secretStore.save(id, storedSecret) }
                    .onFailure { rollbackCause ->
                        println("MyToken: failed to restore secret after metadata deletion failure: ${rollbackCause.message}")
                    }
            }
            throw AppError.Storage("failed to delete credential metadata", cause)
        }
    }

    override suspend fun readSecret(id: UUID): CredentialSecret? {
        val encoded = try {
            secretStore.read(id)
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to read secret", cause)
        } ?: return null

        return CredentialSecretCodec.decode(String(encoded, Charsets.UTF_8))
            ?: throw AppError.Decode("stored secret has an unreadable format")
    }

    /** Caches the latest usage snapshot for a credential (removed automatically on delete). */
    suspend fun cacheSnapshot(snapshot: UsageSnapshot) {
        try {
            snapshotDao.upsert(
                UsageSnapshotEntity(
                    credentialId = snapshot.credentialId.toString(),
                    fetchedAtEpochMs = snapshot.fetchedAt.toEpochMilli(),
                    metricsJson = UsageSnapshotJsonCodec.encode(snapshot)
                )
            )
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to cache usage snapshot", cause)
        }
    }

    suspend fun latestSnapshot(credentialId: UUID): UsageSnapshot? {
        val entity = try {
            snapshotDao.findById(credentialId.toString())
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to read usage snapshot", cause)
        } ?: return null
        return UsageSnapshotJsonCodec.decode(credentialId, entity.metricsJson)
    }

    private fun Credential.toEntity(): CredentialEntity = CredentialEntity(
        id = id.toString(),
        providerId = providerId.rawValue,
        credentialKind = credentialKind.rawValue,
        name = name,
        isEnabled = isEnabled,
        sortOrder = sortOrder,
        baseURL = metadata[CredentialMetadataKey.BaseURL],
        userID = metadata[CredentialMetadataKey.UserID],
        region = metadata[CredentialMetadataKey.Region],
        planType = metadata[CredentialMetadataKey.PlanType],
        usageKind = metadata[CredentialMetadataKey.UsageKind],
        websiteURL = metadata[CredentialMetadataKey.WebsiteURL]
    )

    private fun CredentialEntity.toDomain(): Credential = Credential(
        id = UUID.fromString(id),
        providerId = requireNotNull(ProviderId.fromRawValue(providerId)) { "unknown providerId: $providerId" },
        credentialKind = requireNotNull(CredentialKind.fromRawValue(credentialKind)) { "unknown credentialKind: $credentialKind" },
        name = name,
        isEnabled = isEnabled,
        sortOrder = sortOrder,
        metadata = buildMap {
            baseURL?.let { put(CredentialMetadataKey.BaseURL, it) }
            userID?.let { put(CredentialMetadataKey.UserID, it) }
            region?.let { put(CredentialMetadataKey.Region, it) }
            planType?.let { put(CredentialMetadataKey.PlanType, it) }
            usageKind?.let { put(CredentialMetadataKey.UsageKind, it) }
            websiteURL?.let { put(CredentialMetadataKey.WebsiteURL, it) }
        }
    )
}
