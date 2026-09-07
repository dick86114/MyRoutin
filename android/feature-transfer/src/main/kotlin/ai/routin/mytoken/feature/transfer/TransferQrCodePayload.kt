package ai.routin.mytoken.feature.transfer

import java.time.Instant
import java.util.Base64
import java.util.Locale

/** Thrown for any structural or temporal violation of the transfer QR contract. */
class TransferQrCodePayloadException(val reason: TransferQrCodePayload.Reason) :
    Exception("invalid transfer QR payload: ${reason.name}")

/**
 * Android-side mirror of `RoutinUsage/Transfer/TransferQRCodePayload.swift`.
 * Parses `mytoken-transfer://v1?...` QR payloads with the same strict rules:
 * exact scheme/host, no port/user/password/fragment/path, exactly the six
 * expected query keys with no duplicates, UUID session, validated host and
 * port, 32-byte base64url public key, fractional-second ISO8601 expiry in the
 * future, and a six-digit connection code.
 */
data class TransferQrCodePayload(
    val protocolVersion: Int,
    val sessionId: String,
    val host: String,
    val port: Int,
    val macEphemeralPublicKey: ByteArray,
    val expiresAt: Instant,
    val connectionCode: String
) {
    /** Structural checks plus expiry against [now]. */
    fun validate(now: Instant) {
        validateStructure()
        if (!expiresAt.isAfter(now)) throw TransferQrCodePayloadException(Reason.EXPIRED)
    }

    private fun validateStructure() {
        if (protocolVersion != SUPPORTED_PROTOCOL_VERSION) {
            throw TransferQrCodePayloadException(Reason.UNSUPPORTED_VERSION)
        }
        if (!isValidHost(host)) throw TransferQrCodePayloadException(Reason.INVALID_HOST)
        if (port !in 1..65_535) throw TransferQrCodePayloadException(Reason.INVALID_PORT)
        if (macEphemeralPublicKey.size != 32) throw TransferQrCodePayloadException(Reason.INVALID_PUBLIC_KEY)
        if (connectionCode.length != 6 || connectionCode.any { !it.isDigit() }) {
            throw TransferQrCodePayloadException(Reason.INVALID_CONNECTION_CODE)
        }
    }

    enum class Reason {
        UNSUPPORTED_VERSION,
        INVALID_HOST,
        INVALID_PORT,
        INVALID_PUBLIC_KEY,
        INVALID_CONNECTION_CODE,
        EXPIRED,
        INVALID_ENCODING
    }

    companion object {
        const val SUPPORTED_PROTOCOL_VERSION = 1
        const val SCHEME = "mytoken-transfer"

        /** Decodes a scanned QR string. Throws [TransferQrCodePayloadException] on any violation. */
        fun decode(raw: String, now: Instant): TransferQrCodePayload {
            val uri = try {
                java.net.URI(raw.trim())
            } catch (_: Exception) {
                throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            }
            if (uri.scheme?.lowercase(Locale.US) != SCHEME ||
                uri.host != "v$SUPPORTED_PROTOCOL_VERSION" ||
                uri.port != -1 ||
                uri.userInfo != null ||
                uri.fragment != null ||
                !uri.rawPath.isNullOrEmpty()
            ) {
                throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            }
            val rawQuery = uri.rawQuery ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            val values = parseQuery(rawQuery)
            val expectedKeys = setOf("session", "host", "port", "publicKey", "expiry", "code")
            if (values.keys != expectedKeys) {
                throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            }
            val sessionId = values["session"]?.let { parseUuid(it) }
                ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            val host = values["host"]!!
            val port = values["port"]?.toIntOrNull()
                ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            val publicKey = values["publicKey"]?.let(::decodeBase64Url)
                ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            val expiresAt = values["expiry"]?.let(::parseIso8601)
                ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
            val code = values["code"]!!
            val payload = TransferQrCodePayload(
                protocolVersion = SUPPORTED_PROTOCOL_VERSION,
                sessionId = sessionId,
                host = host,
                port = port,
                macEphemeralPublicKey = publicKey,
                expiresAt = expiresAt,
                connectionCode = code
            )
            payload.validate(now)
            return payload
        }

        /** Strict UUID: uppercase or lowercase, hyphenated 8-4-4-4-12 hex groups. */
        private fun parseUuid(value: String): String? {
            if (!Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
                .matches(value)
            ) {
                return null
            }
            return try {
                java.util.UUID.fromString(value).toString().uppercase(Locale.US)
            } catch (_: IllegalArgumentException) {
                null
            }
        }

        /** Parses macOS `ISO8601DateFormatter` output: fractional seconds required, `Z` zone. */
        private fun parseIso8601(value: String): Instant? {
            if (!Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d+Z$").matches(value)) return null
            return try {
                Instant.parse(value)
            } catch (_: Exception) {
                null
            }
        }

        private fun parseQuery(rawQuery: String): Map<String, String> {
            if (rawQuery.isEmpty()) return emptyMap()
            val result = LinkedHashMap<String, String>()
            for (pair in rawQuery.split('&')) {
                if (pair.isEmpty()) throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
                val separator = pair.indexOf('=')
                val name = if (separator == -1) pair else pair.substring(0, separator)
                val value = if (separator == -1) "" else pair.substring(separator + 1)
                val decodedName = percentDecode(name) ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
                val decodedValue = percentDecode(value) ?: throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
                if (result.containsKey(decodedName)) {
                    throw TransferQrCodePayloadException(Reason.INVALID_ENCODING)
                }
                result[decodedName] = decodedValue
            }
            return result
        }

        /** Percent-decoding without `URLDecoder`'s `+`-to-space conversion (matches URLComponents). */
        private fun percentDecode(value: String): String? {
            if ('%' !in value) return value
            val bytes = java.io.ByteArrayOutputStream()
            var index = 0
            val chars = value.toByteArray(Charsets.US_ASCII)
            while (index < chars.size) {
                val current = chars[index].toInt()
                if (current == '%'.code) {
                    if (index + 2 >= chars.size) return null
                    val hexPair = value.substring(index + 1, index + 3)
                    val byteValue = hexPair.toIntOrNull(16) ?: return null
                    bytes.write(byteValue)
                    index += 3
                } else {
                    bytes.write(current)
                    index += 1
                }
            }
            return bytes.toString("UTF-8")
        }

        /** Same host grammar as `TransferQRCodePayload.isValidHost`. */
        private fun isValidHost(value: String): Boolean {
            if (value.isEmpty() || value.toByteArray(Charsets.UTF_8).size > 253) return false
            if (value.any { it.code !in 0x21..0x7E || it in "/\\?#@:[]" }) return false
            if (value == "localhost") return true
            val labels = value.split(".")
            val looksNumeric = value.all { it.isDigit() || it == '.' }
            if (looksNumeric) {
                if (labels.size != 4) return false
                return labels.all { label ->
                    label.isNotEmpty() && label.all { it.isDigit() } && label.toIntOrNull() in 0..255
                }
            }
            return labels.all { label ->
                if (label.isEmpty() || label.length > 63) return@all false
                if (!label.first().isLetterOrDigit() || !label.last().isLetterOrDigit()) return@all false
                label.all { it.isLetterOrDigit() || it == '-' }
            }
        }

        /** Unpadded base64url with the same lexical rules as the macOS decoder. */
        private fun decodeBase64Url(value: String): ByteArray? {
            if (value.isEmpty() || value.length % 4 == 1) return null
            if (value.any { !(it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_') }) {
                return null
            }
            return try {
                val padded = value + "=".repeat((4 - value.length % 4) % 4)
                Base64.getUrlDecoder().decode(padded)
            } catch (_: IllegalArgumentException) {
                null
            }
        }
    }
}
