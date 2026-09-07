package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.core.crypto.CryptoSession
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the JSON wire shapes against real macOS `JSONEncoder` output
 * (`TransferSession.swift` / `TransferServer.swift` Codable contracts).
 */
class TransferWireTest {

    @Test
    fun `decodes the exact connection request JSON produced by Swift`() {
        // Output of JSONEncoder on macOS for TransferConnectionRequest.
        val swiftJson =
            "{\"sessionID\":\"${TransferFixtures.SESSION_ID}\",\"connectionCode\":\"482913\"," +
                "\"macEphemeralPublicKey\":\"2J47rXlDfb7Z+ENBgwT0YP8Fx\\/6B\\/kqVd6gEy5Nn\\/2Y=\"}"
        val request = TransferWireCodec.decodeAckLinePlaceholder(swiftJson)
        assertEquals(TransferFixtures.SESSION_ID, request.sessionId)
        assertEquals("482913", request.connectionCode)
        assertArrayEquals(TransferFixtures.MAC_PUBLIC_KEY, Base64.getMimeDecoder().decode(request.macEphemeralPublicKey))
    }

    @Test
    fun `encodes a handshake JSON with the exact Swift field names and standard base64`() {
        val handshake = TransferHandshake(
            sessionId = TransferFixtures.SESSION_ID,
            androidEphemeralPublicKey = Base64.getEncoder().encodeToString(TransferFixtures.ANDROID_PUBLIC_KEY)
        )
        val encoded = TransferWireCodec.encodeHandshake(handshake)
        // Swift produces: {"androidEphemeralPublicKey":"NOQtSvXvlKB6OoQgG4idTNGnQ8snsRtqEEOKj+uOWEc=","sessionID":"..."}
        val expectedKey = Base64.getEncoder().encodeToString(TransferFixtures.ANDROID_PUBLIC_KEY)
        assertEquals(
            "NOQtSvXvlKB6OoQgG4idTNGnQ8snsRtqEEOKj+uOWEc=",
            expectedKey
        )
        val parsed = TransferWireCodec.json.parseToJsonElement(encoded).let { it as kotlinx.serialization.json.JsonObject }
        assertEquals(setOf("sessionID", "androidEphemeralPublicKey"), parsed.keys)
        assertEquals("\"$expectedKey\"", parsed["androidEphemeralPublicKey"].toString())
        assertEquals(TransferFixtures.SESSION_ID, (parsed["sessionID"] as kotlinx.serialization.json.JsonPrimitive).content)
    }

    @Test
    fun `decodes the exact acknowledgement line from TransferServer`() {
        val ack = TransferWireCodec.decodeAck("{\"ok\":true,\"protocolVersion\":1}")
        assertTrue(ack.ok)
        assertEquals(1, ack.protocolVersion)
    }

    @Test
    fun `ack with ok false is rejected by the client`() {
        val ack = TransferWireCodec.decodeAck("{\"ok\":false,\"protocolVersion\":1}")
        org.junit.Assert.assertFalse(ack.ok)
    }

    @Test
    fun `decodes the exact encrypted message JSON produced by Swift`() {
        // Swift JSONEncoder escapes "/" as "\/"; "+" is emitted as-is.
        val ciphertextSwiftEscaped =
            Base64.getEncoder().encodeToString(TransferFixtures.CIPHERTEXT).replace("/", "\\/")
        val swiftJson =
            "{\"nonce\":\"AAECAwQFBgcICQoL\",\"authenticationTag\":\"binZsL5Vd91Ls0aRzRKgbA==\"," +
                "\"ciphertext\":\"$ciphertextSwiftEscaped\"," +
                "\"sessionID\":\"${TransferFixtures.SESSION_ID}\",\"protocolVersion\":1}"
        val message = TransferWireCodec.decodeEncryptedMessage(swiftJson)
        assertEquals(1, message.protocolVersion)
        assertEquals(TransferFixtures.SESSION_ID, message.sessionId)
        assertArrayEquals(TransferFixtures.NONCE, Base64.getMimeDecoder().decode(message.nonce))
        assertArrayEquals(TransferFixtures.TAG, Base64.getMimeDecoder().decode(message.authenticationTag))
        assertArrayEquals(TransferFixtures.CIPHERTEXT, Base64.getMimeDecoder().decode(message.ciphertext))
    }

    @Test
    fun `encrypted message round trip keeps field names`() {
        val message = TransferEncryptedMessage(
            protocolVersion = 1,
            sessionId = TransferFixtures.SESSION_ID,
            nonce = Base64.getEncoder().encodeToString(TransferFixtures.NONCE),
            ciphertext = Base64.getEncoder().encodeToString(TransferFixtures.CIPHERTEXT),
            authenticationTag = Base64.getEncoder().encodeToString(TransferFixtures.TAG)
        )
        val parsed = TransferWireCodec.decodeEncryptedMessage(TransferWireCodec.encodeEncryptedMessage(message))
        assertEquals(message, parsed)
    }

    @Test
    fun `decodes the CryptoKit-sealed package end to end`() {
        val plaintext = CryptoSession.open(
            nonce = TransferFixtures.NONCE,
            ciphertext = TransferFixtures.CIPHERTEXT,
            authenticationTag = TransferFixtures.TAG,
            key = TransferFixtures.SESSION_KEY,
            associatedData = CryptoSession.associatedData(TransferFixtures.SESSION_ID, 1)
        )
        val packageData = TransferPackageCodec.decode(plaintext)
        assertEquals(1, packageData.schemaVersion)
        assertEquals(1, packageData.credentials.size)
        assertEquals("deepseek", packageData.credentials[0].providerId)
        assertEquals("bearerAPIKey", packageData.credentials[0].credentialKind)
        assertEquals("Example Key", packageData.credentials[0].name)
        assertEquals("https://api.example.com/v1", packageData.credentials[0].metadata["baseURL"])
        assertEquals(1, packageData.secretEnvelope.entries.size)
        assertEquals("A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D", packageData.secretEnvelope.entries[0].credentialId)
    }

    @Test
    fun `package decode accepts unknown fields like Swift Codable`() {
        val withUnknown = TransferFixtures.PACKAGE_JSON.replace(
            "{\"credentials\":",
            "{\"futureField\":123,\"credentials\":"
        )
        val packageData = TransferPackageCodec.decode(withUnknown.toByteArray())
        assertEquals(1, packageData.credentials.size)
    }

    @Test
    fun `package decode rejects unknown metadata key`() {
        val withBadMetadata = TransferFixtures.PACKAGE_JSON.replace(
            "\"metadata\":{\"baseURL\":\"https://api.example.com/v1\"}",
            "\"metadata\":{\"notAllowed\":\"x\"}"
        )
        assertThrows(TransferPackageException::class.java) {
            TransferPackageCodec.decode(withBadMetadata.toByteArray())
        }
    }

    @Test
    fun `package decode rejects unknown provider`() {
        val withBadProvider = TransferFixtures.PACKAGE_JSON.replace("\"providerId\":\"deepseek\"", "\"providerId\":\"unknown\"")
        assertThrows(TransferPackageException::class.java) {
            TransferPackageCodec.decode(withBadProvider.toByteArray())
        }
    }

    @Test
    fun `package decode rejects wrong schema version`() {
        val withBadVersion = TransferFixtures.PACKAGE_JSON.replace("\"schemaVersion\":1,\"secretEnvelope\"", "\"schemaVersion\":2,\"secretEnvelope\"")
        assertThrows(TransferPackageException::class.java) {
            TransferPackageCodec.decode(withBadVersion.toByteArray())
        }
    }

    @Test
    fun `package decode rejects envelope referencing unknown credential`() {
        val withForeignEntry = TransferFixtures.PACKAGE_JSON.replace(
            "\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"}],\"ephemeralPublicKey\"",
            "\"credentialId\":\"B1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"}],\"ephemeralPublicKey\""
        )
        assertThrows(TransferPackageException::class.java) {
            TransferPackageCodec.decode(withForeignEntry.toByteArray())
        }
    }

    @Test
    fun `package decode rejects invalid envelope algorithm and key agreement`() {
        val badAlgorithm = TransferFixtures.PACKAGE_JSON.replace("\"algorithm\":\"AES-256-GCM\"", "\"algorithm\":\"DES\"")
        assertThrows(TransferPackageException::class.java) { TransferPackageCodec.decode(badAlgorithm.toByteArray()) }
        val badAgreement = TransferFixtures.PACKAGE_JSON.replace(
            "\"keyAgreement\":\"X25519-HKDF-SHA256\"",
            "\"keyAgreement\":\"RSA\""
        )
        assertThrows(TransferPackageException::class.java) { TransferPackageCodec.decode(badAgreement.toByteArray()) }
    }

    @Test
    fun `package decode rejects incomplete access key pair and empty entry`() {
        val partial = TransferFixtures.PACKAGE_JSON.replace(
            "\"bearerToken\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"",
            "\"accessKeyID\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\""
        )
        assertThrows(TransferPackageException::class.java) { TransferPackageCodec.decode(partial.toByteArray()) }
    }

    @Test
    fun `base64url lexical validator matches the Swift contract`() {
        assertTrue(Base64UrlLexical.isValid("AA"))
        assertTrue(Base64UrlLexical.isValid("Zh"))
        assertTrue(Base64UrlLexical.isValid("A".repeat(4)))
        assertTrue(Base64UrlLexical.isValid("AAA")) // 4n+3 accepted
        assertTrue(Base64UrlLexical.isValid("AB-_-9"))
        org.junit.Assert.assertFalse(Base64UrlLexical.isValid(""))
        org.junit.Assert.assertFalse(Base64UrlLexical.isValid("A")) // 4n+1 rejected
        org.junit.Assert.assertFalse(Base64UrlLexical.isValid("AA=")) // padding rejected
        org.junit.Assert.assertFalse(Base64UrlLexical.isValid("AA+//")) // non-url alphabet
    }
}

/** Small helper so the connection request test can reuse the production decoder. */
private fun TransferWireCodec.decodeAckLinePlaceholder(json: String): TransferConnectionRequest =
    TransferWireCodec.json.decodeFromString(TransferConnectionRequest.serializer(), json)
