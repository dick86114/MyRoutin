package ai.routin.mytoken.core.crypto

import com.google.crypto.tink.subtle.X25519
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.random.Random

/**
 * X25519 + HKDF-SHA256 + AES-256-GCM primitives for the MyToken transfer
 * protocol, byte-compatible with the macOS implementation in
 * `RoutinUsage/Transfer/TransferSession.swift` (CryptoKit).
 *
 * Wire contract (protocol version 1):
 * - HKDF salt: UTF-8 bytes of the uppercase, hyphenated session UUID string.
 * - HKDF info: "mytoken-transfer/v{n}/hkdf-sha256".
 * - HKDF output: 32-byte AES-256 key.
 * - AEAD AAD: "mytoken-transfer/v{n}|{sessionID}" (same UUID format).
 * - AES-256-GCM with a random 12-byte nonce; ciphertext and the 16-byte
 *   authentication tag are carried as separate fields (CryptoKit layout).
 */
object CryptoSession {
    const val PROTOCOL_VERSION = 1
    const val NONCE_BYTE_SIZE = 12
    const val TAG_BYTE_SIZE = 16
    const val KEY_BYTE_SIZE = 32
    const val PUBLIC_KEY_BYTE_SIZE = 32

    /** HKDF shared info; includes the protocol version so key material is version-bound. */
    fun hkdfInfo(protocolVersion: Int): ByteArray =
        "mytoken-transfer/v$protocolVersion/hkdf-sha256".toByteArray(Charsets.UTF_8)

    /** AEAD associated data; binds every ciphertext to the protocol version and session ID. */
    fun associatedData(sessionId: String, protocolVersion: Int): ByteArray =
        "mytoken-transfer/v$protocolVersion|$sessionId".toByteArray(Charsets.UTF_8)

    /** HKDF-SHA256 (RFC 5869) extract-and-expand over the X25519 shared secret. */
    fun deriveSessionKey(
        sharedSecret: ByteArray,
        sessionId: String,
        protocolVersion: Int = PROTOCOL_VERSION
    ): ByteArray = hkdfSha256(
        ikm = sharedSecret,
        salt = sessionId.toByteArray(Charsets.UTF_8),
        info = hkdfInfo(protocolVersion),
        length = KEY_BYTE_SIZE
    )

    fun generateEphemeralKeyPair(random: Random = Random.Default): EphemeralKeyPair {
        val privateKey = ByteArray(PUBLIC_KEY_BYTE_SIZE).also(random::nextBytes)
        return EphemeralKeyPair(privateKey = privateKey, publicKey = X25519.publicFromPrivate(privateKey))
    }

    fun x25519SharedSecret(privateKey: ByteArray, peerPublicKey: ByteArray): ByteArray =
        X25519.computeSharedSecret(privateKey, peerPublicKey)

    /** Derives the 32-byte X25519 raw public key from a raw private key. */
    fun publicKeyFromPrivate(privateKey: ByteArray): ByteArray = X25519.publicFromPrivate(privateKey)

    /**
     * Seals plaintext with a fresh random 12-byte nonce. Returns the nonce,
     * ciphertext and authentication tag as separate parts so they can be
     * encoded exactly like the macOS `TransferEncryptedMessage`.
     */
    fun seal(
        plaintext: ByteArray,
        key: ByteArray,
        associatedData: ByteArray,
        random: Random = Random.Default
    ): GcmSealed {
        val nonce = ByteArray(NONCE_BYTE_SIZE).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BYTE_SIZE * 8, nonce))
        cipher.updateAAD(associatedData)
        val output = cipher.doFinal(plaintext)
        val ciphertext = output.copyOfRange(0, output.size - TAG_BYTE_SIZE)
        val tag = output.copyOfRange(output.size - TAG_BYTE_SIZE, output.size)
        return GcmSealed(nonce = nonce, ciphertext = ciphertext, authenticationTag = tag)
    }

    /** Opens a sealed message; throws a [javax.crypto.AEADBadTagException] subclass on tag/AAD mismatch. */
    fun open(
        nonce: ByteArray,
        ciphertext: ByteArray,
        authenticationTag: ByteArray,
        key: ByteArray,
        associatedData: ByteArray
    ): ByteArray {
        require(nonce.size == NONCE_BYTE_SIZE) { "invalid GCM nonce length ${nonce.size}" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BYTE_SIZE * 8, nonce))
        cipher.updateAAD(associatedData)
        return cipher.doFinal(ciphertext + authenticationTag)
    }

    internal fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..255 * 32) { "invalid HKDF output length $length" }
        val hmac = Mac.getInstance("HmacSHA256")
        // extract
        hmac.init(SecretKeySpec(if (salt.isEmpty()) ByteArray(32) else salt, "HmacSHA256"))
        val prk = hmac.doFinal(ikm)
        // expand
        hmac.init(SecretKeySpec(prk, "HmacSHA256"))
        val output = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            hmac.update(previous)
            hmac.update(info)
            hmac.update(counter.toByte())
            previous = hmac.doFinal()
            val count = minOf(previous.size, length - offset)
            System.arraycopy(previous, 0, output, offset, count)
            offset += count
            counter += 1
        }
        return output
    }
}

data class EphemeralKeyPair(val privateKey: ByteArray, val publicKey: ByteArray)

data class GcmSealed(
    val nonce: ByteArray,
    val ciphertext: ByteArray,
    val authenticationTag: ByteArray
)
