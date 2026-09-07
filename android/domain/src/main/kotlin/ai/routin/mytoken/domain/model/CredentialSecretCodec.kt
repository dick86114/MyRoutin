package ai.routin.mytoken.domain.model

import java.util.Base64

/**
 * Serializes [CredentialSecret] values into an opaque string suitable for handing to the
 * encrypted secret store, and back. The encoding itself provides no confidentiality; it is
 * only a stable on-disk format for the ciphertext that the secure store produces.
 */
object CredentialSecretCodec {
    private const val VERSION = "v1"

    fun encode(secret: CredentialSecret): String {
        val b64: (String) -> String = {
            Base64.getUrlEncoder().withoutPadding().encodeToString(it.toByteArray(Charsets.UTF_8))
        }
        return when (secret) {
            is CredentialSecret.BearerToken ->
                listOf(VERSION, CredentialKind.BearerApiKey.rawValue, b64(secret.token)).joinToString("|")
            is CredentialSecret.ApiKey ->
                listOf(VERSION, CredentialKind.ApiKey.rawValue, b64(secret.key)).joinToString("|")
            is CredentialSecret.AccessKeyPair ->
                listOf(
                    VERSION,
                    CredentialKind.AccessKeyPair.rawValue,
                    b64(secret.accessKeyID),
                    b64(secret.secretAccessKey)
                ).joinToString("|")
        }
    }

    /**
     * Decodes an opaque encoded secret. Never throws for malformed input: any structural
     * mismatch, invalid Base64url, or empty segment yields null so callers can surface a
     * decode error instead of crashing on corrupted stored data.
     */
    fun decode(encoded: String): CredentialSecret? {
        val parts = encoded.split("|")
        if (parts.firstOrNull() != VERSION) return null
        val unb64: (String) -> String? = { value ->
            runCatching {
                if (value.isEmpty()) return@runCatching null
                String(Base64.getUrlDecoder().decode(value), Charsets.UTF_8)
            }.getOrNull()
        }
        return when (parts.getOrNull(1)) {
            CredentialKind.BearerApiKey.rawValue ->
                if (parts.size != 3) return null
                else unb64(parts[2])?.let { CredentialSecret.BearerToken(it) }
            CredentialKind.ApiKey.rawValue ->
                if (parts.size != 3) return null
                else unb64(parts[2])?.let { CredentialSecret.ApiKey(it) }
            CredentialKind.AccessKeyPair.rawValue -> {
                if (parts.size != 4) return null
                val id = unb64(parts[2]) ?: return null
                val key = unb64(parts[3]) ?: return null
                CredentialSecret.AccessKeyPair(id, key)
            }
            else -> null
        }
    }
}
