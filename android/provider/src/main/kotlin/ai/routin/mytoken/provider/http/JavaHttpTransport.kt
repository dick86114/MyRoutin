package ai.routin.mytoken.provider.http

import java.net.URI
import java.net.http.HttpClient
import java.time.Duration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible

/** Production [HttpTransport] over the JDK built-in HTTP client (15s timeout, like the macOS client). */
class JavaHttpTransport(
    private val client: HttpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(15))
        .build(),
    private val requestTimeout: Duration = Duration.ofSeconds(15),
) : HttpTransport {

    override suspend fun execute(request: ProviderHttpRequest): ProviderHttpResponse =
        runInterruptible(Dispatchers.IO) {
            val builder = java.net.http.HttpRequest.newBuilder(URI.create(request.url))
                .timeout(requestTimeout)
            when (request.method.uppercase()) {
                "POST" -> builder.POST(
                    java.net.http.HttpRequest.BodyPublishers.ofByteArray(request.body ?: ByteArray(0))
                )
                "PUT" -> builder.PUT(
                    java.net.http.HttpRequest.BodyPublishers.ofByteArray(request.body ?: ByteArray(0))
                )
                else -> builder.GET()
            }
            for ((name, value) in request.headers) {
                builder.header(name, value)
            }
            val response = client.send(builder.build(), java.net.http.HttpResponse.BodyHandlers.ofByteArray())
            ProviderHttpResponse(response.statusCode(), response.body())
        }
}
