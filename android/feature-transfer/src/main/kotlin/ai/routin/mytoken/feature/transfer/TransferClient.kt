package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.core.crypto.CryptoSession
import ai.routin.mytoken.core.crypto.EphemeralKeyPair
import ai.routin.mytoken.domain.model.AppError
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.time.Clock
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Android client for the single-use macOS → Android transfer protocol.
 *
 * Sequence per connection (all messages are newline-terminated JSON lines):
 * 1. Android sends `TransferConnectionRequest{sessionID, connectionCode, macEphemeralPublicKey}`.
 * 2. macOS answers `{"ok":true,"protocolVersion":1}`.
 * 3. Android sends `TransferHandshake{sessionID, androidEphemeralPublicKey}`.
 * 4. macOS sends the AEAD-sealed `TransferEncryptedMessage`.
 *
 * Handshake buffering is capped at 64 KiB like the macOS server. No payload
 * content is ever logged.
 */
class TransferClient(
    private val clock: Clock = Clock.systemUTC(),
    private val connectTimeoutMillis: Int = 10_000,
    private val readTimeoutMillis: Int = 15_000,
    private val keyPairFactory: () -> EphemeralKeyPair = CryptoSession::generateEphemeralKeyPair
) {
    suspend fun connect(payload: TransferQrCodePayload): Result<EncryptedTransferPackage> =
        withContext(Dispatchers.IO) {
            try {
                Result.success(connectInternal(payload))
            } catch (cause: Throwable) {
                Result.failure(mapIoError(cause))
            }
        }

    private fun connectInternal(payload: TransferQrCodePayload): EncryptedTransferPackage {
        payload.validate(clock.instant())

        Socket().use { socket ->
            try {
                socket.connect(InetSocketAddress(payload.host, payload.port), connectTimeoutMillis)
                socket.soTimeout = readTimeoutMillis
            } catch (cause: IOException) {
                // Re-map below so unreachable hosts surface as network errors.
                throw cause
            }

            val output = socket.getOutputStream()
            val input = socket.getInputStream()

            val request = TransferConnectionRequest(
                sessionId = payload.sessionId,
                connectionCode = payload.connectionCode,
                macEphemeralPublicKey = Base64.getEncoder().encodeToString(payload.macEphemeralPublicKey)
            )
            writeLine(output, TransferWireCodec.encodeConnectionRequest(request))

            val ack = TransferWireCodec.decodeAck(readLine(input))
            if (!ack.ok || ack.protocolVersion != CryptoSession.PROTOCOL_VERSION) {
                throw AppError.Authentication("transfer connection was not accepted")
            }

            val keyPair = keyPairFactory()
            val handshake = TransferHandshake(
                sessionId = payload.sessionId,
                androidEphemeralPublicKey = Base64.getEncoder().encodeToString(keyPair.publicKey)
            )
            writeLine(output, TransferWireCodec.encodeHandshake(handshake))

            val message = TransferWireCodec.decodeEncryptedMessage(readLine(input))
            val sharedSecret = try {
                CryptoSession.x25519SharedSecret(keyPair.privateKey, payload.macEphemeralPublicKey)
            } catch (_: IllegalArgumentException) {
                throw AppError.Authentication("invalid mac ephemeral public key")
            }
            val sessionKey = CryptoSession.deriveSessionKey(sharedSecret, payload.sessionId)
            return EncryptedTransferPackage(
                sessionId = payload.sessionId,
                message = message,
                sessionKey = sessionKey
            )
        }
    }

    private fun mapIoError(cause: Throwable): Exception = when (cause) {
        is AppError -> cause
        is TransferQrCodePayloadException ->
            if (cause.reason == TransferQrCodePayload.Reason.EXPIRED) {
                AppError.Authentication("transfer session expired")
            } else {
                AppError.Decode("invalid transfer QR payload: ${cause.reason.name}")
            }
        is SocketTimeoutException -> AppError.Network("transfer connection timed out")
        is IOException -> AppError.Network("cannot reach transfer host: ${cause.javaClass.simpleName}")
        is kotlinx.serialization.SerializationException -> AppError.Decode("malformed transfer wire message")
        else -> AppError.Unknown("transfer failed", cause)
    }

    private fun writeLine(output: java.io.OutputStream, line: String) {
        output.write((line + "\n").toByteArray(Charsets.UTF_8))
        output.flush()
    }

    /** Reads one newline-terminated line with the 64 KiB handshake buffer cap. */
    private fun readLine(input: java.io.InputStream): String {
        val buffer = ByteArrayOutputStream()
        while (true) {
            val read = input.read()
            if (read == -1) {
                throw AppError.Network("transfer connection closed before a complete message")
            }
            if (read == '\n'.code) break
            buffer.write(read)
            if (buffer.size() > MAX_LINE_BYTES) {
                throw AppError.Network("transfer message exceeded 64 KiB buffer limit")
            }
        }
        return buffer.toString("UTF-8")
    }

    companion object {
        const val MAX_LINE_BYTES = 64 * 1024
    }
}
