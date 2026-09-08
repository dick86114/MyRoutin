package ai.routin.mytoken.provider.routin

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageGroupMultiplier
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.UsageProvider
import ai.routin.mytoken.domain.usage.UsageProviderException
import ai.routin.mytoken.provider.http.HttpTransport
import ai.routin.mytoken.provider.http.ProviderHttpRequest
import ai.routin.mytoken.provider.http.ProviderHttpResponse
import ai.routin.mytoken.provider.json.ProviderJson
import ai.routin.mytoken.provider.json.arrayOrNull
import ai.routin.mytoken.provider.json.asObjectOrNull
import ai.routin.mytoken.provider.json.decimalOrNull
import ai.routin.mytoken.provider.json.intOrNull
import ai.routin.mytoken.provider.json.objOrNull
import ai.routin.mytoken.provider.json.stringOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant

/**
 * Routin plan usage adapter, aligned with the macOS UsageAPIClient + UsageMapper:
 * GET /plan/v1/usage with Bearer auth; a JSON `null` body means "no subscription"
 * and yields a snapshot without metrics.
 */
class RoutinUsageProvider(
    private val transport: HttpTransport,
    private val clock: Clock = Clock.systemUTC(),
    private val endpoint: String = DEFAULT_ENDPOINT,
) : UsageProvider {

    override val providerId: ProviderId = ProviderId.Routin

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        if (credential.providerId != ProviderId.Routin || credential.credentialKind != CredentialKind.BearerApiKey) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }
        val token = (secret as? CredentialSecret.BearerToken)?.token
            ?: return Result.failure(UsageProviderException.InvalidCredential())
        val response = try {
            transport.execute(
                ProviderHttpRequest(
                    method = "GET",
                    url = endpoint,
                    headers = mapOf(
                        "Authorization" to "Bearer $token",
                        "Accept" to "application/json"
                    )
                )
            )
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            return Result.failure(UsageProviderException.Transport())
        }

        return runCatching { mapResponse(response, credential.id) }.recoverCatching { error ->
            if (error is UsageProviderException) throw error
            throw UsageProviderException.InvalidResponse()
        }
    }

    private fun mapResponse(response: ProviderHttpResponse, credentialId: java.util.UUID): UsageSnapshot {
        val body = response.body.decodeToString()
        if (response.statusCode !in 200..299) {
            if (response.statusCode == 401 && isInvalidKeyBody(body)) {
                throw UsageProviderException.Unauthorized()
            }
            throw classifyStatus(response.statusCode)
        }
        if (body.trim() == "null") {
            return UsageSnapshot(credentialId = credentialId, fetchedAt = clock.instant(), metrics = emptyList())
        }
        val root = ai.routin.mytoken.provider.json.ProviderJson.parse(body).asObjectOrNull()
            ?: throw UsageProviderException.InvalidResponse()

        val hasPeriodicLimit = hasValidLimit(root.decimalOrNull("dailyLimitUsd")) ||
            hasValidLimit(root.decimalOrNull("weeklyLimitUsd"))
        val hasTokenLimit = hasValidLimit(root.decimalOrNull("totalTokens"))
        val type = root.intOrNull("type")

        val metrics: List<UsageMetric> = when {
            hasTokenLimit && !hasPeriodicLimit -> listOfNotNull(
                metric(
                    id = "token",
                    label = "Token",
                    limit = root.decimalOrNull("totalTokens"),
                    used = root.decimalOrNull("consumedTokens"),
                    remaining = root.decimalOrNull("remainingTokens"),
                    unit = UsageMetricUnit.Token,
                    currencyCode = null,
                    windowEnd = null
                )
            )
            hasPeriodicLimit -> listOfNotNull(
                metric(
                    id = "fiveHour",
                    label = "5 小时",
                    limit = root.decimalOrNull("dailyLimitUsd"),
                    used = root.decimalOrNull("dailyUsedUsd"),
                    remaining = root.decimalOrNull("dailyRemainingUsd"),
                    unit = UsageMetricUnit.Currency,
                    currencyCode = "USD",
                    windowEnd = root.stringOrNull("dayWindowEndAt")?.let(::parseInstant)
                ),
                metric(
                    id = "weekly",
                    label = "周",
                    limit = root.decimalOrNull("weeklyLimitUsd"),
                    used = root.decimalOrNull("weeklyUsedUsd"),
                    remaining = root.decimalOrNull("weeklyRemainingUsd"),
                    unit = UsageMetricUnit.Currency,
                    currencyCode = "USD",
                    windowEnd = root.stringOrNull("weekWindowEndAt")?.let(::parseInstant)
                )
            )
            else -> throw UsageProviderException.InvalidResponse()
        }
        return UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = clock.instant(),
            planName = root.stringOrNull("planName").orEmpty(),
            subscriptionStartAt = root.stringOrNull("startAt")?.let(::parseInstant),
            subscriptionEndAt = root.stringOrNull("endAt")?.let(::parseInstant),
            status = root.intOrNull("status"),
            usageKind = if (hasPeriodicLimit) "periodic" else "tokenPack",
            allowedModels = root.arrayOrNull("allowedModels")
                ?.mapNotNull { item -> (item as? JsonPrimitive)?.contentOrNull }
                .orEmpty(),
            groupMultipliers = readGroupMultipliers(root),
            metrics = metrics
        )
    }

    private fun readGroupMultipliers(root: JsonObject): List<UsageGroupMultiplier> {
        val names = keyedStringValues(root, "groupNames")
        val multipliers = keyedDecimalValues(root, "groupMultipliers")
        if (names == null || multipliers == null) return emptyList()
        return names.keys.mapNotNull { key ->
            val multiplier = multipliers[key] ?: return@mapNotNull null
            UsageGroupMultiplier(name = key, multiplier = multiplier)
        }
    }

    private fun keyedStringValues(
        root: JsonObject,
        key: String,
    ): Map<String, String>? {
        val element = root[key] ?: return null
        return when (element) {
            is kotlinx.serialization.json.JsonArray -> element.mapIndexedNotNull { index, item ->
                val value = (item as? JsonPrimitive)?.contentOrNull ?: return@mapIndexedNotNull null
                index.toString() to value
            }.toMap()
            is kotlinx.serialization.json.JsonObject -> element.keys.sorted().mapNotNull { itemKey ->
                val value = (element[itemKey] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                itemKey to value
            }.toMap()
            else -> null
        }
    }

    private fun keyedDecimalValues(
        root: JsonObject,
        key: String,
    ): Map<String, BigDecimal>? {
        val element = root[key] ?: return null
        return when (element) {
            is kotlinx.serialization.json.JsonArray -> element.mapIndexedNotNull { index, item ->
                val value = (item as? JsonPrimitive)?.contentOrNull?.toBigDecimalOrNull() ?: return@mapIndexedNotNull null
                index.toString() to value
            }.toMap()
            is kotlinx.serialization.json.JsonObject -> element.keys.sorted().mapNotNull { itemKey ->
                val value = (element[itemKey] as? JsonPrimitive)?.contentOrNull?.toBigDecimalOrNull() ?: return@mapNotNull null
                itemKey to value
            }.toMap()
            else -> null
        }
    }

    private fun metric(
        id: String,
        label: String,
        limit: BigDecimal?,
        used: BigDecimal?,
        remaining: BigDecimal?,
        unit: UsageMetricUnit,
        currencyCode: String?,
        windowEnd: Instant?,
    ): UsageMetric? {
        if (limit == null || !hasValidLimit(limit)) return null
        if (used == null && remaining == null) return null

        val resolvedUsed = used ?: remaining?.let { limit.subtract(it) } ?: BigDecimal.ZERO
        val resolvedRemaining = remaining ?: limit.subtract(resolvedUsed)
        return UsageMetric(
            id = id,
            label = label,
            used = resolvedUsed,
            limit = limit,
            remaining = resolvedRemaining,
            unit = unit,
            windowEnd = windowEnd,
            presentation = UsageMetricPresentation.Progress,
            semantic = UsageMetricSemantic.UsedQuota,
            currencyCode = currencyCode
        )
    }

    private fun classifyStatus(statusCode: Int): UsageProviderException = when (statusCode) {
        429 -> UsageProviderException.RateLimited()
        in 500..599 -> UsageProviderException.ProviderUnavailable()
        else -> UsageProviderException.InvalidResponse()
    }

    private fun hasValidLimit(value: BigDecimal?): Boolean = value != null && value.signum() > 0

    private fun isInvalidKeyBody(body: String): Boolean =
        ai.routin.mytoken.provider.json.ProviderJson.parse(body).asObjectOrNull()
            ?.stringOrNull("error") == "invalid_api_key"

    private fun parseInstant(value: String): Instant? =
        runCatching { Instant.parse(value) }.getOrNull()

    companion object {
        const val DEFAULT_ENDPOINT = "https://api.routin.ai/plan/v1/usage"
    }
}
