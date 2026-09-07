package ai.routin.mytoken.domain.usage

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageSnapshot

/**
 * Unified usage provider interface. Each provider adapter maps its remote API onto the
 * shared [UsageSnapshot] model and classifies failures into [UsageProviderException].
 *
 * Error messages never contain credential secret material.
 */
interface UsageProvider {
    val providerId: ProviderId

    suspend fun fetchUsage(credential: Credential, secret: CredentialSecret): Result<UsageSnapshot>
}

/** Failure categories aligned with the macOS UsageProviderError taxonomy. */
sealed class UsageProviderException(message: String, cause: Throwable? = null) :
    Exception(message, cause) {

    /** 凭证字段不完整（缺少密钥、区域等本地字段）。 */
    class InvalidCredential(message: String = "凭证字段不完整，请检查输入") :
        UsageProviderException(message)

    /** 认证失败：凭证无效或没有权限。 */
    class Unauthorized(message: String = "凭证无效或没有该供应商权限") :
        UsageProviderException(message)

    /** 限流。 */
    class RateLimited(message: String = "请求过于频繁，请稍后重试") :
        UsageProviderException(message)

    /** 网络传输失败。 */
    class Transport(message: String = "网络连接失败，请检查网络后重试") :
        UsageProviderException(message)

    /** 结构变化：响应无法解析或不完整。 */
    class InvalidResponse(message: String = "供应商返回的数据无法识别") :
        UsageProviderException(message)

    /** 服务端错误（5xx）。 */
    class ProviderUnavailable(message: String = "供应商服务暂时不可用") :
        UsageProviderException(message)

    /** 供应商返回的错误消息（已确认不包含凭证材料）。 */
    class ProviderMessage(message: String) : UsageProviderException(message)
}
