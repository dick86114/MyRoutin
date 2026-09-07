package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import java.net.URI

/** Validation failure with a user-visible Chinese message (aligned with the macOS editor). */
class CredentialValidationException(message: String) : Exception(message)

/** Validated editor input: only the Android metadata allowlist keys are emitted. */
data class ValidatedCredentialInput(
    val credentialKind: CredentialKind,
    val name: String,
    val secret: CredentialSecret,
    val metadata: Map<CredentialMetadataKey, String>,
)

/**
 * Port of the macOS CredentialEditorValidation (RoutinUsage/Views/CredentialEditorView.swift)
 * to the Android credential kinds:
 * - Routin: bearerAPIKey with the plan- prefix rules from [CredentialKeyPolicy].
 * - DeepSeek / GLM: raw apiKey.
 * - Volcengine: accessKeyPair with a default region of cn-beijing.
 * - NewAPI: bearerAPIKey plus baseURL + userID metadata.
 *
 * The macOS editor also persists balanceWarningThreshold; that key is not part of the
 * Android metadata allowlist (transfer-schema-v1.json), so it is intentionally dropped.
 */
object CredentialEditorValidation {

    data class FormFields(
        val name: String,
        val apiKey: String = "",
        val accessKeyID: String = "",
        val secretAccessKey: String = "",
        val region: String = "",
        val newAPIBaseURL: String = "",
        val newAPIUserID: String = "",
        val websiteURL: String = "",
    )

    fun validate(providerId: ProviderId, fields: FormFields): ValidatedCredentialInput {
        val normalizedName = fields.name.trim()
        if (normalizedName.isEmpty()) {
            throw CredentialValidationException("请输入 Key 名称")
        }
        val websiteMetadata = websiteMetadata(fields.websiteURL)

        return when (providerId) {
            ProviderId.Routin -> {
                val secret = fields.apiKey
                if (secret.isEmpty()) throw CredentialValidationException("请输入 plan Key")
                if (!CredentialKeyPolicy.hasValidPrefix(secret)) {
                    throw CredentialValidationException("Key 必须以 plan- 开头")
                }
                if (!CredentialKeyPolicy.isSafeDisplayName(normalizedName)) {
                    throw CredentialValidationException("显示名称不能是 plan Key")
                }
                if (!CredentialKeyPolicy.hasSufficientSecretPayload(secret)) {
                    throw CredentialValidationException("plan Key 内容至少需要 4 位")
                }
                ValidatedCredentialInput(
                    credentialKind = CredentialKind.BearerApiKey,
                    name = normalizedName,
                    secret = CredentialSecret.BearerToken(secret),
                    metadata = mapOf(CredentialMetadataKey.PlanType to "agent") + websiteMetadata,
                )
            }
            ProviderId.DeepSeek, ProviderId.Glm -> {
                val secret = fields.apiKey.trim()
                if (secret.isEmpty()) throw CredentialValidationException("请输入 API Key")
                ValidatedCredentialInput(
                    credentialKind = CredentialKind.ApiKey,
                    name = normalizedName,
                    secret = CredentialSecret.ApiKey(secret),
                    metadata = websiteMetadata,
                )
            }
            ProviderId.Volcengine -> {
                val accessKey = fields.accessKeyID.trim()
                val secret = fields.secretAccessKey.trim()
                if (accessKey.isEmpty()) throw CredentialValidationException("请输入 Access Key ID")
                if (secret.isEmpty()) throw CredentialValidationException("请输入 Secret Access Key")
                val region = fields.region.trim().ifEmpty { "cn-beijing" }
                ValidatedCredentialInput(
                    credentialKind = CredentialKind.AccessKeyPair,
                    name = normalizedName,
                    secret = CredentialSecret.AccessKeyPair(accessKey, secret),
                    metadata = mapOf(
                        CredentialMetadataKey.Region to region,
                        CredentialMetadataKey.PlanType to "agent",
                    ) + websiteMetadata,
                )
            }
            ProviderId.NewAPI -> {
                val secret = fields.apiKey.trim()
                if (secret.isEmpty()) throw CredentialValidationException("请输入 API Key")
                val userID = fields.newAPIUserID.trim()
                val parsedUserID = userID.toLongOrNull()
                if (parsedUserID == null || parsedUserID <= 0) {
                    throw CredentialValidationException("请输入有效的用户 ID")
                }
                val normalizedURL = normalizeNewAPIBaseURL(fields.newAPIBaseURL)
                ValidatedCredentialInput(
                    credentialKind = CredentialKind.BearerApiKey,
                    name = normalizedName,
                    secret = CredentialSecret.BearerToken(secret),
                    metadata = mapOf(
                        CredentialMetadataKey.BaseURL to normalizedURL,
                        CredentialMetadataKey.UserID to userID,
                    ) + websiteMetadata,
                )
            }
        }
    }

    private fun normalizeNewAPIBaseURL(raw: String): String {
        val trimmed = raw.trim()
        val uri = try {
            URI(trimmed)
        } catch (_: Exception) {
            throw CredentialValidationException("请输入有效的接口地址")
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https" || uri.host.isNullOrBlank()) {
            throw CredentialValidationException("请输入有效的接口地址")
        }
        var path = uri.rawPath ?: ""
        while (path.endsWith("/")) {
            path = path.dropLast(1)
        }
        if (path == "/api") {
            path = ""
        }
        val port = if (uri.port in 1..65535) ":${uri.port}" else ""
        return "$scheme://${uri.host}$port$path"
    }

    private fun websiteMetadata(rawValue: String): Map<CredentialMetadataKey, String> {
        val trimmed = rawValue.trim()
        if (trimmed.isEmpty()) return emptyMap()
        val uri = try {
            URI(trimmed)
        } catch (_: Exception) {
            throw CredentialValidationException("请输入有效的网址")
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https" || uri.host.isNullOrBlank()) {
            throw CredentialValidationException("请输入有效的网址")
        }
        return mapOf(CredentialMetadataKey.WebsiteURL to trimmed)
    }
}
