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

    fun decode(encoded: String): CredentialSecret? {
        val parts = encoded.split("|")
        if (parts.isEmpty() || parts[0] != VERSION) return null
        val unb64: (String) -> String = {
            String(Base64.getUrlDecoder().decode(it), Charsets.UTF_8)
        }
        return when (parts.getOrNull(1)) {
            CredentialKind.BearerApiKey.rawValue ->
                parts.getOrNull(2)?.let { CredentialSecret.BearerToken(unb64(it)) }
            CredentialKind.ApiKey.rawValue ->
                parts.getOrNull(2)?.let { CredentialSecret.ApiKey(unb64(it)) }
            CredentialKind.AccessKeyPair.rawValue -> {
                val id = parts.getOrNull(2) ?: return null
                val key = parts.getOrNull(3) ?: return null
                CredentialSecret.AccessKeyPair(unb64(id), unb64(key))
            }
            else -> null
        }
    }
}
