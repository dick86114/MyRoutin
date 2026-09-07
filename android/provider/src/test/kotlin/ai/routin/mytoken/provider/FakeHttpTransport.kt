package ai.routin.mytoken.provider

import ai.routin.mytoken.provider.http.ProviderHttpRequest
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.http.HttpTransport

/** Test double capturing requests and replaying queued responses. */
class FakeHttpTransport : HttpTransport {
    val requests = mutableListOf<ProviderHttpRequest>()

    /** Responses consumed in order; the last one repeats when the queue is exhausted. */
    val responses = ArrayDeque<ProviderHttpResponse>()

    override suspend fun execute(request: ProviderHttpRequest): ProviderHttpResponse {
        requests += request
        check(responses.isNotEmpty()) { "No canned response configured" }
        return responses.removeFirst()
    }
}
