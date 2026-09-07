package ai.routin.mytoken

import ai.routin.mytoken.core.crypto.CryptoSession
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.feature.transfer.ImportConflictMode
import ai.routin.mytoken.feature.transfer.TransferClient
import ai.routin.mytoken.feature.transfer.TransferPackageCodec
import ai.routin.mytoken.feature.transfer.TransferQrCodePayload
import ai.routin.mytoken.feature.transfer.TransferRepositoryImpl
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Instrumented transfer flow test (requires a device/emulator; a CI runner
 * without devices cannot run it). Exercises the real [TransferRepositoryImpl]
 * against a loopback "simulated Mac" and an in-memory credential store.
 * All key material is synthetic test data; no real credentials are involved.
 */
class TransferFlowTest {
    private val sessionId = "5E7B0A62-9C1F-4E3A-8D2B-1F6C4A9E7D30"
    private val macPrivateKey = hex(
        "101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f"
    )
    private val packageJson =
        "{\"credentials\":[{\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"," +
            "\"credentialKind\":\"bearerAPIKey\",\"isEnabled\":true,\"metadata\":{},\"name\":\"Example Key\"," +
            "\"providerId\":\"deepseek\",\"schemaVersion\":1,\"sortOrder\":0}],\"exportedAt\":\"2026-09-07T03:00:00Z\"," +
            "\"preferences\":{\"alertThresholds\":[50,80],\"notificationsEnabled\":true,\"openAppRefresh\":true," +
            "\"pinnedCredentialIds\":[],\"refreshIntervalMinutes\":15,\"wifiOnly\":false},\"schemaVersion\":1," +
            "\"secretEnvelope\":{\"algorithm\":\"AES-256-GCM\",\"ciphertext\":\"AA\",\"entries\":[" +
            "{\"bearerToken\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D\"}]," +
            "\"ephemeralPublicKey\":\"AA\",\"keyAgreement\":\"X25519-HKDF-SHA256\",\"nonce\":\"AA\",\"tag\":\"AA\"}}"

    @Test
    fun transferFlowConnectsDecryptsAndImports() = runBlocking {
        LoopbackMacServer(sessionId, macPrivateKey, packageJson).use { server ->
            server.start()
            val now = Instant.parse("2026-09-07T03:00:00Z")
            val payload = TransferQrCodePayload.decode(
                "mytoken-transfer://v1?session=$sessionId&host=127.0.0.1&port=${server.port}" +
                    "&publicKey=${publicKeyBase64Url()}&expiry=2027-01-15T08:00:00.000Z&code=482913",
                now
            )
            val store = InMemoryCredentialStore()
            val repository = TransferRepositoryImpl(
                client = TransferClient(clock = Clock.fixed(now, ZoneOffset.UTC)),
                credentialRepository = store
            )

            val encrypted = repository.connect(payload).getOrThrow()
            val packageData = repository.decrypt(encrypted).getOrThrow()
            assertEquals(1, packageData.credentials.size)

            val summary = repository.import(packageData, ImportConflictMode.SKIP).getOrThrow()
            assertEquals(1, summary.importedCount)
            val secret = store.readSecret(UUID.fromString("A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"))
            assertTrue(secret is CredentialSecret.BearerToken)
        }
    }

    private fun publicKeyBase64Url(): String {
        // The QR key must be the raw Mac X25519 public key; derive it from the private key.
        val publicKey = CryptoSession.publicKeyFromPrivate(macPrivateKey)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(publicKey)
    }

    private fun hex(value: String): ByteArray =
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}

/** Minimal macOS-side protocol stand-in for instrumented testing. */
private class LoopbackMacServer(
    private val sessionId: String,
    private val macPrivateKey: ByteArray,
    private val packageJson: String
) : AutoCloseable {
    private val serverSocket = ServerSocket(0, 4, InetAddress.getLoopbackAddress())
    val port: Int = serverSocket.localPort
    private val thread = Thread { runCatching { serve() } }
    private val json = Json { ignoreUnknownKeys = true }

    fun start() {
        thread.isDaemon = true
        thread.start()
    }

    private fun serve() {
        val socket = serverSocket.accept()
        socket.use { connection ->
            val reader = BufferedReader(InputStreamReader(connection.getInputStream(), Charsets.UTF_8))
            val requestLine = reader.readLine() ?: return
            val request = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), requestLine)
            if (request["connectionCode"]?.jsonPrimitive?.content != "482913") return
            connection.getOutputStream().write("{\"ok\":true,\"protocolVersion\":1}\n".toByteArray())
            connection.getOutputStream().flush()
            val handshakeLine = reader.readLine() ?: return
            val handshake = json.decodeFromString(kotlinx.serialization.json.JsonObject.serializer(), handshakeLine)
            val androidPublicKey = Base64.getMimeDecoder()
                .decode(handshake["androidEphemeralPublicKey"]?.jsonPrimitive?.content ?: return)
            val sessionKey = CryptoSession.deriveSessionKey(
                CryptoSession.x25519SharedSecret(macPrivateKey, androidPublicKey),
                sessionId
            )
            val sealed = CryptoSession.seal(
                packageJson.toByteArray(Charsets.UTF_8),
                sessionKey,
                CryptoSession.associatedData(sessionId, 1)
            )
            val message = buildJsonObject {
                put("protocolVersion", JsonPrimitive(1))
                put("sessionID", JsonPrimitive(sessionId))
                put("nonce", JsonPrimitive(Base64.getEncoder().encodeToString(sealed.nonce)))
                put("ciphertext", JsonPrimitive(Base64.getEncoder().encodeToString(sealed.ciphertext)))
                put("authenticationTag", JsonPrimitive(Base64.getEncoder().encodeToString(sealed.authenticationTag)))
            }.toString()
            connection.getOutputStream().write((message + "\n").toByteArray())
            connection.getOutputStream().flush()
        }
    }

    override fun close() {
        runCatching { serverSocket.close() }
    }
}

/** Test double of the credential repository (secrets stay in memory). */
private class InMemoryCredentialStore : ai.routin.mytoken.domain.repository.CredentialRepository {
    private val credentials = LinkedHashMap<UUID, ai.routin.mytoken.domain.model.Credential>()
    private val secrets = LinkedHashMap<UUID, CredentialSecret>()
    private val flow = kotlinx.coroutines.flow.MutableStateFlow(credentials.values.toList())

    override fun observeCredentials(): kotlinx.coroutines.flow.Flow<List<ai.routin.mytoken.domain.model.Credential>> = flow

    override suspend fun save(credential: ai.routin.mytoken.domain.model.Credential, secret: CredentialSecret) {
        credentials[credential.id] = credential
        secrets[credential.id] = secret
        flow.value = credentials.values.toList()
    }

    override suspend fun delete(id: UUID) {
        credentials.remove(id)
        secrets.remove(id)
        flow.value = credentials.values.toList()
    }

    override suspend fun readSecret(id: UUID): CredentialSecret? = secrets[id]
}
