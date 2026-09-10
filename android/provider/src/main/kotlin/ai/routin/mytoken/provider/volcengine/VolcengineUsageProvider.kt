package ai.routin.mytoken.provider.volcengine

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
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
import ai.routin.mytoken.provider.json.boolOrNull
import ai.routin.mytoken.provider.json.decimalOrNull
import ai.routin.mytoken.provider.json.longOrNull
import ai.routin.mytoken.provider.json.objOrNull
import ai.routin.mytoken.provider.json.stringOrNull
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.OffsetDateTime

/**
 * Volcengine (火山方舟) personal plan adapter，动态获取套餐详情、用量和允许模型。
 */
class VolcengineUsageProvider(
    private val transport: HttpTransport,
    private val clock: Clock = Clock.systemUTC(),
    private val signer: VolcengineSigner = VolcengineSigner(),
    private val endpoint: String = DEFAULT_ENDPOINT,
) : UsageProvider {

    override val providerId: ProviderId = ProviderId.Volcengine

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        val accessKeyID: String
        val secretAccessKey: String
        if (credential.providerId != ProviderId.Volcengine || credential.credentialKind != CredentialKind.AccessKeyPair) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }
        when (val pair = secret as? CredentialSecret.AccessKeyPair) {
            null -> return Result.failure(UsageProviderException.InvalidCredential())
            else -> {
                accessKeyID = pair.accessKeyID
                secretAccessKey = pair.secretAccessKey
            }
        }
        val region = credential.metadata[CredentialMetadataKey.Region]?.takeIf { it.isNotBlank() }
            ?: return Result.failure(UsageProviderException.InvalidCredential())
        if (accessKeyID.isEmpty() || secretAccessKey.isEmpty()) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }

        val isCodingPlan = credential.metadata[CredentialMetadataKey.PlanType] == "coding"
        val requestedPlan = if (isCodingPlan) "CodingPlan" else "AgentPlan"
        val planBody = """{"Plan":"$requestedPlan"}""".toByteArray()

        val plan = decodePersonalPlan(
            response = signedRequest(
                action = ACTION_PERSONAL_PLAN,
                body = planBody,
                accessKeyID = accessKeyID,
                secretAccessKey = secretAccessKey,
                region = region,
            ),
            requestedPlan = requestedPlan,
        )
        val response = signedRequest(
            action = if (isCodingPlan) ACTION_CODING_USAGE else ACTION_AGENT_USAGE,
            body = "{}".toByteArray(),
            accessKeyID = accessKeyID,
            secretAccessKey = secretAccessKey,
            region = region,
        )
        val models = decodeModelIds(
            signedRequest(
                action = if (isCodingPlan) ACTION_CODING_MODEL_LIST else ACTION_AGENT_MODEL_LIST,
                body = planBody,
                accessKeyID = accessKeyID,
                secretAccessKey = secretAccessKey,
                region = region,
            )
        )

        return runCatching {
            mapResponse(
                response = response,
                credentialId = credential.id,
                plan = plan,
                fallbackPlanName = if (isCodingPlan) "Coding Plan" else "Personal Agent Plan",
                allowedModels = models,
            )
        }.recoverCatching { error ->
            if (error is UsageProviderException) throw error
            throw UsageProviderException.InvalidResponse()
        }
    }

    private suspend fun signedRequest(
        action: String,
        body: ByteArray,
        accessKeyID: String,
        secretAccessKey: String,
        region: String,
    ): ProviderHttpResponse {
        val url = endpoint.trimEnd('/') + "/?Action=$action&Version=$VERSION"
        return try {
            val headers = signer.sign(
                method = "POST",
                url = url,
                headers = mapOf(
                    "Content-Type" to "application/json",
                    "Host" to hostOf(url)
                ),
                body = body,
                credential = VolcengineSigner.Credential(
                    accessKeyID = accessKeyID,
                    secretAccessKey = secretAccessKey,
                    region = region
                ),
                timestamp = clock.instant()
            )
            transport.execute(ProviderHttpRequest(method = "POST", url = url, headers = headers, body = body))
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            throw error as? UsageProviderException ?: UsageProviderException.Transport()
        }
    }

    private fun decodePersonalPlan(
        response: ProviderHttpResponse,
        requestedPlan: String,
    ): PersonalPlan {
        val body = response.body.decodeToString()
        if (response.statusCode !in 200..299) {
            safeErrorMessage(body)?.let { throw UsageProviderException.ProviderMessage("火山方舟：$it") }
            throw classifyStatus(response.statusCode)
        }
        val result = ProviderJson.parse(body).asObjectOrNull()?.objOrNull("Result")
            ?: throw UsageProviderException.ProviderMessage("火山方舟：未找到已购买的$requestedPlan 套餐")

        return PersonalPlan(
            planType = result.stringOrNull("PlanType")?.takeIf(String::isNotBlank),
            status = result.stringOrNull("Status")?.takeIf(String::isNotBlank),
            autoRenew = result.boolOrNull("AutoRenew"),
            startTime = parsePlanInstant(result.stringOrNull("StartTime")),
            endTime = parsePlanInstant(result.stringOrNull("EndTime")),
        )
    }

    private fun decodeModelIds(response: ProviderHttpResponse): List<String> {
        val body = response.body.decodeToString()
        if (response.statusCode !in 200..299) {
            safeErrorMessage(body)?.let { throw UsageProviderException.ProviderMessage("火山方舟：$it") }
            throw classifyStatus(response.statusCode)
        }
        val data = ProviderJson.parse(body).asObjectOrNull()
            ?.objOrNull("Result")
            ?.arrayOrNull("Datas")
            ?: return emptyList()
        return data.mapNotNull { item ->
            item.asObjectOrNull()?.stringOrNull("ModelID")?.takeIf(String::isNotBlank)
        }
    }

    private fun parsePlanInstant(value: String?): Instant? {
        val text = value?.takeIf(String::isNotBlank) ?: return null
        return runCatching { Instant.parse(text) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(text).toInstant() }.getOrNull()
    }

    private fun mapResponse(
        response: ProviderHttpResponse,
        credentialId: java.util.UUID,
        plan: PersonalPlan,
        fallbackPlanName: String,
        allowedModels: List<String>,
    ): UsageSnapshot {
        val body = response.body.decodeToString()
        if (response.statusCode !in 200..299) {
            // Same message-first priority as the macOS provider.
            safeErrorMessage(body)?.let { throw UsageProviderException.ProviderMessage("火山方舟：$it") }
            throw when (response.statusCode) {
                401, 403 -> UsageProviderException.Unauthorized()
                429 -> UsageProviderException.RateLimited()
                in 500..599 -> UsageProviderException.ProviderUnavailable()
                else -> UsageProviderException.InvalidResponse()
            }
        }

        val root = ProviderJson.parse(body).asObjectOrNull()
            ?: throw UsageProviderException.InvalidResponse()
        val result = root.objOrNull("Result")
            ?: throw UsageProviderException.InvalidResponse()
        val remotePlanName = plan.planType
            ?.takeIf { it.isNotBlank() }
            ?.let { "$it Plan" }
            ?: fallbackPlanName

        val metrics = buildList {
            val windows = listOf(
                Triple("fiveHour", "近 5 小时用量", result.objOrNull("AFPFiveHour")),
                Triple("weekly", "近一周用量", result.objOrNull("AFPWeekly")),
                Triple("monthly", "近一月用量", result.objOrNull("AFPMonthly"))
            )
            for ((id, label, window) in windows) {
                if (window == null) continue
                val quota = window.decimalOrNull("Quota") ?: continue
                if (quota.signum() <= 0) continue
                val used = window.decimalOrNull("Used") ?: BigDecimal.ZERO
                val percent = used.divide(quota, MATH_CONTEXT).toDouble() * 100
                add(
                    UsageMetric(
                        id = id,
                        label = label,
                        used = used,
                        limit = quota,
                        remaining = quota.subtract(used).max(BigDecimal.ZERO),
                        unit = UsageMetricUnit.Request,
                        windowEnd = window.longOrNull("ResetTime")?.let(Instant::ofEpochMilli),
                        presentation = UsageMetricPresentation.Progress,
                        semantic = UsageMetricSemantic.UsedQuota,
                        healthState = UsageMetricHealthEvaluator.fromPercent(percent)
                    )
                )
            }
            if (isEmpty()) {
                val quotaUsage = result.arrayOrNull("QuotaUsage") ?: emptyList()
                quotaUsage.forEachIndexed { index, item ->
                    val obj = item.asObjectOrNull() ?: return@forEachIndexed
                    val percent = obj.decimalOrNull("Percent") ?: return@forEachIndexed
                    add(
                        UsageMetric(
                            id = "coding-$index",
                            label = obj.stringOrNull("Level") ?: "Coding Plan",
                            used = percent,
                            limit = BigDecimal(100),
                            remaining = BigDecimal(100).subtract(percent).max(BigDecimal.ZERO),
                            unit = UsageMetricUnit.Request,
                            windowEnd = obj.longOrNull("ResetTimestamp")?.let(Instant::ofEpochSecond),
                            presentation = UsageMetricPresentation.Progress,
                            semantic = UsageMetricSemantic.UsedQuota,
                            healthState = UsageMetricHealthEvaluator.fromPercent(percent.toDouble())
                        )
                    )
                }
            }
        }
        if (metrics.isEmpty()) throw UsageProviderException.InvalidResponse()

        return UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = clock.instant(),
            planName = remotePlanName,
            subscriptionStartAt = plan.startTime,
            subscriptionEndAt = plan.endTime,
            statusText = plan.status,
            billingMode = plan.autoRenew?.let { if (it) "自动续费" else "单次订阅" },
            allowedModels = allowedModels,
            metrics = metrics
        )
    }

    private data class PersonalPlan(
        val planType: String?,
        val status: String?,
        val autoRenew: Boolean?,
        val startTime: Instant?,
        val endTime: Instant?,
    )

    /**
     * Extracts the provider error message the same way as the macOS implementation
     * (`Error` / `error` / `ResponseMetadata` objects with `Code` / `Message` fields).
     * Only server-provided fields are used; credential material is never included.
     */
    private fun safeErrorMessage(body: String): String? {
        val object0 = runCatching { ProviderJson.parse(body).asObjectOrNull() }.getOrNull() ?: return null
        val error = object0.objOrNull("Error")
            ?: object0.objOrNull("error")
            ?: object0.objOrNull("ResponseMetadata")
        val code = error?.stringOrNull("Code") ?: error?.stringOrNull("code")
        val message = error?.stringOrNull("Message") ?: error?.stringOrNull("message")
        if (code != null && message != null) return "$code：$message"
        return message ?: code
    }

    private fun classifyStatus(statusCode: Int): UsageProviderException = when (statusCode) {
        401, 403 -> UsageProviderException.Unauthorized()
        429 -> UsageProviderException.RateLimited()
        in 500..599 -> UsageProviderException.ProviderUnavailable()
        else -> UsageProviderException.InvalidResponse()
    }

    private fun hostOf(url: String): String =
        runCatching { java.net.URI(url).host }.getOrNull() ?: "open.volcengineapi.com"

    companion object {
        const val DEFAULT_ENDPOINT = "https://open.volcengineapi.com"
        private const val VERSION = "2024-01-01"
        private const val ACTION_PERSONAL_PLAN = "GetPersonalPlan"
        private const val ACTION_AGENT_USAGE = "GetAgentPlanAFPUsage"
        private const val ACTION_CODING_USAGE = "GetCodingPlanUsage"
        private const val ACTION_AGENT_MODEL_LIST = "ListArkAgentPlanModel"
        private const val ACTION_CODING_MODEL_LIST = "ListArkCodingPlanModel"
        private val MATH_CONTEXT = java.math.MathContext.DECIMAL64
    }
}
