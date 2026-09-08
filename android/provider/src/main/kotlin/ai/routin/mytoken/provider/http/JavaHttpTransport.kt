package ai.routin.mytoken.provider.http

import ai.routin.mytoken.domain.usage.UsageProviderException
import java.net.HttpURLConnection
import java.net.URI
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withTimeout

/**
 * Production [HttpTransport] over Android's built-in [HttpURLConnection]
 * (15s timeouts, like the macOS client). Deliberately avoids
 * `java.net.http.HttpClient`, which does not exist on Android.
 */
class JavaHttpTransport(
    private val connectTimeoutMillis: Int = DEFAULT_TIMEOUT_MILLIS,
    private val requestTimeoutMillis: Int = DEFAULT_TIMEOUT_MILLIS,
) : HttpTransport {

    override suspend fun execute(request: ProviderHttpRequest): ProviderHttpResponse =
        try {
            withTimeout(requestTimeoutMillis + TIMEOUT_GRACE_MILLIS) {
                runInterruptible(Dispatchers.IO) {
                    val method = when (request.method.uppercase()) {
                        "POST" -> "POST"
                        "PUT" -> "PUT"
                        else -> "GET"
                    }
                    val connection = URI.create(request.url).toURL().openConnection() as HttpURLConnection
                    try {
                        connection.apply {
                            connectTimeout = connectTimeoutMillis
                            readTimeout = requestTimeoutMillis
                            requestMethod = method
                            for ((name, value) in request.headers) {
                                addRequestProperty(name, value)
                            }
                            if (request.body != null && method != "GET") {
                                doOutput = true
                                setFixedLengthStreamingMode(request.body.size)
                            }
                        }
                        if (request.body != null && method != "GET") {
                            connection.outputStream.use { it.write(request.body) }
                        }
                        val statusCode = connection.responseCode
                        val body = (connection.inputStream.takeIf { statusCode in 200..299 }
                            ?: connection.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
                        ProviderHttpResponse(statusCode, body)
                    } finally {
                        connection.disconnect()
                    }
                }
            }
        } catch (error: TimeoutCancellationException) {
            // HttpURLConnection 的 DNS 阶段可能不受 connect/read timeout 约束，
            // 这里把整个请求包一层协程超时，避免 UI 永远停留在“刷新中”。
            throw UsageProviderException.Transport("网络请求超时")
        }

    private companion object {
        const val DEFAULT_TIMEOUT_MILLIS = 15_000
        const val TIMEOUT_GRACE_MILLIS = 5_000L
    }
}
