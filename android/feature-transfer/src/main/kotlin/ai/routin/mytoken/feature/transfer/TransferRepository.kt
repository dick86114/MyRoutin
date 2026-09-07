package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.core.crypto.CryptoSession
import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.repository.CredentialRepository
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.flow.first

/** How to handle credentials whose UUID already exists on the device. */
enum class ImportConflictMode {
    /** Keep the existing credential untouched. */
    SKIP,

    /** Replace the existing credential (metadata + secret). */
    OVERWRITE
}

data class ImportSummary(
    val importedCount: Int,
    val overwrittenCount: Int,
    val skippedCount: Int,
    val skippedWithoutSecretCount: Int
)

data class ImportPreview(
    val providerCount: Int,
    val credentialCount: Int,
    val sensitiveItemCount: Int
)

data class TransferImportItem(
    val credentialId: UUID,
    val providerId: String,
    val credentialKind: String,
    val name: String,
    val hasSecret: Boolean,
    val conflictsWithExisting: Boolean
)

interface TransferRepository {
    suspend fun connect(payload: TransferQrCodePayload): Result<EncryptedTransferPackage>
    suspend fun decrypt(packageData: EncryptedTransferPackage): Result<TransferPackageV1>
    suspend fun import(
        packageData: TransferPackageV1,
        conflictMode: ImportConflictMode
    ): Result<ImportSummary>

    /** Metadata-only counts used by the confirmation screen before anything is written. */
    suspend fun preview(packageData: TransferPackageV1): ImportPreview

    /** Per-credential preview rows with conflict and secret-availability flags. */
    suspend fun previewItems(packageData: TransferPackageV1): List<TransferImportItem>
}

/**
 * Orchestrates the transfer flow: LAN connect/decrypt via [TransferClient],
 * then an atomic, rollback-compensating import through the domain
 * [CredentialRepository] (secrets go through the Keystore-backed store).
 */
class TransferRepositoryImpl(
    private val client: TransferClient,
    private val credentialRepository: CredentialRepository
) : TransferRepository {

    override suspend fun connect(payload: TransferQrCodePayload): Result<EncryptedTransferPackage> =
        client.connect(payload)

    override suspend fun decrypt(packageData: EncryptedTransferPackage): Result<TransferPackageV1> =
        try {
            Result.success(decryptInternal(packageData))
        } catch (cause: Throwable) {
            Result.failure(cause)
        }

    override suspend fun import(
        packageData: TransferPackageV1,
        conflictMode: ImportConflictMode
    ): Result<ImportSummary> = try {
        Result.success(importInternal(packageData, conflictMode))
    } catch (cause: Throwable) {
        Result.failure(cause)
    }

    private fun decryptInternal(packageData: EncryptedTransferPackage): TransferPackageV1 {
        val message = packageData.message
        if (message.protocolVersion != CryptoSession.PROTOCOL_VERSION) {
            throw AppError.Authentication("unsupported transfer protocol version")
        }
        if (message.sessionId != packageData.sessionId) {
            throw AppError.Authentication("encrypted message session does not match the scanned session")
        }
        val nonce = try {
            Base64.getMimeDecoder().decode(message.nonce)
        } catch (_: IllegalArgumentException) {
            throw AppError.Decode("malformed nonce encoding")
        }
        val ciphertext = decodeWireBase64(message.ciphertext) { AppError.Decode("malformed ciphertext encoding") }
        val tag = decodeWireBase64(message.authenticationTag) { AppError.Decode("malformed tag encoding") }
        if (nonce.size != CryptoSession.NONCE_BYTE_SIZE) {
            throw AppError.Authentication("invalid GCM nonce length")
        }
        if (tag.size != CryptoSession.TAG_BYTE_SIZE) {
            throw AppError.Authentication("invalid GCM tag length")
        }
        val plaintext = try {
            CryptoSession.open(
                nonce = nonce,
                ciphertext = ciphertext,
                authenticationTag = tag,
                key = packageData.sessionKey,
                associatedData =
                    CryptoSession.associatedData(packageData.sessionId, message.protocolVersion)
            )
        } catch (cause: Exception) {
            throw AppError.Authentication("decryption failed: ciphertext was tampered with or the key is wrong", cause)
        }
        return try {
            TransferPackageCodec.decode(plaintext)
        } catch (cause: TransferPackageException) {
            throw AppError.Decode("transferred package failed validation: ${cause.message}", cause)
        }
    }

    private fun decodeWireBase64(value: String, onError: () -> AppError): ByteArray = try {
        // Swift JSONEncoder emits padded standard Base64; MIME decoding is
        // additionally tolerant of line separators but still verifies padding.
        Base64.getMimeDecoder().decode(value)
    } catch (_: IllegalArgumentException) {
        throw onError()
    }

    /** Metadata-only view used by the confirmation screen before anything is written. */
    override suspend fun preview(packageData: TransferPackageV1): ImportPreview = ImportPreview(
        providerCount = packageData.credentials.map { it.providerId }.distinct().size,
        credentialCount = packageData.credentials.size,
        sensitiveItemCount = packageData.secretEnvelope.entries.count { it.hasSecret() }
    )

    override suspend fun previewItems(packageData: TransferPackageV1): List<TransferImportItem> {
        val existingIds = try {
            credentialRepository.observeCredentials().first().map { it.id.toString().uppercase() }.toSet()
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to read existing credentials", cause)
        }
        val secretIds = packageData.secretEnvelope.entries.map { it.credentialId.uppercase() }.toSet()
        return packageData.credentials.map { credential ->
            TransferImportItem(
                credentialId = UUID.fromString(credential.credentialId),
                providerId = credential.providerId,
                credentialKind = credential.credentialKind,
                name = credential.name,
                hasSecret = credential.credentialId.uppercase() in secretIds,
                conflictsWithExisting = credential.credentialId.uppercase() in existingIds
            )
        }
    }

    private suspend fun importInternal(
        packageData: TransferPackageV1,
        conflictMode: ImportConflictMode
    ): ImportSummary {
        val existing = try {
            credentialRepository.observeCredentials().first()
        } catch (cause: Throwable) {
            throw AppError.Storage("failed to read existing credentials", cause)
        }
        // macOS UUID strings are uppercase; java.util.UUID.toString() is lowercase.
        val existingById = existing.associateBy { it.id.toString().uppercase() }
        val entriesById = packageData.secretEnvelope.entries.associateBy { it.credentialId.uppercase() }

        val importedIds = mutableListOf<UUID>()
        val overwrites = mutableListOf<Pair<Credential, CredentialSecret?>>()

        var importedCount = 0
        var overwrittenCount = 0
        var skippedCount = 0
        var skippedWithoutSecretCount = 0

        try {
            for (transferCredential in packageData.credentials.sortedBy { it.sortOrder }) {
                val existingCredential = existingById[transferCredential.credentialId]
                if (existingCredential != null && conflictMode == ImportConflictMode.SKIP) {
                    skippedCount += 1
                    continue
                }
                val secret = entrySecret(transferCredential, entriesById[transferCredential.credentialId.uppercase()])
                if (secret == null) {
                    skippedWithoutSecretCount += 1
                    continue
                }
                val credential = transferCredential.toDomain()
                if (existingCredential != null) {
                    // Capture the original secret so a later failure can restore it.
                    overwrites.add(existingCredential to credentialRepository.readSecret(existingCredential.id))
                }
                credentialRepository.save(credential, secret)
                importedIds.add(credential.id)
                if (existingCredential != null) {
                    overwrittenCount += 1
                } else {
                    importedCount += 1
                }
            }
        } catch (cause: Throwable) {
            rollback(importedIds, overwrites)
            if (cause is AppError) throw cause
            throw AppError.Storage("credential import failed; changes were rolled back", cause)
        }

        return ImportSummary(
            importedCount = importedCount,
            overwrittenCount = overwrittenCount,
            skippedCount = skippedCount,
            skippedWithoutSecretCount = skippedWithoutSecretCount
        )
    }

    /** Best-effort compensation: remove new credentials, restore overwritten ones. */
    private suspend fun rollback(
        importedIds: List<UUID>,
        overwrites: List<Pair<Credential, CredentialSecret?>>
    ) {
        importedIds.forEach { id ->
            runCatching { credentialRepository.delete(id) }
                .onFailure { failure ->
                    // Non-fatal: report-only rollback gap.
                    println("MyToken: import rollback failed to delete imported credential: ${failure.message}")
                }
        }
        overwrites.forEach { (original, originalSecret) ->
            runCatching {
                if (originalSecret != null) {
                    credentialRepository.save(original, originalSecret)
                } else {
                    // Original had no stored secret; remove the overwrite entirely.
                    credentialRepository.delete(original.id)
                }
            }.onFailure { failure ->
                println("MyToken: import rollback failed to restore credential: ${failure.message}")
            }
        }
    }

    /**
     * Maps an envelope entry to the typed [CredentialSecret] required by the
     * credential kind. Entries without the kind-required field are rejected;
     * credentials without any entry are reported as "without secret".
     */
    private fun entrySecret(
        credential: TransferCredentialV1,
        entry: EncryptedSecretEntry?
    ): CredentialSecret? {
        if (entry == null) return null
        val kind = CredentialKind.fromRawValue(credential.credentialKind)
            ?: throw AppError.Decode("invalid credentialKind")
        fun decode(value: String): String {
            val bytes = Base64UrlLexical.decode(value)
                ?: throw AppError.Decode("invalid secret encoding in transfer package")
            return String(bytes, Charsets.UTF_8)
        }
        return when (kind) {
            CredentialKind.BearerApiKey -> entry.bearerToken
                ?.let { CredentialSecret.BearerToken(decode(it)) }
            CredentialKind.ApiKey -> entry.apiKey?.let { CredentialSecret.ApiKey(decode(it)) }
            CredentialKind.AccessKeyPair -> {
                val accessKeyId = entry.accessKeyID
                val secretAccessKey = entry.secretAccessKey
                if (accessKeyId != null && secretAccessKey != null) {
                    CredentialSecret.AccessKeyPair(decode(accessKeyId), decode(secretAccessKey))
                } else {
                    null
                }
            }
        } ?: throw AppError.Decode("secret entry does not match credential kind ${kind.rawValue}")
    }

    private fun TransferCredentialV1.toDomain(): Credential = Credential(
        id = UUID.fromString(credentialId),
        providerId = requireNotNull(ProviderId.fromRawValue(providerId)) { "invalid providerId" },
        credentialKind = requireNotNull(CredentialKind.fromRawValue(credentialKind)) { "invalid credentialKind" },
        name = name,
        isEnabled = isEnabled,
        sortOrder = sortOrder,
        metadata = metadata.mapNotNull { (key, value) ->
            CredentialMetadataKey.entries.firstOrNull { it.rawValue == key }?.let { it to value }
        }.toMap()
    )
}
