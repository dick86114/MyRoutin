package ai.routin.mytoken.domain.model

import java.util.UUID

/** Provider identifiers mirrored from shared/provider-contracts/provider-capabilities.json. */
enum class ProviderId(val rawValue: String) {
    Routin("routin"),
    DeepSeek("deepseek"),
    Glm("glm"),
    Volcengine("volcengine"),
    NewAPI("newAPI"),
    CommandCode("commandCode");

    companion object {
        fun fromRawValue(value: String): ProviderId? = entries.firstOrNull { it.rawValue == value }
    }
}

/** Credential kinds mirrored from transfer-schema-v1.json. */
enum class CredentialKind(val rawValue: String) {
    BearerApiKey("bearerAPIKey"),
    ApiKey("apiKey"),
    AccessKeyPair("accessKeyPair");

    companion object {
        fun fromRawValue(value: String): CredentialKind? = entries.firstOrNull { it.rawValue == value }
    }
}

/** Allowlisted metadata keys from transfer-schema-v1.json. */
enum class CredentialMetadataKey(val rawValue: String) {
    BaseURL("baseURL"),
    UserID("userID"),
    Region("region"),
    PlanType("planType"),
    UsageKind("usageKind"),
    WebsiteURL("websiteURL")
}

data class Credential(
    val id: UUID,
    val providerId: ProviderId,
    val credentialKind: CredentialKind,
    val name: String,
    val isEnabled: Boolean = true,
    val sortOrder: Int = 0,
    val metadata: Map<CredentialMetadataKey, String> = emptyMap()
)
