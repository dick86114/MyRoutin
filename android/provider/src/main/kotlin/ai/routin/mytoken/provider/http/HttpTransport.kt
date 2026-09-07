package ai.routin.mytoken.provider.http

/**
 * Minimal transport abstraction so provider adapters can be tested without a real
 * network. The production implementation wraps `java.net.http.HttpClient` (JDK built-in,
 * no extra dependency).
 */
fun interface HttpTransport {
    suspend fun execute(request: ProviderHttpRequest): ProviderHttpResponse
}

class ProviderHttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
) {
    override fun toString(): String =
        "ProviderHttpRequest(method=$method, url=$url, headers=${headers.keys}, bodyBytes=${body?.size})"
}

class ProviderHttpResponse(
    val statusCode: Int,
    val body: ByteArray,
)
