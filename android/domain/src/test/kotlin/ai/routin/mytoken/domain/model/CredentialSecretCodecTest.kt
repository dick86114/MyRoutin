package ai.routin.mytoken.domain.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CredentialSecretCodecTest {

    @Test
    fun roundTripsBearerToken() {
        val secret = CredentialSecret.BearerToken(token = "fixture-token-αβγ")
        assertEquals(secret, CredentialSecretCodec.decode(CredentialSecretCodec.encode(secret)))
    }

    @Test
    fun roundTripsApiKey() {
        val secret = CredentialSecret.ApiKey(key = "fixture-key")
        assertEquals(secret, CredentialSecretCodec.decode(CredentialSecretCodec.encode(secret)))
    }

    @Test
    fun roundTripsAccessKeyPair() {
        val secret = CredentialSecret.AccessKeyPair(
            accessKeyID = "fixture-id",
            secretAccessKey = "fixture-secret"
        )
        assertEquals(secret, CredentialSecretCodec.decode(CredentialSecretCodec.encode(secret)))
    }

    @Test
    fun decodeRejectsGarbage() {
        assertNull(CredentialSecretCodec.decode(""))
        assertNull(CredentialSecretCodec.decode("v9|bearerAPIKey|AAAA"))
        assertNull(CredentialSecretCodec.decode("v1|unknownKind|AAAA"))
    }

    @Test
    fun decodeRejectsInvalidBase64Characters() {
        // Must map to null, never throw IllegalArgumentException.
        assertNull(CredentialSecretCodec.decode("v1|bearerAPIKey|!!!"))
        assertNull(CredentialSecretCodec.decode("v1|apiKey|a@@b"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair|!!!|AAAA"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair|AAAA|!!!"))
    }

    @Test
    fun decodeRejectsTruncatedInput() {
        assertNull(CredentialSecretCodec.decode("v1"))
        assertNull(CredentialSecretCodec.decode("v1|bearerAPIKey"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair|AAAA"))
    }

    @Test
    fun decodeRejectsExtraSegments() {
        assertNull(CredentialSecretCodec.decode("v1|bearerAPIKey|AAAA|extra"))
        assertNull(CredentialSecretCodec.decode("v1|apiKey|AAAA|extra"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair|AAAA|BBBB|extra"))
    }

    @Test
    fun decodeRejectsEmptySegments() {
        assertNull(CredentialSecretCodec.decode("v1|bearerAPIKey|"))
        assertNull(CredentialSecretCodec.decode("v1|apiKey|"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair||AAAA"))
        assertNull(CredentialSecretCodec.decode("v1|accessKeyPair|AAAA|"))
        assertNull(CredentialSecretCodec.decode("|bearerAPIKey|AAAA"))
    }

    @Test
    fun decodeNeverThrowsForMalformedInput() {
        // Property-style sweep over a set of malformed inputs; none may throw.
        val malformed = listOf(
            "v1|bearerAPIKey|***",
            "v1|bearerAPIKey|A",
            "v1|bearerAPIKey|AAAA|BBBB|CCCC",
            "v1|accessKeyPair|!!!!|!!!!|extra",
            "v1|",
            "||",
            "not-encoded-at-all"
        )
        for (input in malformed) {
            val result = runCatching { CredentialSecretCodec.decode(input) }
            check(result.isSuccess) { "decode must not throw for: $input" }
            assertNull(result.getOrNull())
        }
    }

    @Test
    fun encodedFormNeverContainsRawSecret() {
        val secret = CredentialSecret.BearerToken(token = "fixture-plain-secret")
        val encoded = CredentialSecretCodec.encode(secret)
        check(!encoded.contains("fixture-plain-secret")) { "raw secret must not appear in encoded form" }
    }
}
