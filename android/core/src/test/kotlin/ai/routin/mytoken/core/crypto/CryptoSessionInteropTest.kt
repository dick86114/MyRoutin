package ai.routin.mytoken.core.crypto

import com.google.crypto.tink.subtle.X25519
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins [CryptoSession] against vectors produced by real Apple CryptoKit
 * (macOS 26, Swift 6.3) using the exact primitives from
 * `RoutinUsage/Transfer/TransferSession.swift`. See the repo report for the
 * generator script. These are synthetic test keys; no credential material.
 */
class CryptoSessionInteropTest {
    private val sessionId = "5E7B0A62-9C1F-4E3A-8D2B-1F6C4A9E7D30"
    private val macPrivateKey = hex("101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f")
    private val androidPrivateKey = hex("303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f")
    private val macPublicKey =
        hex("d89e3bad79437dbed9f843418304f460ff05c7fe81fe4a9577a804cb9367ff66")
    private val androidPublicKey =
        hex("34e42d4af5ef94a07a3a84201b889d4cd1a743cb27b11b6a10438a8feb8e5847")
    private val sessionKey =
        hex("531ddc4fc1b0f928213d19d1486bead0bfd390281d307b6ab1db13f73678acac")
    private val nonce = hex("000102030405060708090a0b")
    private val tag = hex("6e29d9b0be5577dd4bb34691cd12a06c")

    // Ciphertext of the package JSON below, sealed by CryptoKit with the
    // session key, the fixed nonce, and AAD "mytoken-transfer/v1|$sessionId".
    private val ciphertext = hex(
        "2c77f05973cf7304227aee0b49fee7415625e66d6431b942fadab631da7eb60b06dcea7e0295b3debe478397bcd35349ff0513e40302828eb6e95c71015a842daabb8250907dd17b7a1e4371a52a2db3c734627ecefef5cde9acd295c4568cce0330670c0f360d20f902c3ba98b1c81d871a8fa5e2db7b471fa340c1cc493f72d40fdd75b4387307bd9002b79f562e19d3eb2da2828c26940920fb714ae091a3515bd04e7d7e0f721c8b0a3c3b6bee0537bf1ec521bceda3689871bb3fffe29b4c57b6a7119611d822394e327d14229062216407dee4e5370ad5bb5b211e6481e7f03e2194eeba824078a6057b74431227bba43a4e04dd3e45f4a820b9dd9132c059421ef4cac9fa55b11195dabe23b238a0d044f6fd8b1b00622ec4a6736f7b100a691f8ce96ea1625d93fe678041d2961e5483502c471bde2bb60df78f9d90c71a7a995fa4ac15dd25b8479bc8704f4ff4f0a8c054e39e90124886e99ba87e80892d288638bf116239f7b7bdf17d49e5f242d273938e934113da2255fd57bb1cde439c76a75dedded289a809e092b665138c9f88c61c14d84749f85265b157439facbe3eaaca4bc25a8a22014557d5d85d638f1ef22dad62a84dda7f7ddb552ba02f0e664b4020762844e953057e9271ec08cef5a048ab360489944336e1c92e0a3c2d40849c879d7f922a7636cd1b25c4a584a3ae274a82ee673e71de4615272dbfba433623a6083dca7b637de17d888b3c0fbf20939fc65690e42bc537758507f866773d4b8f36dd5a5155910392c0c794ee9afdf717d53a5f2eb0f060fa61d25d00cda64321ced0635aef5cd6ea1a4aa534e15ec3ebd8c1c20ba087a64ae55f7a274fb9df08694e2b5e9251c3abb64a8ea78f77a0e702d754f27611faf2aa6dd1fa328151679e39b94e94ed39bdc60ec208dd1317acb1941f18ceb262028660210d4af25a97c29c0ec98f7f2e8ba4aff8579ed1bcd9cdb1a3880c4f98674937750b37ba5bcafa8adc62c3"
    )
    private val plaintext =
        ("{\"credentials\":[{\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"," +
            "\"credentialKind\":\"bearerAPIKey\",\"isEnabled\":true,\"metadata\":{\"baseURL\":\"https://api.example.com/v1\"}," +
            "\"name\":\"Example Key\",\"providerId\":\"deepseek\",\"schemaVersion\":1,\"sortOrder\":0}]," +
            "\"exportedAt\":\"2026-09-07T03:00:00Z\",\"preferences\":{\"alertThresholds\":[50,80]," +
            "\"notificationsEnabled\":true,\"openAppRefresh\":true,\"pinnedCredentialIds\":[]," +
            "\"refreshIntervalMinutes\":15,\"wifiOnly\":false},\"schemaVersion\":1,\"secretEnvelope\":" +
            "{\"algorithm\":\"AES-256-GCM\",\"ciphertext\":\"AA\",\"entries\":[{\"bearerToken\":\"RXhhbXBsZVRva2Vu\"," +
            "\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"}],\"ephemeralPublicKey\":\"AA\"," +
            "\"keyAgreement\":\"X25519-HKDF-SHA256\",\"nonce\":\"AA\",\"tag\":\"AA\"}}")

    @Test
    fun `public keys match CryptoKit X25519 raw representations`() {
        assertEquals(macPublicKey.toList(), X25519.publicFromPrivate(macPrivateKey).toList())
        assertEquals(androidPublicKey.toList(), X25519.publicFromPrivate(androidPrivateKey).toList())
    }

    @Test
    fun `ECDH shared secret and HKDF derive the CryptoKit session key`() {
        // Both sides must derive the same 32-byte key from their own private key.
        val fromMacSide = CryptoSession.deriveSessionKey(
            sharedSecret = CryptoSession.x25519SharedSecret(macPrivateKey, androidPublicKey),
            sessionId = sessionId
        )
        val fromAndroidSide = CryptoSession.deriveSessionKey(
            sharedSecret = CryptoSession.x25519SharedSecret(androidPrivateKey, macPublicKey),
            sessionId = sessionId
        )
        assertArrayEquals(sessionKey, fromMacSide)
        assertArrayEquals(sessionKey, fromAndroidSide)
    }

    @Test
    fun `HKDF info and AAD use the exact macOS strings`() {
        assertEquals("mytoken-transfer/v1/hkdf-sha256", String(CryptoSession.hkdfInfo(1), Charsets.UTF_8))
        assertEquals(
            "mytoken-transfer/v1|$sessionId",
            String(CryptoSession.associatedData(sessionId, 1), Charsets.UTF_8)
        )
    }

    @Test
    fun `opens a CryptoKit-sealed message`() {
        val decrypted = CryptoSession.open(
            nonce = nonce,
            ciphertext = ciphertext,
            authenticationTag = tag,
            key = sessionKey,
            associatedData = CryptoSession.associatedData(sessionId, 1)
        )
        assertEquals(plaintext, String(decrypted, Charsets.UTF_8))
    }

    @Test
    fun `seal output opens back and tag is 16 bytes`() {
        val sealed = CryptoSession.seal(
            plaintext = plaintext.toByteArray(Charsets.UTF_8),
            key = sessionKey,
            associatedData = CryptoSession.associatedData(sessionId, 1),
            random = kotlin.random.Random(nonce.toList().map { it.toInt() }.toIntArray().let { it.hashCode() })
        )
        assertEquals(12, sealed.nonce.size)
        assertEquals(16, sealed.authenticationTag.size)
        val opened = CryptoSession.open(
            sealed.nonce, sealed.ciphertext, sealed.authenticationTag,
            sessionKey, CryptoSession.associatedData(sessionId, 1)
        )
        assertEquals(plaintext, String(opened, Charsets.UTF_8))
    }

    @Test
    fun `opening with wrong AAD fails authentication`() {
        val wrongAad = CryptoSession.associatedData("00000000-0000-0000-0000-000000000000", 1)
        val exception = assertThrows(Exception::class.java) {
            CryptoSession.open(nonce, ciphertext, tag, sessionKey, wrongAad)
        }
        assertTrue(exception is javax.crypto.AEADBadTagException)
    }

    @Test
    fun `HKDF matches RFC 5869 test case 1`() {
        // A.1: IKM=0x0b x22, salt=000102...0c, info=f0f1..f9, L=42
        val okm = CryptoSession.hkdfSha256(
            ikm = hex("0b".repeat(22)),
            salt = hex("000102030405060708090a0b0c"),
            info = hex("f0f1f2f3f4f5f6f7f8f9"),
            length = 42
        )
        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
            okm.joinToString("") { "%02x".format(it) }
        )
    }

    @Test
    fun `random key pairs agree on the same shared secret`() {
        val a = CryptoSession.generateEphemeralKeyPair()
        val b = CryptoSession.generateEphemeralKeyPair()
        val ab = CryptoSession.x25519SharedSecret(a.privateKey, b.publicKey)
        val ba = CryptoSession.x25519SharedSecret(b.privateKey, a.publicKey)
        assertArrayEquals(ab, ba)
        assertEquals(32, ab.size)
    }

    private fun hex(value: String): ByteArray =
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
