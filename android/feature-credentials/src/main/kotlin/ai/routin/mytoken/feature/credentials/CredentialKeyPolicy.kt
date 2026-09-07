package ai.routin.mytoken.feature.credentials

/**
 * Port of the macOS KeyCredentialPolicy / KeyDisplayMask rules
 * (RoutinUsage/Models/KeyConfiguration.swift, KeyDisplayMask.swift) for the
 * Routin "plan Key" credential family: display-name hygiene, plan- prefix
 * validation, and the masked display shown in the credential list/editor.
 */
object CredentialKeyPolicy {
    const val SECRET_PREFIX = "plan-"
    const val MINIMUM_VISIBLE_SUFFIX_LENGTH = 4

    fun isSafeDisplayName(name: String): Boolean {
        val normalized = name.trim()
        return normalized.isNotEmpty() && !normalized.lowercase().startsWith(SECRET_PREFIX)
    }

    fun hasValidPrefix(secret: String): Boolean = secret.startsWith(SECRET_PREFIX)

    fun hasSufficientSecretPayload(secret: String): Boolean =
        hasValidPrefix(secret) && secret.drop(SECRET_PREFIX.length).length >= MINIMUM_VISIBLE_SUFFIX_LENGTH

    fun metadataSuffix(secret: String): String =
        if (hasSufficientSecretPayload(secret)) {
            secret.takeLast(MINIMUM_VISIBLE_SUFFIX_LENGTH)
        } else {
            ""
        }

    fun isLegacyShortSecretSuffix(suffix: String): Boolean {
        if (suffix.length != MINIMUM_VISIBLE_SUFFIX_LENGTH) return false
        return suffix.startsWith("an-") || suffix.startsWith("n-") || suffix.startsWith("-")
    }

    fun maskedDisplay(suffix: String): String =
        if (suffix.length == MINIMUM_VISIBLE_SUFFIX_LENGTH && !isLegacyShortSecretSuffix(suffix)) {
            "$SECRET_PREFIX••••$suffix"
        } else {
            "$SECRET_PREFIX••••"
        }

    fun safeDisplayName(name: String): String =
        if (isSafeDisplayName(name)) name.trim() else "未命名 Key"
}
