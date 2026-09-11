package ai.routin.mytoken.provider.commandcode

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
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
import ai.routin.mytoken.provider.json.boolOrNull
import ai.routin.mytoken.provider.json.decimalOrNull
import ai.routin.mytoken.provider.json.intOrNull
import ai.routin.mytoken.provider.json.longOrNull
import ai.routin.mytoken.provider.json.objOrNull
import ai.routin.mytoken.provider.json.stringOrNull
import java.math.BigDecimal
import java.net.URI
import java.net.URLEncoder
import java.time.Clock
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject

/**
 * Command Code adapter using the same account endpoints as the official CLI:
 * whoami, billing credits, subscriptions, usage summary, and the public model list.
 */
class CommandCodeUsageProvider(
    private val transport: HttpTransport,
    private val clock: Clock = Clock.systemUTC(),
    private val baseURL: URI = URI.create("https://api.commandcode.ai"),
) : UsageProvider {

    override val providerId: ProviderId = ProviderId.CommandCode

    private val metadataCache = mutableMapOf<String, CachedMetadata>()
    private val cacheMutex = Mutex()

    override suspend fun fetchUsage(
        credential: Credential,
        secret: CredentialSecret,
    ): Result<UsageSnapshot> {
        if (credential.providerId != ProviderId.CommandCode ||
            credential.credentialKind != CredentialKind.BearerApiKey
        ) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }
        val token = (secret as? CredentialSecret.BearerToken)?.token.orEmpty().trim()
        if (token.isEmpty()) return Result.failure(UsageProviderException.InvalidCredential())

        return runCatching { fetchSnapshot(credential, token) }.recoverCatching { error ->
            if (error is UsageProviderException) throw error
            throw UsageProviderException.InvalidResponse()
        }
    }

    private suspend fun fetchSnapshot(
        credential: Credential,
        token: String,
    ): UsageSnapshot {
        val now = clock.instant()
        val cacheKey = "${credential.id}:${token.hashCode()}"
        val cached = cacheMutex.withLock { metadataCache[cacheKey] ?: CachedMetadata() }

        return coroutineScope {

        val whoamiRequest = async {
            requestObject("/alpha/whoami", token, mapOf("limits" to "1"))
        }
        val creditsRequest = async {
            requestResult("/alpha/billing/credits", token, query = mapOf("orgId" to cached.orgId))
        }
        val subscriptionsRequest = async {
            requestResult("/alpha/billing/subscriptions", token, query = mapOf("orgId" to cached.orgId))
        }
        val modelsRequest = async {
            fetchAllowedModels(cacheKey, token, now)
        }
        val preloadedSummaryRequest = cached.periodStart?.let { periodStart ->
            async {
                requestResult(
                    "/alpha/usage/summary",
                    token,
                    query = mapOf(
                        "orgId" to cached.orgId,
                        "since" to periodStart,
                    ),
                )
            }
        }

        val whoami = whoamiRequest.await()
        val actualOrgID = whoami.objOrNull("org")?.stringOrNull("id")?.takeIf { it.isNotBlank() }
        val creditsPair = if (actualOrgID == cached.orgId) {
            creditsRequest.await().getOrThrow() to subscriptionsRequest.await().getOrThrow()
        } else {
            creditsRequest.cancel()
            subscriptionsRequest.cancel()
            requestObject("/alpha/billing/credits", token, query = mapOf("orgId" to actualOrgID)) to
                requestObject("/alpha/billing/subscriptions", token, query = mapOf("orgId" to actualOrgID))
        }
        val creditsRoot = creditsPair.first
        val creditsData = creditsRoot.objOrNull("credits")
            ?: throw UsageProviderException.ProviderMessage("Command Code：额度信息返回失败")
        val subscription = creditsPair.second.objOrNull("data")
        val periodStart = subscription?.stringOrNull("currentPeriodStart")
        val summary = if (
            preloadedSummaryRequest != null &&
            actualOrgID == cached.orgId &&
            periodStart == cached.periodStart
        ) {
            preloadedSummaryRequest.await().getOrThrow()
        } else {
            preloadedSummaryRequest?.cancel()
            requestObject(
                "/alpha/usage/summary",
                token,
                query = mapOf(
                    "orgId" to actualOrgID,
                    "since" to periodStart,
                ),
            )
        }
        val allowedModels = modelsRequest.await()

        cacheMutex.withLock {
            val current = metadataCache[cacheKey] ?: CachedMetadata()
            metadataCache[cacheKey] = current.copy(orgId = actualOrgID, periodStart = periodStart)
        }

        val monthlyRemaining = creditsData.decimalOrNull("monthlyCredits")?.max(BigDecimal.ZERO) ?: BigDecimal.ZERO
        val purchasedRemaining = creditsData.decimalOrNull("purchasedCredits")?.max(BigDecimal.ZERO) ?: BigDecimal.ZERO
        val freeRemaining = creditsData.decimalOrNull("freeCredits")?.max(BigDecimal.ZERO) ?: BigDecimal.ZERO
        val totalRemaining = monthlyRemaining + purchasedRemaining + freeRemaining
        val totalSpent = summary.decimalOrNull("totalCost")?.max(BigDecimal.ZERO) ?: BigDecimal.ZERO
        val planID = subscription?.stringOrNull("planId")
        val plan = PlanInfo.from(planID)
        val status = subscription?.stringOrNull("status")
        val active = status == "active" || status == "trialing"
        val totalPool = if (active && plan.monthlyCredits != null) {
            plan.monthlyCredits.max(monthlyRemaining) + purchasedRemaining + freeRemaining
        } else {
            totalSpent + totalRemaining
        }
        val totalUsed = (totalPool - totalRemaining).max(BigDecimal.ZERO)
        val health = UsageMetricHealthEvaluator.balanceState(
            balance = totalRemaining,
            warningThreshold = null,
            isAvailable = true,
        )

        val metrics = buildList {
            add(
                UsageMetric(
                    id = "credit-progress",
                    label = "月",
                    used = totalUsed,
                    limit = totalPool,
                    remaining = totalRemaining,
                    unit = UsageMetricUnit.Currency,
                    presentation = UsageMetricPresentation.Progress,
                    semantic = UsageMetricSemantic.UsedQuota,
                    currencyCode = "$",
                    healthState = health,
                )
            )
            add(valueMetric("credit-balance", "剩余额度", totalRemaining, health))
            add(valueMetric("monthly-remaining", "月度剩余", monthlyRemaining, health))
            add(valueMetric("purchased-remaining", "购买剩余", purchasedRemaining, health))
            add(valueMetric("free-remaining", "赠送剩余", freeRemaining, health))
            add(valueMetric("period-spent", "本周期消费", totalSpent, UsageMetricHealthState.Normal))
            add(
                valueMetric(
                    id = "request-count",
                    label = "累计请求",
                    value = (summary.intOrNull("totalCount") ?: 0).coerceAtLeast(0).toBigDecimal(),
                    health = UsageMetricHealthState.Normal,
                )
            )
            addAll(windowMetrics(creditsRoot.objOrNull("windowLimits")))
        }

        UsageSnapshot(
            credentialId = credential.id,
            fetchedAt = now,
            planName = plan.name,
            subscriptionStartAt = periodStart?.let(Instant::parse),
            subscriptionEndAt = subscription?.stringOrNull("currentPeriodEnd")?.let(Instant::parse),
            statusText = statusText(status),
            usageKind = "periodic",
            billingMode = status,
            allowedModels = allowedModels,
            metrics = metrics,
        )
        }
    }

    private fun windowMetrics(limits: JsonObject?): List<UsageMetric> {
        if (limits?.boolOrNull("limited") != true) return emptyList()
        return listOfNotNull(
            limits.objOrNull("fiveHour")?.let { usageWindow("five-hour", "5 小时", it) },
            limits.objOrNull("weekly")?.let { usageWindow("weekly", "周", it) },
        )
    }

    private fun usageWindow(id: String, label: String, data: JsonObject): UsageMetric {
        val used = (data.decimalOrNull("used") ?: BigDecimal.ZERO).max(BigDecimal.ZERO)
        val cap = (data.decimalOrNull("cap") ?: BigDecimal.ZERO).max(BigDecimal.ZERO)
        return UsageMetric(
            id = id,
            label = label,
            used = used,
            limit = cap,
            remaining = (cap - used).max(BigDecimal.ZERO),
            unit = UsageMetricUnit.Currency,
            windowEnd = data.longOrNull("resetAt")?.let(Instant::ofEpochMilli),
            presentation = UsageMetricPresentation.Progress,
            semantic = UsageMetricSemantic.UsedQuota,
            currencyCode = "$",
            healthState = UsageMetricHealthState.Normal,
        )
    }

    private fun valueMetric(
        id: String,
        label: String,
        value: BigDecimal,
        health: UsageMetricHealthState,
    ) = UsageMetric(
        id = id,
        label = label,
        value = value,
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Value,
        semantic = UsageMetricSemantic.Value,
        currencyCode = "$",
        healthState = health,
    )

    private suspend fun requestResult(
        path: String,
        token: String,
        query: Map<String, String?> = emptyMap(),
    ): Result<JsonObject> = try {
        Result.success(requestObject(path, token, query))
    } catch (error: kotlinx.coroutines.CancellationException) {
        throw error
    } catch (error: Throwable) {
        Result.failure(error)
    }

    private suspend fun fetchAllowedModels(
        cacheKey: String,
        token: String,
        now: Instant,
    ): List<String> {
        val cached = cacheMutex.withLock { metadataCache[cacheKey] ?: CachedMetadata() }
        val fetchedAt = cached.modelsFetchedAt
        if (fetchedAt != null && now.epochSecond - fetchedAt.epochSecond < MODELS_CACHE_SECONDS) {
            return cached.models
        }

        val models = runCatching {
            requestObject("/provider/v1/models", token).arrayOrNull("data")
                .orEmpty()
                .mapNotNull { item ->
                    item.asObjectOrNull()?.stringOrNull("id")?.takeIf(String::isNotBlank)
                }
        }.getOrElse { error ->
            if (error is kotlinx.coroutines.CancellationException) throw error
            return cached.models
        }
        cacheMutex.withLock {
            val current = metadataCache[cacheKey] ?: CachedMetadata()
            metadataCache[cacheKey] = current.copy(models = models, modelsFetchedAt = now)
        }
        return models
    }

    private suspend fun requestObject(
        path: String,
        token: String,
        query: Map<String, String?> = emptyMap(),
    ): JsonObject {
        val queryString = query
            .filterValues { it != null }
            .entries
            .joinToString("&") { (key, value) ->
                "${encode(key)}=${encode(requireNotNull(value))}"
            }
        val url = buildString {
            append(baseURL.toString().trimEnd('/'))
            append(path)
            if (queryString.isNotEmpty()) append("?").append(queryString)
        }
        val response = try {
            transport.execute(
                ProviderHttpRequest(
                    method = "GET",
                    url = url,
                    headers = mapOf(
                        "Authorization" to "Bearer $token",
                        "Accept" to "application/json",
                    ),
                )
            )
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            throw UsageProviderException.Transport()
        }
        when (response.statusCode) {
            401, 403 -> throw UsageProviderException.Unauthorized()
            429 -> throw UsageProviderException.RateLimited()
            in 500..599 -> throw UsageProviderException.ProviderUnavailable()
            !in 200..299 -> throw UsageProviderException.InvalidResponse()
        }
        val root = ProviderJson.parse(response.body.decodeToString()).asObjectOrNull()
            ?: throw UsageProviderException.InvalidResponse()
        if (root.boolOrNull("success") == false) {
            throw UsageProviderException.ProviderMessage(
                "Command Code：${root.objOrNull("error")?.stringOrNull("message") ?: "请求返回失败"}"
            )
        }
        return root
    }

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())

    private fun statusText(status: String?): String? = when (status) {
        "active" -> "有效"
        "trialing" -> "试用中"
        "past_due" -> "逾期"
        "canceled", "cancelled" -> "已取消"
        else -> status?.takeIf { it.isNotEmpty() }
    }

    private data class CachedMetadata(
        val orgId: String? = null,
        val periodStart: String? = null,
        val models: List<String> = emptyList(),
        val modelsFetchedAt: Instant? = null,
    )

    private companion object {
        const val MODELS_CACHE_SECONDS = 24 * 60 * 60
    }

    private data class PlanInfo(
        val name: String,
        val monthlyCredits: BigDecimal?,
    ) {
        companion object {
            fun from(planID: String?): PlanInfo = when (planID) {
                "individual-go" -> PlanInfo("Go", BigDecimal("10"))
                "individual-goat" -> PlanInfo("GOAT", BigDecimal("70"))
                "individual-pro" -> PlanInfo("Pro", BigDecimal("30"))
                "individual-pro-v1" -> PlanInfo("Pro", BigDecimal("80"))
                "individual-provider" -> PlanInfo("Provider", BigDecimal("15"))
                "individual-max" -> PlanInfo("Max", BigDecimal("150"))
                "individual-ultra" -> PlanInfo("Ultra", BigDecimal("300"))
                "teams-pro" -> PlanInfo("Teams Pro", BigDecimal("40"))
                null -> PlanInfo("", null)
                else -> PlanInfo(planID, null)
            }
        }
    }
}
