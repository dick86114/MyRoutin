package ai.routin.mytoken.provider.http

import java.net.HttpURLConnection
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible

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

    private companion object {
        const val DEFAULT_TIMEOUT_MILLIS = 15_000
    }
}
