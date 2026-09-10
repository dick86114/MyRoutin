package ai.routin.mytoken.provider.deepseek

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
import ai.routin.mytoken.provider.json.objOrNull
import ai.routin.mytoken.provider.json.stringOrNull
import java.math.BigDecimal
import java.time.Clock

/**
 * DeepSeek adapter, aligned with the macOS DeepSeekUsageProvider: GET /user/balance
 * with Bearer auth and a best-effort GET /models request for the allowed model list.
 */
class DeepSeekUsageProvider(
    private val transport: HttpTransport,
    private val clock: Clock = Clock.systemUTC(),
    private val endpoint: String = DEFAULT_ENDPOINT,
) : UsageProvider {

    override val providerId: ProviderId = ProviderId.DeepSeek

    override suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot> {
        if (credential.providerId != ProviderId.DeepSeek || credential.credentialKind != CredentialKind.ApiKey) {
            return Result.failure(UsageProviderException.InvalidCredential())
        }
        val key = (secret as? CredentialSecret.ApiKey)?.key
            ?: return Result.failure(UsageProviderException.InvalidCredential())
        if (key.isEmpty()) return Result.failure(UsageProviderException.InvalidCredential())

        val response = try {
            transport.execute(
                ProviderHttpRequest(
                    method = "GET",
                    url = endpoint,
                    headers = mapOf(
                        "Authorization" to "Bearer $key",
                        "Accept" to "application/json"
                    )
                )
            )
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            return Result.failure(UsageProviderException.Transport())
        }

        val allowedModels = runCatching {
            val modelsResponse = transport.execute(
                ProviderHttpRequest(
                    method = "GET",
                    url = MODELS_ENDPOINT,
                    headers = mapOf(
                        "Authorization" to "Bearer $key",
                        "Accept" to "application/json"
                    )
                )
            )
            readModelIds(modelsResponse)
        }.getOrElse { error ->
            if (error is kotlinx.coroutines.CancellationException) throw error
            emptyList()
        }

        return runCatching { mapResponse(response, credential, allowedModels) }.recoverCatching { error ->
            if (error is UsageProviderException) throw error
            throw UsageProviderException.InvalidResponse()
        }
    }

    private fun mapResponse(
        response: ProviderHttpResponse,
        credential: Credential,
        allowedModels: List<String>,
    ): UsageSnapshot {
        val body = response.body.decodeToString()
        if (response.statusCode !in 200..299) {
            throw classifyStatus(response.statusCode)
        }
        val root = ProviderJson.parse(body).asObjectOrNull()
            ?: throw UsageProviderException.InvalidResponse()
        val isAvailable = root.boolOrNull("is_available") ?: false
        val balanceInfo = root.arrayOrNull("balance_infos")?.firstOrNull()?.asObjectOrNull()
            ?: throw UsageProviderException.InvalidResponse()

        val currency = balanceInfo.stringOrNull("currency")?.takeIf { it.isNotEmpty() } ?: "CNY"
        val total = balanceInfo.decimalOrNull("total_balance") ?: BigDecimal.ZERO
        val granted = balanceInfo.decimalOrNull("granted_balance") ?: BigDecimal.ZERO
        val toppedUp = balanceInfo.decimalOrNull("topped_up_balance") ?: BigDecimal.ZERO
        val health = UsageMetricHealthEvaluator.balanceState(
            balance = total,
            warningThreshold = null,
            isAvailable = isAvailable
        )

        return UsageSnapshot(
            credentialId = credential.id,
            fetchedAt = clock.instant(),
            planName = "API 余额",
            allowedModels = allowedModels,
            metrics = listOf(
                UsageMetric(
                    id = "balance",
                    label = "余额",
                    value = total,
                    unit = UsageMetricUnit.Currency,
                    presentation = UsageMetricPresentation.Balance,
                    semantic = UsageMetricSemantic.Balance,
                    currencyCode = currency,
                    healthState = health
                ),
                UsageMetric(
                    id = "grantedBalance",
                    label = "赠金余额",
                    value = granted,
                    unit = UsageMetricUnit.Currency,
                    presentation = UsageMetricPresentation.Value,
                    semantic = UsageMetricSemantic.Value,
                    currencyCode = currency,
                    healthState = health
                ),
                UsageMetric(
                    id = "toppedUpBalance",
                    label = "充值余额",
                    value = toppedUp,
                    unit = UsageMetricUnit.Currency,
                    presentation = UsageMetricPresentation.Value,
                    semantic = UsageMetricSemantic.Value,
                    currencyCode = currency,
                    healthState = health
                ),
                UsageMetric(
                    id = "availability",
                    label = "账户状态",
                    value = if (isAvailable) BigDecimal.ONE else BigDecimal.ZERO,
                    unit = UsageMetricUnit.Boolean_,
                    presentation = UsageMetricPresentation.Status,
                    semantic = UsageMetricSemantic.Status,
                    healthState = if (isAvailable) health else UsageMetricHealthState.Unavailable
                )
            )
        )
    }

    private fun readModelIds(response: ProviderHttpResponse): List<String> {
        if (response.statusCode !in 200..299) throw UsageProviderException.InvalidResponse()
        val data = ProviderJson.parse(response.body.decodeToString())
            .asObjectOrNull()
            ?.arrayOrNull("data")
            ?: return emptyList()
        return data.mapNotNull { item ->
            item.asObjectOrNull()?.stringOrNull("id")?.takeIf(String::isNotBlank)
        }
    }

    private fun classifyStatus(statusCode: Int): UsageProviderException = when (statusCode) {
        401, 403 -> UsageProviderException.Unauthorized()
        429 -> UsageProviderException.RateLimited()
        in 500..599 -> UsageProviderException.ProviderUnavailable()
        else -> UsageProviderException.InvalidResponse()
    }

    companion object {
        const val DEFAULT_ENDPOINT = "https://api.deepseek.com/user/balance"
        const val MODELS_ENDPOINT = "https://api.deepseek.com/models"
    }
}
