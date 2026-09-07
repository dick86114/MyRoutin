package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.ProviderId
import java.time.Instant
import java.util.Base64
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Wire models mirroring the Codable JSON contracts of the macOS transfer
 * implementation (`TransferSession.swift`, `TransferServer.swift`,
 * `TransferModels.swift`).
 *
 * Encoding notes pinned against the Swift JSONEncoder/JSONDecoder defaults:
 * - `Data`-typed fields (`nonce`, `ciphertext`, `authenticationTag`,
 *   `macEphemeralPublicKey`, `androidEphemeralPublicKey`) are **standard
 *   Base64 with padding** on the JSON wire (unlike the QR URI and the secret
 *   envelope, which use unpadded base64url).
 * - UUIDs are uppercase, hyphenated strings (Swift `uuidString`).
 * - Unknown JSON fields are ignored (Swift Codable behavior).
 */
object TransferWireCodec {
    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    fun encodeConnectionRequest(request: TransferConnectionRequest): String =
        json.encodeToString(TransferConnectionRequest.serializer(), request)

    fun decodeAck(line: String): ConnectionAcknowledgement =
        json.decodeFromString(ConnectionAcknowledgement.serializer(), line)

    fun encodeHandshake(handshake: TransferHandshake): String =
        json.encodeToString(TransferHandshake.serializer(), handshake)

    fun decodeEncryptedMessage(line: String): TransferEncryptedMessage =
        json.decodeFromString(TransferEncryptedMessage.serializer(), line)

    fun encodeEncryptedMessage(message: TransferEncryptedMessage): String =
        json.encodeToString(TransferEncryptedMessage.serializer(), message)
}

@Serializable
data class TransferConnectionRequest(
    @SerialName("sessionID") val sessionId: String,
    @SerialName("connectionCode") val connectionCode: String,
    @SerialName("macEphemeralPublicKey") val macEphemeralPublicKey: String
)

@Serializable
data class ConnectionAcknowledgement(
    @SerialName("ok") val ok: Boolean,
    @SerialName("protocolVersion") val protocolVersion: Int
)

@Serializable
data class TransferHandshake(
    @SerialName("sessionID") val sessionId: String,
    @SerialName("androidEphemeralPublicKey") val androidEphemeralPublicKey: String
)

@Serializable
data class TransferEncryptedMessage(
    @SerialName("protocolVersion") val protocolVersion: Int,
    @SerialName("sessionID") val sessionId: String,
    @SerialName("nonce") val nonce: String,
    @SerialName("ciphertext") val ciphertext: String,
    @SerialName("authenticationTag") val authenticationTag: String
)

/**
 * The result of a successful LAN handshake: the encrypted envelope plus the
 * derived one-time session key held in memory only. `toString` is redacted so
 * no key or ciphertext material can leak through logs.
 */
class EncryptedTransferPackage(
    val sessionId: String,
    val message: TransferEncryptedMessage,
    internal val sessionKey: ByteArray
) {
    override fun toString(): String =
        "EncryptedTransferPackage(sessionId=$sessionId, protocolVersion=${message.protocolVersion}, " +
            "nonce=<redacted>, ciphertext=<redacted>, authenticationTag=<redacted>)"
}

// ---------------------------------------------------------------------------
// Transfer package schema v1 (mirror of TransferModels.swift)
// ---------------------------------------------------------------------------

/** Unpadded-base64url lexical contract shared by the envelope and its entries. */
object Base64UrlLexical {
    fun isValid(value: String): Boolean {
        if (value.isEmpty() || value.length % 4 == 1) return false
        return value.all {
            it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_'
        }
    }

    fun decode(value: String): ByteArray? {
        if (!isValid(value)) return null
        return try {
            val padded = value + "=".repeat((4 - value.length % 4) % 4)
            Base64.getUrlDecoder().decode(padded)
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}

class TransferPackageException(message: String, cause: Throwable? = null) : Exception(message, cause)

@Serializable
data class TransferCredentialV1(
    @SerialName("schemaVersion") val schemaVersion: Int,
    @SerialName("credentialId") val credentialId: String,
    @SerialName("providerId") val providerId: String,
    @SerialName("credentialKind") val credentialKind: String,
    @SerialName("name") val name: String,
    @SerialName("isEnabled") val isEnabled: Boolean = true,
    @SerialName("sortOrder") val sortOrder: Int = 0,
    @SerialName("metadata") val metadata: Map<String, String> = emptyMap()
)

@Serializable
data class TransferPreferencesV1(
    @SerialName("refreshIntervalMinutes") val refreshIntervalMinutes: Int,
    @SerialName("wifiOnly") val wifiOnly: Boolean,
    @SerialName("openAppRefresh") val openAppRefresh: Boolean,
    @SerialName("notificationsEnabled") val notificationsEnabled: Boolean,
    @SerialName("alertThresholds") val alertThresholds: List<Int>,
    @SerialName("pinnedCredentialIds") val pinnedCredentialIds: List<String>
)

@Serializable
data class EncryptedSecretEntry(
    @SerialName("credentialId") val credentialId: String,
    @SerialName("bearerToken") val bearerToken: String? = null,
    @SerialName("apiKey") val apiKey: String? = null,
    @SerialName("accessKeyID") val accessKeyID: String? = null,
    @SerialName("secretAccessKey") val secretAccessKey: String? = null
) {
    val secretFieldCount: Int
        get() = listOfNotNull(bearerToken, apiKey, accessKeyID, secretAccessKey).size

    fun hasSecret(): Boolean = secretFieldCount > 0
}

@Serializable
data class EncryptedSecretEnvelope(
    @SerialName("algorithm") val algorithm: String,
    @SerialName("keyAgreement") val keyAgreement: String,
    @SerialName("nonce") val nonce: String,
    @SerialName("ciphertext") val ciphertext: String,
    @SerialName("tag") val tag: String,
    @SerialName("ephemeralPublicKey") val ephemeralPublicKey: String,
    @SerialName("associatedData") val associatedData: String? = null,
    @SerialName("entries") val entries: List<EncryptedSecretEntry> = emptyList()
)

@Serializable
data class TransferPackageV1(
    @SerialName("schemaVersion") val schemaVersion: Int,
    @SerialName("credentials") val credentials: List<TransferCredentialV1>,
    @SerialName("preferences") val preferences: TransferPreferencesV1,
    @SerialName("secretEnvelope") val secretEnvelope: EncryptedSecretEnvelope,
    @SerialName("exportedAt") val exportedAt: String
)

object TransferPackageCodec {
    private val metadataAllowlist: Set<String> =
        CredentialMetadataKey.entries.map { it.rawValue }.toSet()

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    /** Decodes and validates a transfer package (same rules as TransferModels.swift). */
    fun decode(data: ByteArray): TransferPackageV1 {
        val packageData = try {
            json.decodeFromString(TransferPackageV1.serializer(), String(data, Charsets.UTF_8))
        } catch (cause: Exception) {
            throw TransferPackageException("malformed transfer package", cause)
        }
        validate(packageData)
        return packageData
    }

    fun validate(packageData: TransferPackageV1) {
        if (packageData.schemaVersion != 1) {
            throw TransferPackageException("unsupported schema version ${packageData.schemaVersion}")
        }
        parseExportedAt(packageData.exportedAt)
            ?: throw TransferPackageException("invalid exportedAt: <redacted>")

        val credentialIds = HashSet<String>()
        packageData.credentials.forEach { credential ->
            validateCredential(credential)
            if (!credentialIds.add(credential.credentialId)) {
                throw TransferPackageException("duplicate credentialId in package")
            }
        }
        validatePreferences(packageData.preferences)
        validateEnvelope(packageData.secretEnvelope)
        val unknownEntries = packageData.secretEnvelope.entries
            .map { it.credentialId }
            .filterNot { it in credentialIds }
        if (unknownEntries.isNotEmpty()) {
            throw TransferPackageException("secret envelope references unknown credential")
        }
    }

    private fun validateCredential(credential: TransferCredentialV1) {
        if (credential.schemaVersion != 1) {
            throw TransferPackageException("unsupported credential schema version")
        }
        if (runCatching { UUID.fromString(credential.credentialId) }.isFailure) {
            throw TransferPackageException("invalid credentialId")
        }
        if (ProviderId.fromRawValue(credential.providerId) == null) {
            throw TransferPackageException("invalid providerId")
        }
        if (CredentialKind.fromRawValue(credential.credentialKind) == null) {
            throw TransferPackageException("invalid credentialKind")
        }
        val unknownKeys = credential.metadata.keys.filterNot { it in metadataAllowlist }
        if (unknownKeys.isNotEmpty()) {
            throw TransferPackageException("invalid metadata key")
        }
    }

    private fun validatePreferences(preferences: TransferPreferencesV1) {
        if (preferences.refreshIntervalMinutes !in listOf(1, 5, 15, 30)) {
            throw TransferPackageException("invalid refreshIntervalMinutes")
        }
        if (preferences.alertThresholds.any { it !in 0..100 }) {
            throw TransferPackageException("invalid alertThresholds")
        }
        if (preferences.pinnedCredentialIds.any { runCatching { UUID.fromString(it) }.isFailure }) {
            throw TransferPackageException("invalid pinnedCredentialIds")
        }
    }

    private fun validateEnvelope(envelope: EncryptedSecretEnvelope) {
        if (envelope.algorithm !in listOf("AES-256-GCM", "ChaCha20-Poly1305")) {
            throw TransferPackageException("invalid envelope algorithm")
        }
        if (envelope.keyAgreement != "X25519-HKDF-SHA256") {
            throw TransferPackageException("invalid envelope keyAgreement")
        }
        val encodedFields = listOf(
            "nonce" to envelope.nonce,
            "ciphertext" to envelope.ciphertext,
            "tag" to envelope.tag,
            "ephemeralPublicKey" to envelope.ephemeralPublicKey
        )
        if (encodedFields.any { !Base64UrlLexical.isValid(it.second) }) {
            throw TransferPackageException("invalid envelope encoded field")
        }
        if (envelope.associatedData != null && !Base64UrlLexical.isValid(envelope.associatedData)) {
            throw TransferPackageException("invalid envelope associatedData")
        }
        val entryIds = HashSet<String>()
        envelope.entries.forEach { entry ->
            if (runCatching { UUID.fromString(entry.credentialId) }.isFailure) {
                throw TransferPackageException("invalid envelope entry credentialId")
            }
            if (!entryIds.add(entry.credentialId)) {
                throw TransferPackageException("duplicate envelope entry")
            }
            if (!entry.hasSecret()) {
                throw TransferPackageException("envelope entry has no secret fields")
            }
            val secretFields = listOf(
                "bearerToken" to entry.bearerToken,
                "apiKey" to entry.apiKey,
                "accessKeyID" to entry.accessKeyID,
                "secretAccessKey" to entry.secretAccessKey
            )
            if (secretFields.any { it.second != null && !Base64UrlLexical.isValid(it.second!!) }) {
                throw TransferPackageException("invalid envelope entry secret encoding")
            }
            val hasPair = entry.accessKeyID != null && entry.secretAccessKey != null
            val hasPartialPair = (entry.accessKeyID == null) != (entry.secretAccessKey == null)
            if (hasPartialPair) {
                throw TransferPackageException("incomplete access key pair")
            }
            if (!hasPair && entry.bearerToken == null && entry.apiKey == null) {
                throw TransferPackageException("envelope entry has no usable secret fields")
            }
        }
    }

    private fun parseExportedAt(value: String): Instant? = try {
        Instant.parse(value)
    } catch (_: Exception) {
        null
    }
}
