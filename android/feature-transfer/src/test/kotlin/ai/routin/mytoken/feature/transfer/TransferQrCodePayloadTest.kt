package ai.routin.mytoken.feature.transfer

import java.time.Instant
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TransferQrCodePayloadTest {
    private val now: Instant = TransferFixtures.NOW

    @Test
    fun `parses the exact URI produced by macOS TransferQRCodePayload`() {
        val payload = TransferQrCodePayload.decode(TransferFixtures.QR_URI, now)
        assertEquals(1, payload.protocolVersion)
        assertEquals(TransferFixtures.SESSION_ID, payload.sessionId)
        assertEquals("192.168.1.10", payload.host)
        assertEquals(52888, payload.port)
        assertArrayEquals(TransferFixtures.MAC_PUBLIC_KEY, payload.macEphemeralPublicKey)
        assertEquals(Instant.parse(TransferFixtures.EXPIRY_INSTANT), payload.expiresAt)
        assertEquals("482913", payload.connectionCode)
    }

    @Test
    fun `accepts localhost host`() {
        val payload = validPayload(host = "localhost")
        assertEquals("localhost", payload.host)
    }

    @Test
    fun `accepts dotted hostname`() {
        assertEquals("MacBook-Pro.local", validPayload(host = "MacBook-Pro.local").host)
    }

    @Test
    fun `rejects wrong scheme`() {
        assertInvalid("yourtoken-transfer://v1?${query()}")
    }

    @Test
    fun `rejects wrong version host`() {
        assertInvalid("mytoken-transfer://v2?${query()}")
    }

    @Test
    fun `rejects unexpected query keys`() {
        // Same strict key set as Swift: replacing `code` with an extra key fails.
        val raw = "mytoken-transfer://v1?" +
            "session=${TransferFixtures.SESSION_ID}&host=localhost&port=52888" +
            "&publicKey=${publicKeyBase64Url()}&expiry=${TransferFixtures.EXPIRY_INSTANT}" +
            "&code=482913&extra=1"
        assertInvalid(raw)
    }

    @Test
    fun `rejects missing query key`() {
        val raw = "mytoken-transfer://v1?" +
            "session=${TransferFixtures.SESSION_ID}&host=localhost&port=52888" +
            "&publicKey=${publicKeyBase64Url()}&expiry=${TransferFixtures.EXPIRY_INSTANT}"
        assertInvalid(raw)
    }

    @Test
    fun `rejects duplicate query keys`() {
        val raw = "mytoken-transfer://v1?" +
            "session=${TransferFixtures.SESSION_ID}&session=${TransferFixtures.SESSION_ID}" +
            "&host=localhost&port=52888&publicKey=${publicKeyBase64Url()}" +
            "&expiry=${TransferFixtures.EXPIRY_INSTANT}&code=482913"
        assertInvalid(raw)
    }

    @Test
    fun `rejects fragment, port, user or path`() {
        assertInvalid("mytoken-transfer://v1:80?${query()}")
        assertInvalid("mytoken-transfer://user@v1?${query()}")
        assertInvalid("mytoken-transfer://v1/path?${query()}")
        assertInvalid("mytoken-transfer://v1?${query()}#fragment")
    }

    @Test
    fun `rejects invalid hosts`() {
        assertInvalid(validUri(host = "-bad.example.com"))
        assertInvalid(validUri(host = "bad-.example.com"))
        assertInvalid(validUri(host = "bad..example.com"))
        assertInvalid(validUri(host = "300.1.1.1"))
        assertInvalid(validUri(host = "1.2.3"))
        assertInvalid(validUri(host = "under_score.example.com"))
    }

    @Test
    fun `rejects out of range port`() {
        assertInvalid(validUri(port = 0))
        assertInvalid(validUri(port = 65_536))
    }

    @Test
    fun `rejects bad public key`() {
        assertInvalid(validUri(publicKey = "not-base64url!"))
        assertInvalid(validUri(publicKey = "")) // too short: 0 bytes
        assertInvalid(validUri(publicKey = "AAAA")) // 3 bytes, not 32
    }

    @Test
    fun `rejects malformed connection code`() {
        assertInvalid(validUri(code = "48291"))
        assertInvalid(validUri(code = "48291a"))
        assertInvalid(validUri(code = "0482913"))
    }

    @Test
    fun `rejects expired payload`() {
        val afterExpiry = Instant.parse("2027-01-15T08:00:00.001Z")
        val exception = assertThrows(TransferQrCodePayloadException::class.java) {
            TransferQrCodePayload.decode(TransferFixtures.QR_URI, afterExpiry)
        }
        assertEquals(TransferQrCodePayload.Reason.EXPIRED, exception.reason)
    }

    @Test
    fun `rejects expiry at exactly the current instant`() {
        val atExpiry = Instant.parse(TransferFixtures.EXPIRY_INSTANT)
        assertThrows(TransferQrCodePayloadException::class.java) {
            TransferQrCodePayload.decode(TransferFixtures.QR_URI, atExpiry)
        }
    }

    @Test
    fun `rejects non-fractional or non-UTC expiry`() {
        // Swift's formatter requires fractional seconds; mirror that strictness.
        assertInvalid(
            validUri(expiry = "2027-01-15T08:00:00Z")
        )
        assertInvalid(validUri(expiry = "2027-01-15T08:00:00+00:00"))
    }

    @Test
    fun `rejects garbage input`() {
        assertInvalid("not a uri")
        assertInvalid("")
        assertInvalid("https://example.com?session=1")
    }

    // -- helpers -------------------------------------------------------------

    private fun publicKeyBase64Url(): String =
        java.util.Base64.getUrlEncoder().withoutPadding()
            .encodeToString(TransferFixtures.MAC_PUBLIC_KEY)

    private fun query(
        host: String = "192.168.1.10",
        port: Int = 52888,
        publicKey: String = publicKeyBase64Url(),
        expiry: String = TransferFixtures.EXPIRY_INSTANT,
        code: String = "482913"
    ): String =
        "session=${TransferFixtures.SESSION_ID}&host=$host&port=$port" +
            "&publicKey=$publicKey&expiry=$expiry&code=$code"

    private fun validUri(
        host: String = "192.168.1.10",
        port: Int = 52888,
        publicKey: String = publicKeyBase64Url(),
        expiry: String = TransferFixtures.EXPIRY_INSTANT,
        code: String = "482913"
    ): String = "mytoken-transfer://v1?${query(host, port, publicKey, expiry, code)}"

    private fun validPayload(host: String): TransferQrCodePayload =
        TransferQrCodePayload.decode(validUri(host = host), now)

    private fun assertInvalid(raw: String) {
        val exception = assertThrows(TransferQrCodePayloadException::class.java) {
            TransferQrCodePayload.decode(raw, now)
        }
        // Any parse failure must be explicit; reason varies by violation.
        org.junit.Assert.assertNotNull(exception.reason)
    }
}
