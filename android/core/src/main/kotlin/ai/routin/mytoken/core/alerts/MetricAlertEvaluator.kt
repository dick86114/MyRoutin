package ai.routin.mytoken.core.alerts

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.usage.CredentialUsageState
import ai.routin.mytoken.domain.usage.RefreshStatus
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

/** Severity of an alert, mirroring the macOS `AlertLevel`. */
enum class AlertLevel { Low, High }

/**
 * Global usage alert thresholds (percent of quota). Defaults mirror the macOS
 * 50/80 semantics. Per-credential overrides are supported by [MetricAlertSettings]
 * but remain a pure-evaluator capability on Android: the metadata allowlist has no
 * per-credential threshold key, so overrides would need a separate local store.
 */
data class AlertThresholds(val lowPercent: Int, val highPercent: Int) {
    init {
        require(lowPercent in MIN_PERCENT..MAX_PERCENT) { "lowPercent must be in 1..99" }
        require(highPercent in MIN_PERCENT..MAX_PERCENT) { "highPercent must be in 1..99" }
        require(lowPercent < highPercent) { "lowPercent must be lower than highPercent" }
    }

    companion object {
        const val MIN_PERCENT = 1
        const val MAX_PERCENT = 99
        val DEFAULT = AlertThresholds(lowPercent = 50, highPercent = 80)
    }
}

data class MetricAlertSettings(
    val thresholds: AlertThresholds = AlertThresholds.DEFAULT,
    val perCredential: Map<UUID, AlertThresholds> = emptyMap(),
)

/**
 * Deduplication key for "notify once" semantics: one threshold crossing per
 * credential × metric × window × threshold. Serializable for DataStore persistence.
 */
data class AlertWindowKey(
    val credentialId: UUID,
    val metricId: String,
    val windowIdentifier: String,
    val threshold: Int,
) {
    fun encoded(): String = "$credentialId|$metricId|$windowIdentifier|$threshold"

    companion object {
        fun decode(value: String): AlertWindowKey? {
            val parts = value.split("|")
            if (parts.size != 4) return null
            return runCatching {
                AlertWindowKey(
                    credentialId = UUID.fromString(parts[0]),
                    metricId = parts[1],
                    windowIdentifier = parts[2],
                    threshold = parts[3].toInt(),
                )
            }.getOrNull()
        }
    }
}

/** Notification bookkeeping carried between evaluations. */
data class AlertNotificationState(
    val triggeredWindows: Set<AlertWindowKey> = emptySet(),
    val invalidNotifiedCredentials: Set<UUID> = emptySet(),
)

/**
 * Persists [AlertNotificationState] so "notify once" survives process restarts
 * (a periodic worker may run in a cold process). DataStore-backed in :data.
 */
interface AlertStateStore {
    suspend fun load(): AlertNotificationState
    suspend fun save(state: AlertNotificationState)
}

enum class MetricAlertSource { UsedPercent, RemainingPercent, HealthState }

/**
 * A usage alert ready to post. Carries only alias, provider and redacted metric
 * values — never secrets or raw request payloads.
 */
data class MetricAlert(
    val credentialId: UUID,
    val credentialName: String,
    val providerId: ProviderId,
    val metricId: String,
    val metricLabel: String,
    val source: MetricAlertSource,
    val level: AlertLevel,
    val percent: Double,
    val windowEnd: Instant?,
    val currencyCode: String?,
) {
    fun notificationBody(timeZone: ZoneId = ZoneId.systemDefault()): String {
        val provider = providerDisplayName(providerId)
        val base = when (source) {
            MetricAlertSource.UsedPercent ->
                "「$credentialName」($provider) · ${metricLabel}用量已达 ${formattedPercent()}%"
            MetricAlertSource.RemainingPercent ->
                "「$credentialName」($provider) · ${metricLabel}剩余低于 ${formattedPercent()}%"
            MetricAlertSource.HealthState ->
                "「$credentialName」($provider) · ${metricLabel}状态异常"
        }
        if (source != MetricAlertSource.UsedPercent || windowEnd == null) return base
        val formatter = DateTimeFormatter.ofPattern("HH:mm").withZone(timeZone)
        return "$base，窗口将在 ${formatter.format(windowEnd)} 重置"
    }

    private fun formattedPercent(): String {
        val rounded = percent.toInt()
        return if (percent - rounded == 0.0) rounded.toString() else String.format("%.1f", percent)
    }
}

/** A credential whose authentication failed and needs user action. */
data class InvalidCredentialAlert(
    val credentialId: UUID,
    val credentialName: String,
    val providerId: ProviderId,
    val reason: String?,
) {
    fun notificationBody(): String {
        val provider = providerDisplayName(providerId)
        val reasonText = reason?.let { "：$it" } ?: ""
        return "「$credentialName」($provider) 认证失败，请更新凭证$reasonText"
    }
}

data class MetricAlertEvaluation(
    val usageAlerts: List<MetricAlert>,
    val invalidCredentialAlerts: List<InvalidCredentialAlert>,
    val state: AlertNotificationState,
)

/**
 * Pure threshold evaluation ported from the macOS `AlertEvaluator` (simplified to
 * the Android metric model):
 * - usedQuota → percent ≥ 50/80 (or custom / per-credential override)
 * - remainingQuota → mirrored percent ≤ (100 − 50)/(100 − 80)
 * - balance / status metrics → health-state (warning/critical/unavailable) alerts
 * - authentication failures → invalid-credential alerts (once, re-armed on recovery)
 *
 * "Notify once" is tracked per [AlertWindowKey]: a crossing notifies once per window
 * (windowed metrics re-arm on the next window); windowless percent metrics re-arm
 * once the percent falls back below the threshold (i.e. after a reset).
 */
class MetricAlertEvaluator {

    fun evaluate(
        credential: Credential,
        usageState: CredentialUsageState?,
        settings: MetricAlertSettings,
        previousState: AlertNotificationState,
    ): MetricAlertEvaluation {
        val triggered = previousState.triggeredWindows.toMutableSet()
        var invalidNotified = previousState.invalidNotifiedCredentials
        val usageAlerts = mutableListOf<MetricAlert>()
        val invalidAlerts = mutableListOf<InvalidCredentialAlert>()

        val thresholds = settings.perCredential[credential.id] ?: settings.thresholds
        val snapshot = usageState?.snapshot
        if (usageState?.status == RefreshStatus.Ready && snapshot != null) {
            for (metric in snapshot.metrics) {
                evaluateMetric(credential, metric, thresholds, triggered, usageAlerts)
            }
        }

        val error = usageState?.error
        when {
            usageState?.status == RefreshStatus.Failed && error is AppError.Authentication -> {
                if (credential.id !in invalidNotified) {
                    invalidNotified = invalidNotified + credential.id
                    invalidAlerts += InvalidCredentialAlert(
                        credentialId = credential.id,
                        credentialName = credential.name,
                        providerId = credential.providerId,
                        reason = error.message,
                    )
                }
            }
            usageState?.status == RefreshStatus.Ready || usageState?.status == RefreshStatus.Disabled -> {
                // Recovery or deliberate disable re-arms the invalid-credential alert.
                invalidNotified = invalidNotified - credential.id
            }
        }

        return MetricAlertEvaluation(
            usageAlerts = usageAlerts,
            invalidCredentialAlerts = invalidAlerts,
            state = AlertNotificationState(triggered, invalidNotified),
        )
    }

    private data class ThresholdMatch(
        val key: Int,
        val level: AlertLevel,
        val matched: Boolean,
        val displayPercent: Int,
        val source: MetricAlertSource,
    )

    private fun evaluateMetric(
        credential: Credential,
        metric: UsageMetric,
        thresholds: AlertThresholds,
        triggered: MutableSet<AlertWindowKey>,
        output: MutableList<MetricAlert>,
    ) {
        val percent = percentOf(metric)
        val matches = matchesFor(metric, thresholds, percent) ?: return
        if (matches.isEmpty()) return

        val windowIdentifier = metric.windowEnd?.epochSecond?.toString() ?: metric.id

        // Drop bookkeeping for windows that no longer exist.
        triggered.removeAll {
            it.credentialId == credential.id && it.metricId == metric.id &&
                it.windowIdentifier != windowIdentifier
        }

        val matched = matches.filter { it.matched }
        if (matched.isEmpty()) {
            // Windowless metrics re-arm as soon as the value falls back below.
            if (metric.windowEnd == null) {
                matches.forEach { match ->
                    triggered.remove(AlertWindowKey(credential.id, metric.id, windowIdentifier, match.key))
                }
            }
            return
        }

        val keyFor: (ThresholdMatch) -> AlertWindowKey = { match ->
            AlertWindowKey(credential.id, metric.id, windowIdentifier, match.key)
        }
        val newlyReached = matched.filterNot { keyFor(it) in triggered }
        if (newlyReached.isEmpty()) return

        if (metric.windowEnd == null) {
            // Re-arm the thresholds that are no longer matched.
            matches.filterNot { it.matched }.forEach { match -> triggered.remove(keyFor(match)) }
        }
        newlyReached.forEach { triggered += keyFor(it) }

        val highest = newlyReached.maxBy { if (it.level == AlertLevel.High) 1 else 0 }
        output += MetricAlert(
            credentialId = credential.id,
            credentialName = credential.name,
            providerId = credential.providerId,
            metricId = metric.id,
            metricLabel = metric.label,
            source = highest.source,
            level = highest.level,
            percent = if (highest.source == MetricAlertSource.HealthState) 0.0 else percent ?: 0.0,
            windowEnd = metric.windowEnd,
            currencyCode = metric.currencyCode,
        )
    }

    /** Returns the usage percent for quota-based metrics; health-state metrics have none. */
    private fun percentOf(metric: UsageMetric): Double? {
        if (metric.semantic != UsageMetricSemantic.UsedQuota &&
            metric.semantic != UsageMetricSemantic.RemainingQuota
        ) {
            return null
        }
        val numerator = if (metric.semantic == UsageMetricSemantic.RemainingQuota) {
            metric.remaining ?: metric.used
        } else {
            metric.used ?: metric.remaining
        } ?: return null
        val limit = metric.limit ?: return null
        if (limit.signum() <= 0) return null
        return numerator.toDouble() / limit.toDouble() * 100.0
    }

    private fun matchesFor(
        metric: UsageMetric,
        thresholds: AlertThresholds,
        percent: Double?,
    ): List<ThresholdMatch>? = when (metric.semantic) {
        UsageMetricSemantic.UsedQuota -> {
            val value = percent ?: return null
            listOf(
                ThresholdMatch(
                    key = thresholds.lowPercent,
                    level = AlertLevel.Low,
                    matched = value >= thresholds.lowPercent,
                    displayPercent = thresholds.lowPercent,
                    source = MetricAlertSource.UsedPercent,
                ),
                ThresholdMatch(
                    key = thresholds.highPercent,
                    level = AlertLevel.High,
                    matched = value >= thresholds.highPercent,
                    displayPercent = thresholds.highPercent,
                    source = MetricAlertSource.UsedPercent,
                ),
            )
        }
        UsageMetricSemantic.RemainingQuota -> {
            val value = percent ?: return null
            val lowRemaining = 100 - thresholds.lowPercent
            val highRemaining = 100 - thresholds.highPercent
            listOf(
                ThresholdMatch(
                    key = thresholds.lowPercent,
                    level = AlertLevel.Low,
                    matched = value <= lowRemaining,
                    displayPercent = lowRemaining,
                    source = MetricAlertSource.RemainingPercent,
                ),
                ThresholdMatch(
                    key = thresholds.highPercent,
                    level = AlertLevel.High,
                    matched = value <= highRemaining,
                    displayPercent = highRemaining,
                    source = MetricAlertSource.RemainingPercent,
                ),
            )
        }
        UsageMetricSemantic.Balance, UsageMetricSemantic.Status -> {
            // No balance-threshold key exists in the Android metadata allowlist, so
            // balance alerts follow the macOS fallback: health-state based.
            val unhealthy = metric.healthState in UNHEALTHY_STATES
            listOf(
                ThresholdMatch(
                    key = HEALTH_KEY,
                    level = AlertLevel.Low,
                    matched = unhealthy,
                    displayPercent = 0,
                    source = MetricAlertSource.HealthState,
                ),
            )
        }
        UsageMetricSemantic.Value -> null
    }

    private companion object {
        val UNHEALTHY_STATES = setOf(
            UsageMetricHealthState.Warning,
            UsageMetricHealthState.Critical,
            UsageMetricHealthState.Unavailable,
        )
        const val HEALTH_KEY = 0
    }
}

/** Display names mirrored from :feature-home's ProviderCatalog (kept dependency-free). */
fun providerDisplayName(providerId: ProviderId): String = when (providerId) {
    ProviderId.Routin -> "Routin"
    ProviderId.DeepSeek -> "DeepSeek"
    ProviderId.Glm -> "智谱 GLM"
    ProviderId.Volcengine -> "火山方舟"
    ProviderId.NewAPI -> "New API"
}
