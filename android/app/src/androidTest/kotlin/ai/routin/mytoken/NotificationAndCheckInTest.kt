package ai.routin.mytoken

import ai.routin.mytoken.core.alerts.AlertLevel
import ai.routin.mytoken.core.alerts.MetricAlertSettings
import ai.routin.mytoken.core.alerts.MetricAlertEvaluator
import ai.routin.mytoken.core.notifications.NotificationChannels
import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.domain.usage.CredentialUsageState
import ai.routin.mytoken.domain.usage.RefreshStatus
import ai.routin.mytoken.feature.credentials.RoutinCheckInLauncher
import android.app.NotificationManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumentation layer for the Task 10 notification and check-in flows, mirroring
 * the JVM/Robolectric coverage at the device layer:
 *  - the three notification channels exist after ensureChannels()
 *  - the evaluator produces redacted notification content (no secret material)
 *  - the check-in launcher URL construction (official page / websiteURL metadata)
 *
 * NOTE: this file cannot execute in this environment — there is no emulator or
 * device available (see task-10-report). It is compile-verified via
 * `./gradlew :app:assembleDebugAndroidTest` and must be exercised by CI/connected
 * runs.
 */
@RunWith(AndroidJUnit4::class)
class NotificationAndCheckInTest {

    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext

    private val credentialId = UUID.fromString("00000000-0000-0000-0000-000000000001")

    private fun credential(metadata: Map<CredentialMetadataKey, String> = emptyMap()) = Credential(
        id = credentialId,
        providerId = ProviderId.Routin,
        credentialKind = CredentialKind.BearerApiKey,
        name = "Routin 主号",
        metadata = metadata,
    )

    @Test
    fun ensureChannelsCreatesAllThreeChannels() {
        NotificationChannels.ensureChannels(context)

        val manager = context.getSystemService(NotificationManager::class.java)
        assertNotNull(manager.getNotificationChannel(NotificationChannels.USAGE_ALERTS_ID))
        assertNotNull(manager.getNotificationChannel(NotificationChannels.CREDENTIAL_ERRORS_ID))
        assertNotNull(manager.getNotificationChannel(NotificationChannels.SYSTEM_REMINDERS_ID))
        assertEquals(
            NotificationManager.IMPORTANCE_HIGH,
            manager.getNotificationChannel(NotificationChannels.USAGE_ALERTS_ID).importance,
        )
    }

    @Test
    fun evaluatorProducesRedactedThresholdAlertContent() = runTest {
        val evaluator = MetricAlertEvaluator()
        val snapshot = UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = Instant.now(),
            metrics = listOf(
                UsageMetric(
                    id = "quota",
                    label = "日用量",
                    used = BigDecimal("85"),
                    limit = BigDecimal("100"),
                    remaining = BigDecimal("15"),
                    unit = UsageMetricUnit.Currency,
                    presentation = UsageMetricPresentation.Progress,
                    semantic = UsageMetricSemantic.UsedQuota,
                    currencyCode = "USD",
                    windowEnd = Instant.now().plusSeconds(3600),
                ),
            ),
        )

        val evaluation = evaluator.evaluate(
            credential = credential(),
            usageState = CredentialUsageState(status = RefreshStatus.Ready, snapshot = snapshot),
            settings = MetricAlertSettings(),
            previousState = ai.routin.mytoken.core.alerts.AlertNotificationState(),
        )

        val alert = evaluation.usageAlerts.single()
        assertEquals(AlertLevel.High, alert.level)
        val body = alert.notificationBody()
        assertTrue(body.contains("Routin 主号"))
        assertTrue(body.contains("85%"))
        // Redaction contract: no credential material can appear in notification text.
        assertTrue(!body.contains("sk-") && !body.contains("Bearer"))
    }

    @Test
    fun invalidCredentialAlertEmittedForAuthenticationFailure() = runTest {
        val evaluator = MetricAlertEvaluator()
        val evaluation = evaluator.evaluate(
            credential = credential(),
            usageState = CredentialUsageState(
                status = RefreshStatus.Failed,
                error = AppError.Authentication("凭证已失效"),
            ),
            settings = MetricAlertSettings(),
            previousState = ai.routin.mytoken.core.alerts.AlertNotificationState(),
        )

        assertEquals(1, evaluation.invalidCredentialAlerts.size)
        assertEquals("Routin 主号", evaluation.invalidCredentialAlerts.single().credentialName)
    }

    @Test
    fun checkInUrlUsesWebsiteUrlMetadataOrOfficialPage() {
        assertEquals(
            "https://routin.ai/dashboard/lottery",
            RoutinCheckInLauncher.checkInUrl(credential()),
        )
        assertEquals(
            "https://custom.example.com/dashboard/lottery",
            RoutinCheckInLauncher.checkInUrl(
                credential(mapOf(CredentialMetadataKey.WebsiteURL to "https://custom.example.com/dashboard/lottery")),
            ),
        )
        assertEquals(
            "https://routin.ai/dashboard/lottery",
            RoutinCheckInLauncher.checkInUrl(
                credential(mapOf(CredentialMetadataKey.WebsiteURL to "http://insecure.example.com")),
            ),
        )
    }
}
