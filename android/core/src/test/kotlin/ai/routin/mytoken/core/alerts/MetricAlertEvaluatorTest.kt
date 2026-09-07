package ai.routin.mytoken.core.alerts

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.CredentialUsageState
import ai.routin.mytoken.domain.usage.RefreshStatus
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM coverage of the threshold semantics ported from the macOS
 * AlertEvaluator / MetricAlertRuleResolver: 50/80/custom thresholds, per-credential
 * overrides, notify-once with re-arm on reset, and invalid-credential alerts.
 */
class MetricAlertEvaluatorTest {

    private val evaluator = MetricAlertEvaluator()
    private val credentialId = UUID.fromString("00000000-0000-0000-0000-000000000001")

    // ---- helpers ------------------------------------------------------------

    private fun credential(
        name: String = "测试凭证",
        providerId: ProviderId = ProviderId.Routin,
    ) = Credential(
        id = credentialId,
        providerId = providerId,
        credentialKind = CredentialKind.BearerApiKey,
        name = name,
    )

    private fun quotaMetric(
        id: String = "m1",
        label: String = "日用量",
        used: BigDecimal,
        limit: BigDecimal,
        windowEnd: Instant? = Instant.parse("2026-09-07T16:00:00Z"),
        semantic: UsageMetricSemantic = UsageMetricSemantic.UsedQuota,
    ) = UsageMetric(
        id = id,
        label = label,
        used = used,
        limit = limit,
        remaining = limit - used,
        unit = UsageMetricUnit.Currency,
        windowStart = null,
        windowEnd = windowEnd,
        presentation = UsageMetricPresentation.Progress,
        semantic = semantic,
        currencyCode = "USD",
    )

    private fun readyState(vararg metrics: UsageMetric) = CredentialUsageState(
        status = RefreshStatus.Ready,
        snapshot = UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = Instant.parse("2026-09-07T12:00:00Z"),
            metrics = metrics.toList(),
        ),
    )

    private val emptyState = AlertNotificationState()

    // ---- used-percent thresholds --------------------------------------------

    @Test
    fun usedQuotaBelowLowThresholdProducesNoAlert() {
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("12"), limit = BigDecimal("100"))),
            MetricAlertSettings(),
            emptyState,
        )
        assertTrue(evaluation.usageAlerts.isEmpty())
    }

    @Test
    fun usedQuotaAtLowThresholdFiresLowAlert() {
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("52"), limit = BigDecimal("100"))),
            MetricAlertSettings(),
            emptyState,
        )
        val alert = evaluation.usageAlerts.single()
        assertEquals(AlertLevel.Low, alert.level)
        assertEquals(52.0, alert.percent, 0.001)
        assertEquals("日用量", alert.metricLabel)
        assertEquals("测试凭证", alert.credentialName)
        assertEquals(ProviderId.Routin, alert.providerId)
        assertEquals(MetricAlertSource.UsedPercent, alert.source)
    }

    @Test
    fun usedQuotaAtHighThresholdFiresHighAlert() {
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("85"), limit = BigDecimal("100"))),
            MetricAlertSettings(),
            emptyState,
        )
        val alert = evaluation.usageAlerts.single()
        assertEquals(AlertLevel.High, alert.level)
    }

    @Test
    fun crossingBothThresholdsFiresOnlyTheHighest() {
        // 0 -> 85 skips past 50 and 80 in one refresh: only the High alert is emitted.
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("85"), limit = BigDecimal("100"))),
            MetricAlertSettings(),
            emptyState,
        )
        assertEquals(listOf(AlertLevel.High), evaluation.usageAlerts.map { it.level })
        // Both windows are marked triggered so a later 60% refresh does not re-notify Low.
        val second = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("60"), limit = BigDecimal("100"))),
            MetricAlertSettings(),
            evaluation.state,
        )
        assertTrue(second.usageAlerts.isEmpty())
    }

    @Test
    fun alertNotifiesOnlyOnceUntilThresholdFallsBackBelow() {
        val settings = MetricAlertSettings()
        // Windowless metric: re-arm happens when the percent falls back below.
        fun metric(used: String) = quotaMetric(
            used = BigDecimal(used),
            limit = BigDecimal("100"),
            windowEnd = null,
        )
        val first = evaluator.evaluate(credential(), readyState(metric("55")), settings, emptyState)
        assertEquals(1, first.usageAlerts.size)

        // Same window, still above threshold: no repeat notification.
        val second = evaluator.evaluate(credential(), readyState(metric("70")), settings, first.state)
        assertTrue(second.usageAlerts.isEmpty())

        // Reset: usage drops back below 50% — the threshold re-arms.
        val reset = evaluator.evaluate(credential(), readyState(metric("20")), settings, second.state)
        assertTrue(reset.usageAlerts.isEmpty())
        assertTrue(reset.state.triggeredWindows.isEmpty())

        val rearmed = evaluator.evaluate(credential(), readyState(metric("60")), settings, reset.state)
        assertEquals(1, rearmed.usageAlerts.size)
    }

    @Test
    fun newWindowReArmsWindowedMetric() {
        val settings = MetricAlertSettings()
        val windowOne = Instant.parse("2026-09-07T16:00:00Z")
        val windowTwo = Instant.parse("2026-09-08T16:00:00Z")
        val first = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("90"), limit = BigDecimal("100"), windowEnd = windowOne)),
            settings,
            emptyState,
        )
        assertEquals(1, first.usageAlerts.size)

        // Same window, still above threshold → silent.
        val repeat = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("95"), limit = BigDecimal("100"), windowEnd = windowOne)),
            settings,
            first.state,
        )
        assertTrue(repeat.usageAlerts.isEmpty())

        // Next window: fresh threshold, notifies again.
        val nextWindow = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("90"), limit = BigDecimal("100"), windowEnd = windowTwo)),
            settings,
            repeat.state,
        )
        assertEquals(1, nextWindow.usageAlerts.size)
    }

    @Test
    fun customThresholdsReplaceDefaults() {
        val settings = MetricAlertSettings(thresholds = AlertThresholds(lowPercent = 70, highPercent = 90))
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("75"), limit = BigDecimal("100"))),
            settings,
            emptyState,
        )
        assertEquals(AlertLevel.Low, evaluation.usageAlerts.single().level)
    }

    @Test
    fun perCredentialOverrideWinsOverGlobal() {
        val settings = MetricAlertSettings(
            thresholds = AlertThresholds.DEFAULT,
            perCredential = mapOf(credentialId to AlertThresholds(lowPercent = 20, highPercent = 90)),
        )
        // 30% is below the global low (50) but above the per-credential override (20).
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("30"), limit = BigDecimal("100"))),
            settings,
            emptyState,
        )
        assertEquals(AlertLevel.Low, evaluation.usageAlerts.single().level)
    }

    @Test
    fun otherCredentialsAreNotAffectedByOverride() {
        val settings = MetricAlertSettings(
            thresholds = AlertThresholds.DEFAULT,
            perCredential = mapOf(UUID.fromString("00000000-0000-0000-0000-000000000002") to AlertThresholds(20, 90)),
        )
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("30"), limit = BigDecimal("100"))),
            settings,
            emptyState,
        )
        assertTrue(evaluation.usageAlerts.isEmpty())
    }

    // ---- remaining-percent thresholds ---------------------------------------

    @Test
    fun remainingQuotaMirrorsUsedThresholds() {
        // remaining 45% <= (100 - 50): Low alert with "剩余低于 50%" semantics.
        val low = evaluator.evaluate(
            credential(),
            readyState(
                quotaMetric(
                    id = "m2",
                    used = BigDecimal("55"),
                    limit = BigDecimal("100"),
                    semantic = UsageMetricSemantic.RemainingQuota,
                ),
            ),
            MetricAlertSettings(),
            emptyState,
        )
        val lowAlert = low.usageAlerts.single()
        assertEquals(AlertLevel.Low, lowAlert.level)
        assertEquals(MetricAlertSource.RemainingPercent, lowAlert.source)
        assertEquals(45.0, lowAlert.percent, 0.001)

        // remaining 15% <= (100 - 80): High alert.
        val high = evaluator.evaluate(
            credential(),
            readyState(
                quotaMetric(
                    id = "m2",
                    used = BigDecimal("85"),
                    limit = BigDecimal("100"),
                    semantic = UsageMetricSemantic.RemainingQuota,
                ),
            ),
            MetricAlertSettings(),
            emptyState,
        )
        assertEquals(AlertLevel.High, high.usageAlerts.single().level)
    }

    // ---- health-state metrics (balance / status) ----------------------------

    @Test
    fun unhealthyBalanceMetricFiresHealthAlertOnceAndReArms() {
        fun balanceMetric(health: UsageMetricHealthState) = UsageMetric(
            id = "balance",
            label = "余额",
            value = BigDecimal("1.5"),
            unit = UsageMetricUnit.Currency,
            presentation = UsageMetricPresentation.Balance,
            semantic = UsageMetricSemantic.Balance,
            currencyCode = "CNY",
            healthState = health,
        )

        val warning = evaluator.evaluate(
            credential(),
            readyState(balanceMetric(UsageMetricHealthState.Warning)),
            MetricAlertSettings(),
            emptyState,
        )
        val alert = warning.usageAlerts.single()
        assertEquals(MetricAlertSource.HealthState, alert.source)
        assertEquals(AlertLevel.Low, alert.level)

        val repeat = evaluator.evaluate(
            credential(),
            readyState(balanceMetric(UsageMetricHealthState.Warning)),
            MetricAlertSettings(),
            warning.state,
        )
        assertTrue(repeat.usageAlerts.isEmpty())

        val recovered = evaluator.evaluate(
            credential(),
            readyState(balanceMetric(UsageMetricHealthState.Normal)),
            MetricAlertSettings(),
            repeat.state,
        )
        assertTrue(recovered.usageAlerts.isEmpty())

        val rearmed = evaluator.evaluate(
            credential(),
            readyState(balanceMetric(UsageMetricHealthState.Critical)),
            MetricAlertSettings(),
            recovered.state,
        )
        assertEquals(1, rearmed.usageAlerts.size)
    }

    // ---- degenerate metric values -------------------------------------------

    @Test
    fun metricWithoutLimitIsSkipped() {
        val metric = UsageMetric(
            id = "m3",
            label = "状态",
            unit = UsageMetricUnit.Request,
            presentation = UsageMetricPresentation.Value,
            semantic = UsageMetricSemantic.Value,
        )
        val evaluation = evaluator.evaluate(credential(), readyState(metric), MetricAlertSettings(), emptyState)
        assertTrue(evaluation.usageAlerts.isEmpty())
    }

    @Test
    fun zeroLimitIsSkipped() {
        val evaluation = evaluator.evaluate(
            credential(),
            readyState(quotaMetric(used = BigDecimal("0"), limit = BigDecimal("0"))),
            MetricAlertSettings(),
            emptyState,
        )
        assertTrue(evaluation.usageAlerts.isEmpty())
    }

    @Test
    fun missingSnapshotProducesNoAlerts() {
        val evaluation = evaluator.evaluate(
            credential(),
            CredentialUsageState(status = RefreshStatus.Loading),
            MetricAlertSettings(),
            emptyState,
        )
        assertTrue(evaluation.usageAlerts.isEmpty())
        assertTrue(evaluation.invalidCredentialAlerts.isEmpty())
    }

    // ---- invalid credential alerts ------------------------------------------

    private fun failedState(error: AppError) = CredentialUsageState(
        status = RefreshStatus.Failed,
        error = error,
    )

    @Test
    fun authenticationFailureNotifiesCredentialInvalidOnce() {
        val first = evaluator.evaluate(
            credential(name = "Routin 主号"),
            failedState(AppError.Authentication("凭证已失效")),
            MetricAlertSettings(),
            emptyState,
        )
        val alert = first.invalidCredentialAlerts.single()
        assertEquals(credentialId, alert.credentialId)
        assertEquals("Routin 主号", alert.credentialName)
        assertEquals("凭证已失效", alert.reason)

        val repeat = evaluator.evaluate(
            credential(name = "Routin 主号"),
            failedState(AppError.Authentication("凭证已失效")),
            MetricAlertSettings(),
            first.state,
        )
        assertTrue(repeat.invalidCredentialAlerts.isEmpty())
    }

    @Test
    fun nonAuthenticationFailureDoesNotNotifyInvalidCredential() {
        val evaluation = evaluator.evaluate(
            credential(),
            failedState(AppError.Network("连接超时")),
            MetricAlertSettings(),
            emptyState,
        )
        assertTrue(evaluation.invalidCredentialAlerts.isEmpty())
    }

    @Test
    fun successfulRefreshReArmsInvalidCredentialAlert() {
        var state = emptyState
        state = evaluator.evaluate(
            credential(), failedState(AppError.Authentication("401")), MetricAlertSettings(), state,
        ).state
        state = evaluator.evaluate(
            credential(), readyState(quotaMetric(used = BigDecimal("10"), limit = BigDecimal("100"))),
            MetricAlertSettings(), state,
        ).state
        assertTrue(state.invalidNotifiedCredentials.isEmpty())

        val rearmed = evaluator.evaluate(
            credential(), failedState(AppError.Authentication("401")), MetricAlertSettings(), state,
        )
        assertEquals(1, rearmed.invalidCredentialAlerts.size)
    }

    // ---- notification text ---------------------------------------------------

    @Test
    fun notificationBodyContainsOnlyAliasProviderAndRedactedMetrics() {
        val alert = MetricAlert(
            credentialId = credentialId,
            credentialName = "测试凭证",
            providerId = ProviderId.Routin,
            metricId = "m1",
            metricLabel = "日用量",
            source = MetricAlertSource.UsedPercent,
            level = AlertLevel.High,
            percent = 85.0,
            windowEnd = Instant.parse("2026-09-07T16:00:00Z"),
            currencyCode = "USD",
        )
        val body = alert.notificationBody()
        assertTrue(body.contains("测试凭证"))
        assertTrue(body.contains("Routin"))
        assertTrue(body.contains("85%"))
        // No secret-bearing material can appear: the alert model has no such field,
        // but pin the redaction contract against accidental schema growth.
        assertFalse(body.contains("sk-"))
        assertFalse(body.contains("Bearer"))
    }

    @Test
    fun usedPercentBodyAppendsWindowResetTime() {
        val alert = MetricAlert(
            credentialId = credentialId,
            credentialName = "测试凭证",
            providerId = ProviderId.Routin,
            metricId = "m1",
            metricLabel = "日用量",
            source = MetricAlertSource.UsedPercent,
            level = AlertLevel.High,
            percent = 85.0,
            windowEnd = Instant.parse("2026-09-07T16:00:00Z"),
            currencyCode = null,
        )
        assertTrue(alert.notificationBody().contains("重置"))
    }

    @Test
    fun remainingPercentBodyUsesRemainingWording() {
        val alert = MetricAlert(
            credentialId = credentialId,
            credentialName = "测试凭证",
            providerId = ProviderId.DeepSeek,
            metricId = "m2",
            metricLabel = "日用量",
            source = MetricAlertSource.RemainingPercent,
            level = AlertLevel.Low,
            percent = 45.0,
            windowEnd = null,
            currencyCode = null,
        )
        assertTrue(alert.notificationBody().contains("剩余低于"))
    }

    @Test
    fun healthStateBodyUsesStatusWording() {
        val alert = MetricAlert(
            credentialId = credentialId,
            credentialName = "测试凭证",
            providerId = ProviderId.Glm,
            metricId = "balance",
            metricLabel = "余额",
            source = MetricAlertSource.HealthState,
            level = AlertLevel.Low,
            percent = 0.0,
            windowEnd = null,
            currencyCode = "CNY",
        )
        assertTrue(alert.notificationBody().contains("状态异常"))
    }

    // ---- window key encoding --------------------------------------------------

    @Test
    fun alertWindowKeyEncodingRoundTrips() {
        val key = AlertWindowKey(credentialId, "m1", "1788281600", 80)
        assertEquals(key, AlertWindowKey.decode(key.encoded()))
    }

    @Test
    fun alertWindowKeyDecodeRejectsGarbage() {
        assertNull(AlertWindowKey.decode("not-a-key"))
        assertNull(AlertWindowKey.decode("x|y|z|NaN"))
    }

    // ---- threshold validation --------------------------------------------------

    @Test
    fun invalidThresholdsAreRejected() {
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            AlertThresholds(lowPercent = 80, highPercent = 50)
        }
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            AlertThresholds(lowPercent = 0, highPercent = 80)
        }
    }
}
