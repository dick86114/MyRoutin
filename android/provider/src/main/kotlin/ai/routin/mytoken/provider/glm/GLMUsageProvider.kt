package ai.routin.mytoken.provider.glm

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.UsageProvider
import ai.routin.mytoken.domain.usage.UsageProviderException
import ai.routin.mytoken.provider.health.UsageMetricHealthEvaluator
import ai.routin.mytoken.provider.http.HttpTransport
import ai.routin.mytoken.provider.http.ProviderHttpRequest
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.json.ProviderJson
import ai.routin.mytoken.provider.json.arrayOrNull
import ai.routin.mytoken.provider.json.asObjectOrNull
import ai.routin.mytoken.provider.json.decimalOrNull
import ai.routin.mytoken.provider.json.intOrNull
import ai.routin.mytoken.provider.json.longOrNull
import ai.routin.mytoken.provider.json.objOrNull
import ai.routin.mytoken.provider.json.stringOrNull
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlinx.serialization.json.JsonObject

/**
 * GLM Coding Plan usage adapter, aligned with the macOS GLMUsageProvider:
 * two GET requests (model usage + quota limit) with a raw Authorization header,
 * metric order [five-hour, weekly, model-calls, zcode-mcp].
 */
class GLMUsageProvider(
    private val transport: HttpTransport,
    private val clock: Clock = Clock.systemUTC(),
    private val defaultBaseURL: String = DEFAULT_BASE_URL,
) : UsageProvider {

    override val providerId: ProviderId = ProviderId.Glm

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        if (credential.providerId != ProviderId.Glm || credential.credentialKind != CredentialKind.ApiKey) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }
        val key = (secret as? CredentialSecret.ApiKey)?.key
            ?: return Result.failure(UsageProviderException.InvalidCredential())
        if (key.isEmpty()) return Result.failure(UsageProviderException.InvalidCredential())

        val baseURL = credential.metadata[CredentialMetadataKey.BaseURL]?.takeIf { it.isNotBlank() }
            ?: defaultBaseURL
        val query = "?startTime=${encode(windowStart())}&endTime=${encode(windowEnd())}"

        val modelResponse = try {
            request(url = baseURL.trimEnd('/') + MODEL_USAGE_PATH + query, key = key)
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            return Result.failure(error as? UsageProviderException ?: UsageProviderException.Transport())
        }
        val quotaResponse = try {
            request(url = baseURL.trimEnd('/') + QUOTA_LIMIT_PATH + query, key = key)
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            return Result.failure(error as? UsageProviderException ?: UsageProviderException.Transport())
        }

        return runCatching {
            mapResponses(modelResponse, quotaResponse, credential.id)
        }.recoverCatching { error ->
            if (error is UsageProviderException) throw error
            throw UsageProviderException.InvalidResponse()
        }
    }

    private suspend fun request(url: String, key: String): ProviderHttpResponse {
        val response = transport.execute(
            ProviderHttpRequest(
                method = "GET",
                url = url,
                headers = mapOf(
                    "Authorization" to key,
                    "Content-Type" to "application/json",
                    "Accept-Language" to "en-US,en"
                )
            )
        )
        if (response.statusCode !in 200..299) {
            throw when (response.statusCode) {
                401, 403 -> UsageProviderException.Unauthorized()
                429 -> UsageProviderException.RateLimited()
                in 500..599 -> UsageProviderException.ProviderUnavailable()
                else -> UsageProviderException.InvalidResponse()
            }
        }
        return response
    }

    private fun mapResponses(modelResponse: ProviderHttpResponse, quotaResponse: ProviderHttpResponse, credentialId: java.util.UUID): UsageSnapshot {
        val modelRoot = ProviderJson.parse(modelResponse.body.decodeToString()).asObjectOrNull()
        val quotaRoot = ProviderJson.parse(quotaResponse.body.decodeToString()).asObjectOrNull()

        val quotaMetrics = quotaMetrics(quotaRoot)
        val metrics = buildList {
            addAll(quotaMetrics.filter { it.id != "zcode-mcp" })
            modelCallMetric(modelRoot)?.let { add(it) }
            quotaMetrics.firstOrNull { it.id == "zcode-mcp" }?.let { add(it) }
        }
        if (metrics.isEmpty()) throw UsageProviderException.InvalidResponse()

        return UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = clock.instant(),
            planName = "Coding Plan",
            metrics = metrics
        )
    }

    private fun quotaMetrics(root: JsonObject?): List<UsageMetric> {
        val limits = root?.objOrNull("data")?.arrayOrNull("limits")
            ?: root?.arrayOrNull("limits")
            ?: return emptyList()

        var fiveHour: UsageMetric? = null
        var weekly: UsageMetric? = null
        var zcodeMcp: UsageMetric? = null

        for (item in limits) {
            val obj = item.asObjectOrNull() ?: continue
            val percentage = obj.decimalOrNull("percentage") ?: continue
            val type = obj.stringOrNull("type") ?: "quota"
            val unit = obj.intOrNull("unit")
            val number = obj.intOrNull("number")
            val windowEnd = obj.longOrNull("nextResetTime")?.let { Instant.ofEpochMilli(it) }

            when {
                type == "TOKENS_LIMIT" && unit == 3 && number == 5 ->
                    fiveHour = percentMetric(id = "five-hour", label = "5 小时用量", percentage = percentage, windowEnd = windowEnd)
                type == "TOKENS_LIMIT" && unit == 6 && number == 1 ->
                    weekly = percentMetric(id = "weekly", label = "每周用量", percentage = percentage, windowEnd = windowEnd)
                type == "TIME_LIMIT" -> {
                    val limit = obj.decimalOrNull("usage") ?: BigDecimal(100)
                    val used = obj.decimalOrNull("currentValue") ?: percentage
                    val remaining = obj.decimalOrNull("remaining")
                        ?: limit.subtract(used).max(BigDecimal.ZERO)
                    zcodeMcp = UsageMetric(
                        id = "zcode-mcp",
                        label = "MCP 调用量",
                        used = used,
                        limit = limit,
                        remaining = remaining,
                        value = used,
                        unit = UsageMetricUnit.Request,
                        windowEnd = windowEnd,
                        presentation = UsageMetricPresentation.Value,
                        semantic = UsageMetricSemantic.UsedQuota,
                        healthState = UsageMetricHealthEvaluator.fromPercent(percentage.toDouble())
                    )
                }
            }
        }
        return listOfNotNull(fiveHour, weekly, zcodeMcp)
    }

    private fun modelCallMetric(root: JsonObject?): UsageMetric? {
        val count = root?.objOrNull("data")?.objOrNull("totalUsage")
            ?.decimalOrNull("totalModelCallCount") ?: return null
        return UsageMetric(
            id = "model-calls",
            label = "模型调用量",
            value = count,
            unit = UsageMetricUnit.Request,
            presentation = UsageMetricPresentation.Value,
            semantic = UsageMetricSemantic.Value,
            healthState = UsageMetricHealthState.Normal
        )
    }

    private fun percentMetric(id: String, label: String, percentage: BigDecimal, windowEnd: Instant?): UsageMetric =
        UsageMetric(
            id = id,
            label = label,
            used = percentage,
            limit = BigDecimal(100),
            remaining = BigDecimal(100).subtract(percentage).max(BigDecimal.ZERO),
            unit = UsageMetricUnit.Token,
            windowEnd = windowEnd,
            presentation = UsageMetricPresentation.Progress,
            semantic = UsageMetricSemantic.UsedQuota,
            healthState = UsageMetricHealthEvaluator.fromPercent(percentage.toDouble())
        )

    /** Start of the model-usage query window: one day before now, local calendar. */
    private fun windowStart(): String = format(LocalDateTime.now(clock).minusDays(1))

    /** End of the query window: the current hour with minutes/seconds set to 59, like the macOS client. */
    private fun windowEnd(): String {
        val now = LocalDateTime.now(clock)
        return format(now.withMinute(59).withSecond(59).withNano(0))
    }

    private fun format(value: LocalDateTime): String = value.format(FORMATTER)

    private fun encode(value: String): String {
        val builder = StringBuilder()
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt().toChar()
            if (c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '_' || c == '.' || c == '~' || c == ':') {
                builder.append(c)
            } else {
                builder.append('%')
                builder.append("%02X".format(byte))
            }
        }
        return builder.toString()
    }

    companion object {
        const val DEFAULT_BASE_URL = "https://api.z.ai"
        private const val MODEL_USAGE_PATH = "/api/monitor/usage/model-usage"
        private const val QUOTA_LIMIT_PATH = "/api/monitor/usage/quota/limit"

        private val FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    }
}
