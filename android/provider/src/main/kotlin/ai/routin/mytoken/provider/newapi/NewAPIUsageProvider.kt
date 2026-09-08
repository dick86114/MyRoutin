package ai.routin.mytoken.provider.newapi

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
import ai.routin.mytoken.provider.json.boolOrNull
import ai.routin.mytoken.provider.json.decimalOrNull
import ai.routin.mytoken.provider.json.intOrNull
import ai.routin.mytoken.provider.json.objOrNull
import ai.routin.mytoken.provider.json.stringOrNull
import kotlinx.serialization.json.JsonObject
import java.math.BigDecimal
import java.math.MathContext
import java.net.URI
import java.net.URLEncoder
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/**
 * New API adapter. Shares the macOS endpoint contract, including the dashboard
 * envelope (`success/message/data`) and raw quota display conversion.
 */
class NewAPIUsageProvider(
    private val transport: HttpTransport,
    private val clock: Clock = Clock.systemUTC(),
) : UsageProvider {

    override val providerId: ProviderId = ProviderId.NewAPI

    override suspend fun fetchUsage(
        credential: Credential,
        secret: CredentialSecret,
    ): Result<UsageSnapshot> {
        if (credential.providerId != ProviderId.NewAPI || credential.credentialKind != CredentialKind.BearerApiKey) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }
        val token = (secret as? CredentialSecret.BearerToken)?.token.orEmpty()
        val userID = credential.metadata[CredentialMetadataKey.UserID]?.trim().orEmpty()
        val root = parseBaseURL(credential.metadata[CredentialMetadataKey.BaseURL])
        if (token.isBlank() || userID.toLongOrNull() ?: 0L <= 0L || root == null) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }

        return runCatching { fetchSnapshot(credential, token, userID, root) }.recoverCatching { error ->
            if (error is UsageProviderException) throw error
            throw UsageProviderException.InvalidResponse()
        }
    }

    private suspend fun fetchSnapshot(
        credential: Credential,
        token: String,
        userID: String,
        root: URI,
    ): UsageSnapshot {
        val now = clock.instant()
        val todayStart = now.atZone(ZoneId.systemDefault()).toLocalDate()
            .atStartOfDay(ZoneId.systemDefault()).toInstant()
        val statusData = requestObject(credential, token, userID, endpoint(root, "api/status"))
        val userData = requestObject(credential, token, userID, endpoint(root, "api/user/self"))
        requireEnvelopeSuccess(statusData, "状态接口返回失败")
        requireEnvelopeSuccess(userData, "认证失败")
        val user = userData.objOrNull("data") ?: throw UsageProviderException.InvalidResponse()
        val displayUnit = DisplayUnit.fromStatus(statusData.objOrNull("data"))

        return coroutineScope {
            val todayToken = async { tokenSummary(credential, token, userID, root, todayStart, now) }
            val oneDayToken = async { tokenSummary(credential, token, userID, root, now.minusSeconds(86_400), now) }
            val sevenDayToken = async { tokenSummary(credential, token, userID, root, now.minusSeconds(604_800), now) }
            val thirtyDayToken = async { tokenSummary(credential, token, userID, root, now.minusSeconds(2_592_000), now) }
            val minuteStat = async { minuteStat(credential, token, userID, root, now) }
            val today = todayToken.await()
            val oneDay = oneDayToken.await()
            val sevenDay = sevenDayToken.await()
            val thirtyDay = thirtyDayToken.await()
            val stat = minuteStat.await()
            buildSnapshot(credential.id, now, user, stat, today, oneDay, sevenDay, thirtyDay, displayUnit)
        }
    }

    private suspend fun requestObject(
        credential: Credential,
        token: String,
        userID: String,
        url: URI,
    ): JsonObject {
        val response = try {
            transport.execute(
                ProviderHttpRequest(
                    method = "GET",
                    url = url.toString(),
                    headers = mapOf(
                        "Authorization" to "Bearer $token",
                        "New-Api-User" to userID,
                        "Accept" to "application/json",
                    ),
                )
            )
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            throw UsageProviderException.Transport()
        }
        val body = response.body.decodeToString()
        if (response.statusCode == 401 || response.statusCode == 403) throw UsageProviderException.Unauthorized()
        if (response.statusCode == 429) throw UsageProviderException.RateLimited()
        if (response.statusCode in 500..599) throw UsageProviderException.ProviderUnavailable()
        if (response.statusCode !in 200..299) throw UsageProviderException.InvalidResponse()
        return ProviderJson.parse(body).asObjectOrNull() ?: throw UsageProviderException.InvalidResponse()
    }

    private suspend fun tokenSummary(
        credential: Credential,
        token: String,
        userID: String,
        root: URI,
        start: Instant,
        end: Instant,
    ): TokenSummary {
        val url = endpoint(
            root,
            "api/data/self",
            "start_timestamp" to start.epochSecond.toString(),
            "end_timestamp" to end.epochSecond.toString(),
        )
        val data = requestObject(credential, token, userID, url)
        requireEnvelopeSuccess(data, "Token 统计接口返回失败")
        return data.arrayOrNull("data").orEmpty().mapNotNull { it.asObjectOrNull() }.fold(TokenSummary()) { total, item ->
            total + TokenSummary(
                tokenUsed = item.intOrNull("token_used") ?: 0,
                requestCount = item.intOrNull("count") ?: 0,
                quota = item.decimalOrNull("quota") ?: BigDecimal.ZERO,
            )
        }
    }

    private suspend fun minuteStat(
        credential: Credential,
        token: String,
        userID: String,
        root: URI,
        now: Instant,
    ): MinuteStat {
        val url = endpoint(
            root,
            "api/log/self/stat",
            "start_timestamp" to now.minusSeconds(60).epochSecond.toString(),
            "end_timestamp" to now.epochSecond.toString(),
            "type" to "2",
        )
        val data = requestObject(credential, token, userID, url)
        requireEnvelopeSuccess(data, "统计接口返回失败")
        val stat = data.objOrNull("data") ?: throw UsageProviderException.InvalidResponse()
        return MinuteStat(
            rpm = stat.intOrNull("rpm") ?: 0,
            tpm = stat.intOrNull("tpm") ?: 0,
        )
    }

    private fun buildSnapshot(
        credentialId: java.util.UUID,
        now: Instant,
        user: JsonObject,
        minute: MinuteStat,
        today: TokenSummary,
        oneDay: TokenSummary,
        sevenDay: TokenSummary,
        thirtyDay: TokenSummary,
        displayUnit: DisplayUnit,
    ): UsageSnapshot {
        val rawUsed = user.decimalOrNull("used_quota") ?: BigDecimal.ZERO
        val rawRemaining = (user.decimalOrNull("quota") ?: BigDecimal.ZERO).max(BigDecimal.ZERO)
        val rawTotal = rawUsed + rawRemaining
        val remaining = displayUnit.convert(rawRemaining)
        val health = UsageMetricHealthEvaluator.balanceState(remaining, null, true)
        val userGroup = user.stringOrNull("group")?.trim().orEmpty()
        val planName = if (userGroup.isEmpty()) "New API" else "New API · $userGroup"

        return UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = now,
            planName = planName,
            metrics = listOf(
                UsageMetric(
                    id = "quota-progress",
                    label = "账户额度",
                    used = displayUnit.convert(rawUsed),
                    limit = displayUnit.convert(rawTotal),
                    remaining = remaining,
                    unit = UsageMetricUnit.Currency,
                    presentation = UsageMetricPresentation.Progress,
                    semantic = UsageMetricSemantic.UsedQuota,
                    currencyCode = displayUnit.symbol,
                    healthState = health,
                ),
                valueMetric("today-token", "今日 Token", today.tokenUsed.toBigDecimal(), UsageMetricUnit.Token),
                valueMetric("one-day-token", "近 24 小时 Token", oneDay.tokenUsed.toBigDecimal(), UsageMetricUnit.Token),
                valueMetric("seven-day-token", "近 7 天 Token", sevenDay.tokenUsed.toBigDecimal(), UsageMetricUnit.Token),
                valueMetric("thirty-day-token", "近 30 天 Token", thirtyDay.tokenUsed.toBigDecimal(), UsageMetricUnit.Token),
                currencyMetric("today-token-cost", "今日消费", today.quota, displayUnit),
                currencyMetric("one-day-token-cost", "近 24 小时消费", oneDay.quota, displayUnit),
                currencyMetric("seven-day-token-cost", "近 7 天消费", sevenDay.quota, displayUnit),
                currencyMetric("thirty-day-token-cost", "近 30 天消费", thirtyDay.quota, displayUnit),
                valueMetric("rpm", "近 60 秒 RPM", minute.rpm.toBigDecimal(), UsageMetricUnit.Request),
                valueMetric("tpm", "近 60 秒 TPM", minute.tpm.toBigDecimal(), UsageMetricUnit.Token),
                valueMetric(
                    "request-count",
                    "账户累计请求",
                    (user.intOrNull("request_count") ?: 0).toBigDecimal(),
                    UsageMetricUnit.Request,
                ),
            ),
        )
    }

    private fun valueMetric(id: String, label: String, value: BigDecimal, unit: UsageMetricUnit) = UsageMetric(
        id = id,
        label = label,
        value = value,
        unit = unit,
        presentation = UsageMetricPresentation.Value,
        semantic = UsageMetricSemantic.Value,
        healthState = UsageMetricHealthState.Normal,
    )

    private fun currencyMetric(id: String, label: String, raw: BigDecimal, unit: DisplayUnit) = UsageMetric(
        id = id,
        label = label,
        value = unit.convert(raw),
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Value,
        semantic = UsageMetricSemantic.Value,
        currencyCode = unit.symbol,
        healthState = UsageMetricHealthState.Normal,
    )

    private fun requireEnvelopeSuccess(envelope: JsonObject, fallback: String) {
        if (envelope.boolOrNull("success") == false) {
            throw UsageProviderException.ProviderMessage("New API：${envelope.stringOrNull("message") ?: fallback}")
        }
    }

    private data class TokenSummary(
        val tokenUsed: Int = 0,
        val requestCount: Int = 0,
        val quota: BigDecimal = BigDecimal.ZERO,
    ) {
        operator fun plus(other: TokenSummary) = TokenSummary(
            tokenUsed = tokenUsed + other.tokenUsed,
            requestCount = requestCount + other.requestCount,
            quota = quota + other.quota,
        )
    }

    private data class MinuteStat(val rpm: Int, val tpm: Int)

    private data class DisplayUnit(
        val quotaPerUnit: BigDecimal,
        val exchangeRate: BigDecimal,
        val symbol: String,
        val displaysRawQuota: Boolean,
    ) {
        fun convert(rawQuota: BigDecimal): BigDecimal = if (displaysRawQuota) {
            rawQuota
        } else {
            rawQuota.divide(quotaPerUnit, MathContext.DECIMAL128).multiply(exchangeRate)
                .stripTrailingZeros()
        }

        companion object {
            fun fromStatus(status: JsonObject?): DisplayUnit {
                val quotaPerUnit = (status?.decimalOrNull("quota_per_unit") ?: BigDecimal(500_000))
                    .takeIf { it.signum() > 0 } ?: BigDecimal(500_000)
                val displayType = status?.stringOrNull("quota_display_type")?.uppercase().orEmpty()
                return when (displayType) {
                    "CNY" -> DisplayUnit(
                        quotaPerUnit,
                        positiveOr(status?.decimalOrNull("usd_exchange_rate"), BigDecimal.ONE),
                        "¥",
                        false,
                    )
                    "CUSTOM" -> DisplayUnit(
                        quotaPerUnit,
                        positiveOr(status?.decimalOrNull("custom_currency_exchange_rate"), BigDecimal.ONE),
                        status?.stringOrNull("custom_currency_symbol")?.trim().takeUnless { it.isNullOrEmpty() } ?: "单位",
                        false,
                    )
                    "TOKENS" -> DisplayUnit(quotaPerUnit, BigDecimal.ONE, "额度", true)
                    else -> DisplayUnit(quotaPerUnit, BigDecimal.ONE, "$", false)
                }
            }

            private fun positiveOr(value: BigDecimal?, fallback: BigDecimal) =
                value?.takeIf { it.signum() > 0 } ?: fallback
        }
    }

    private companion object {
        fun parseBaseURL(raw: String?): URI? {
            val value = raw?.trim().orEmpty()
            if (value.isEmpty()) return null
            return runCatching { URI(value) }.getOrNull()?.takeIf { it.scheme != null && it.host != null }
        }

        fun endpoint(root: URI, path: String, vararg query: Pair<String, String>): URI {
            val normalizedRoot = root.toString().trimEnd('/')
            val pathSuffix = if (normalizedRoot.endsWith("/api") && path.startsWith("api/")) {
                path.removePrefix("api/")
            } else {
                path
            }
            val encoded = query.joinToString("&") { (key, value) ->
                "${URLEncoder.encode(key, Charsets.UTF_8)}=${URLEncoder.encode(value, Charsets.UTF_8)}"
            }
            return URI("$normalizedRoot/$pathSuffix${if (encoded.isEmpty()) "" else "?$encoded"}")
        }
    }
}
