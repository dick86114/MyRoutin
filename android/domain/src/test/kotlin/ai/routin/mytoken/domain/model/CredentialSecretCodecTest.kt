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
    fun encodedFormNeverContainsRawSecret() {
        val secret = CredentialSecret.BearerToken(token = "fixture-plain-secret")
        val encoded = CredentialSecretCodec.encode(secret)
        check(!encoded.contains("fixture-plain-secret")) { "raw secret must not appear in encoded form" }
    }
}
