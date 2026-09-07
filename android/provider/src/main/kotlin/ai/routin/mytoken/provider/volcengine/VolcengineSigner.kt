package ai.routin.mytoken.provider.volcengine

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.security.MessageDigest

/** Volcengine HMAC-SHA256 request signer, aligned with the macOS VolcengineSigning.swift implementation. */
class VolcengineSigner(
    val service: String = "ark",
    val requestType: String = "request",
) {
    data class Credential(
        val accessKeyID: String,
        val secretAccessKey: String,
        val region: String,
    )

    fun sign(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: ByteArray,
        credential: Credential,
        timestamp: java.time.Instant,
    ): Map<String, String> {
        val timestampText = TIMESTAMP_FORMATTER.format(timestamp)
        val dateStamp = timestampText.substring(0, 8)
        val signedHeaders = headers.toMutableMap()
        val uri = java.net.URI(url)
        signedHeaders["Host"] = uri.host ?: ""
        signedHeaders["X-Date"] = timestampText
        signedHeaders["X-Content-Sha256"] = hexDigest(body)

        val canonicalHeaders = signedHeaders.entries
            .map { it.key.lowercase() to it.value.trim() }
            .sortedBy { it.first }
            .joinToString("") { "${it.first}:${it.second}\n" }
        val signedHeaderNames = signedHeaders.keys.map { it.lowercase() }.sorted().joinToString(";")
        val canonicalQuery = canonicalQuery(uri)
        val canonicalRequest = listOf(
            method.uppercase(),
            uri.path?.takeIf { it.isNotEmpty() } ?: "/",
            canonicalQuery,
            canonicalHeaders,
            signedHeaderNames,
            signedHeaders["X-Content-Sha256"]!!
        ).joinToString("\n")

        val scope = "$dateStamp/${credential.region}/$service/$requestType"
        val stringToSign = listOf(
            "HMAC-SHA256",
            timestampText,
            scope,
            hexDigest(canonicalRequest.toByteArray())
        ).joinToString("\n")

        var key = hmac(credential.secretAccessKey.toByteArray(), dateStamp)
        key = hmac(key, credential.region)
        key = hmac(key, service)
        key = hmac(key, requestType)
        val signature = hex(hmac(key, stringToSign))

        signedHeaders["Authorization"] =
            "HMAC-SHA256 Credential=${credential.accessKeyID}/$scope, " +
                "SignedHeaders=$signedHeaderNames, Signature=$signature"
        return signedHeaders
    }

    private fun canonicalQuery(uri: java.net.URI): String {
        val rawQuery = uri.rawQuery ?: return ""
        return rawQuery.split("&")
            .filter { it.isNotEmpty() }
            .map { pair ->
                val index = pair.indexOf('=')
                if (index < 0) {
                    percentEncode(pair) to ""
                } else {
                    percentEncode(pair.substring(0, index)) to percentEncode(pair.substring(index + 1))
                }
            }
            .sortedWith(compareBy({ it.first }, { it.second }))
            .joinToString("&") { "${it.first}=${it.second}" }
    }

    private fun percentEncode(value: String): String {
        val builder = StringBuilder()
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt().toChar()
            if (c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_' || c == '.' || c == '~') {
                builder.append(c)
            } else {
                builder.append('%')
                builder.append("%02X".format(byte))
            }
        }
        return builder.toString()
    }

    private fun hmac(key: ByteArray, message: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(message.toByteArray())
    }

    private fun hexDigest(data: ByteArray): String = hex(
        MessageDigest.getInstance("SHA-256").digest(data)
    )

    private fun hex(data: ByteArray): String = data.joinToString("") { "%02x".format(it) }

    companion object {
        private val TIMESTAMP_FORMATTER =
            java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
                .withZone(java.time.ZoneOffset.UTC)
    }
}
