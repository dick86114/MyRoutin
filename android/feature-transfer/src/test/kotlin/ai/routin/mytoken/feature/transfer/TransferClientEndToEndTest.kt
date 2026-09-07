package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.core.crypto.CryptoSession
import ai.routin.mytoken.domain.model.AppError
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * JVM end-to-end interop test: a loopback "simulated Mac" server implements
 * the macOS transfer protocol byte-for-byte and speaks to the real
 * [TransferClient] over a real TCP socket.
 */
class TransferClientEndToEndTest {
    private lateinit var server: FakeMacServer
    private val now: Instant = TransferFixtures.NOW
    private val clock = Clock.fixed(now, ZoneOffset.UTC)

    @Before
    fun setUp() {
        server = FakeMacServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.close()
    }

    private fun payload(): TransferQrCodePayload = TransferQrCodePayload.decode(
        TransferFixtures.QR_URI
            .replace("192.168.1.10", "127.0.0.1")
            .replace("port=52888", "port=${server.port}"),
        now
    )

    @Test
    fun `full happy path - connect, decrypt, validate package`() = runTestBlocking {
        val client = TransferClient(clock)
        val result = client.connect(payload())
        val encrypted = result.getOrThrow()

        assertEquals(TransferFixtures.SESSION_ID, encrypted.sessionId)
        // The simulated Mac sealed the package with the CryptoKit-derived key;
        // the client must derive the same key from its own X25519 share.
        assertTrue(server.receivedHandshake.await(5, TimeUnit.SECONDS))
        assertEquals(TransferFixtures.SESSION_ID, server.receivedSessionId)
        assertEquals("482913", server.receivedConnectionCode)

        val decrypted = runTestBlocking {
            // Decrypt with the client's own session key.
            val repo = TransferRepositoryImpl(client, FakeCredentialRepository())
            repo.decrypt(encrypted).getOrThrow()
        }
        assertEquals(1, decrypted.credentials.size)
        assertEquals("deepseek", decrypted.credentials[0].providerId)
        assertEquals(1, decrypted.secretEnvelope.entries.size)
    }

    @Test
    fun `decrypt with tampered ciphertext fails authentication`() = runTestBlocking {
        val client = TransferClient(clock)
        val encrypted = client.connect(payload()).getOrThrow()
        val repo = TransferRepositoryImpl(client, FakeCredentialRepository())

        val tampered = TransferEncryptedMessage(
            protocolVersion = encrypted.message.protocolVersion,
            sessionId = encrypted.message.sessionId,
            nonce = encrypted.message.nonce,
            ciphertext = flipOneBit(encrypted.message.ciphertext),
            authenticationTag = encrypted.message.authenticationTag
        )
        val result = repo.decrypt(EncryptedTransferPackage(encrypted.sessionId, tampered, encrypted.sessionKey))
        val error = result.exceptionOrNull()
        assertTrue("expected Authentication error but was $error", error is AppError.Authentication)
    }

    @Test
    fun `decrypt with mismatched session id fails authentication`() = runTestBlocking {
        val client = TransferClient(clock)
        val encrypted = client.connect(payload()).getOrThrow()
        val repo = TransferRepositoryImpl(client, FakeCredentialRepository())

        val mismatched = encrypted.message.copy(
            sessionId = "00000000-0000-0000-0000-000000000000"
        )
        val result = repo.decrypt(EncryptedTransferPackage(encrypted.sessionId, mismatched, encrypted.sessionKey))
        assertTrue(result.exceptionOrNull() is AppError.Authentication)
    }

    @Test
    fun `expired payload is rejected before connecting`() = runTestBlocking {
        val afterExpiry = Clock.fixed(Instant.parse("2027-01-15T08:00:00.001Z"), ZoneOffset.UTC)
        val client = TransferClient(afterExpiry)
        val result = client.connect(payload())
        assertTrue(result.exceptionOrNull() is AppError.Authentication)
        assertEquals(0, server.connectionCount.get())
    }

    @Test
    fun `unreachable host surfaces as network error`() = runTestBlocking {
        // Reserve then release a port so nothing is listening.
        val closedPort = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { it.localPort }
        val rawUri = TransferFixtures.QR_URI
            .replace("192.168.1.10", "127.0.0.1")
            .replace("port=52888", "port=$closedPort")
        val client = TransferClient(clock)
        val result = client.connect(TransferQrCodePayload.decode(rawUri, now))
        val error = result.exceptionOrNull()
        assertTrue("expected Network error but was $error", error is AppError.Network)
    }

    @Test
    fun `wrong connection code gets no ack and fails`() {
        server.acceptScenario = FakeMacServer.Scenario.WRONG_CODE
        val client = TransferClient(clock)
        val result = runTestBlocking { client.connect(payload()) }
        val error = result.exceptionOrNull()
        assertTrue(
            "expected failure but was ${result.getOrNull()}",
            error is AppError.Network || error is AppError.Authentication
        )
    }

    @Test
    fun `oversized line is rejected at the 64 KiB buffer cap`() {
        server.acceptScenario = FakeMacServer.Scenario.OVERSIZE_ACK
        val client = TransferClient(clock)
        val result = runTestBlocking { client.connect(payload()) }
        assertTrue(result.exceptionOrNull() is AppError.Network)
    }

    private fun flipOneBit(base64: String): String {
        val bytes = Base64.getMimeDecoder().decode(base64)
        bytes[0] = (bytes[0].toInt() xor 0x01).toByte()
        return Base64.getEncoder().encodeToString(bytes)
    }
}

/**
 * Minimal macOS-side protocol implementation used only in tests. All key
 * material is synthetic; nothing here touches production credentials.
 */
class FakeMacServer : AutoCloseable {
    enum class Scenario { HAPPY, WRONG_CODE, OVERSIZE_ACK }

    var acceptScenario = Scenario.HAPPY

    private val serverSocket = ServerSocket(0, 4, InetAddress.getLoopbackAddress())
    val port: Int = serverSocket.localPort
    val connectionCount = java.util.concurrent.atomic.AtomicInteger()
    val receivedHandshake = CountDownLatch(1)
    var receivedSessionId: String? = null
        private set
    var receivedConnectionCode: String? = null
        private set

    private val thread = Thread { runCatching { serve() } }
    private val json = Json { ignoreUnknownKeys = true }

    fun start() {
        thread.isDaemon = true
        thread.start()
    }

    private fun serve() {
        val socket = serverSocket.accept()
        connectionCount.incrementAndGet()
        socket.use { connection ->
            val reader = BufferedReader(InputStreamReader(connection.getInputStream(), Charsets.UTF_8))
            val requestLine = reader.readLine() ?: return
            val request = json.decodeFromString(JsonObject.serializer(), requestLine)
            val sessionId = request["sessionID"]?.jsonPrimitive?.content ?: return
            val code = request["connectionCode"]?.jsonPrimitive?.content ?: return
            val macPublicKey = request["macEphemeralPublicKey"]?.jsonPrimitive?.content ?: return

            if (code != "482913" || sessionId != TransferFixtures.SESSION_ID) {
                // macOS rejects: closes the connection without an ack.
                return
            }
            assertEquals(
                "mac public key must be standard padded base64 of the raw key",
                TransferFixtures.MAC_PUBLIC_KEY.toList(),
                Base64.getMimeDecoder().decode(macPublicKey).toList()
            )

            when (acceptScenario) {
                Scenario.WRONG_CODE -> return
                Scenario.OVERSIZE_ACK -> {
                    connection.getOutputStream().write(("x".repeat(64 * 1024 + 1) + "\n").toByteArray())
                    connection.getOutputStream().flush()
                    return
                }
                Scenario.HAPPY -> Unit
            }

            connection.getOutputStream().write("{\"ok\":true,\"protocolVersion\":1}\n".toByteArray())
            connection.getOutputStream().flush()

            val handshakeLine = reader.readLine() ?: return
            val handshake = json.decodeFromString(JsonObject.serializer(), handshakeLine)
            assertEquals(TransferFixtures.SESSION_ID, handshake["sessionID"]?.jsonPrimitive?.content)
            val androidPublicKey = Base64.getMimeDecoder()
                .decode(handshake["androidEphemeralPublicKey"]?.jsonPrimitive?.content ?: return)
            receivedSessionId = sessionId
            receivedConnectionCode = code

            // Derive the session key exactly like TransferSession.acceptHandshake.
            val sharedSecret = CryptoSession.x25519SharedSecret(
                TransferFixtures.MAC_PRIVATE_KEY,
                androidPublicKey
            )
            val sessionKey = CryptoSession.deriveSessionKey(sharedSecret, TransferFixtures.SESSION_ID)

            val sealed = CryptoSession.seal(
                plaintext = TransferFixtures.PACKAGE_JSON.toByteArray(Charsets.UTF_8),
                key = sessionKey,
                associatedData = CryptoSession.associatedData(TransferFixtures.SESSION_ID, 1)
            )

            // Emit the message exactly like macOS JSONEncoder would (standard base64).
            val messageJson = JsonObject(
                mapOf(
                    "protocolVersion" to JsonPrimitive(1),
                    "sessionID" to JsonPrimitive(TransferFixtures.SESSION_ID),
                    "nonce" to JsonPrimitive(Base64.getEncoder().encodeToString(sealed.nonce)),
                    "ciphertext" to JsonPrimitive(Base64.getEncoder().encodeToString(sealed.ciphertext)),
                    "authenticationTag" to JsonPrimitive(Base64.getEncoder().encodeToString(sealed.authenticationTag))
                )
            ).toString()
            connection.getOutputStream().write((messageJson + "\n").toByteArray())
            connection.getOutputStream().flush()
            receivedHandshake.countDown()
        }
    }

    override fun close() {
        runCatching { serverSocket.close() }
    }
}

private fun <T> runTestBlocking(block: suspend () -> T): T =
    kotlinx.coroutines.runBlocking { withTimeout(15_000) { block() } }
