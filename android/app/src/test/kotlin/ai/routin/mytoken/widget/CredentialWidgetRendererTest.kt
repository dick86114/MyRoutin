package ai.routin.mytoken.widget

import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CredentialWidgetRendererTest {

    private val credentialId = UUID.randomUUID()

    @Test
    fun `deepSeek widget uses balance fields only and no periodic template`() {
        val snapshot = UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = Instant.now(),
            planName = "API 余额",
            metrics = listOf(
                balance("balance", "余额", "10.00"),
                value("grantedBalance", "赠金余额", "4.00"),
                value("toppedUpBalance", "充值余额", "6.00"),
                availability(),
            ),
        )

        val items = CredentialWidgetRenderer.displayItems(ProviderId.DeepSeek, snapshot)

        assertEquals(listOf("账户余额", "赠金余额", "充值余额", "账户状态"), items.map { it.label })
        assertTrue(items.none { it.label.contains("5 小时") || it.label.contains("周") })
    }

    @Test
    fun `glm progress omits amounts and keeps reset timing`() {
        val snapshot = UsageSnapshot(
            credentialId = credentialId,
            fetchedAt = Instant.now(),
            planName = "Coding Plan",
            metrics = listOf(
                percent("five-hour", "5 小时用量", 20.toBigDecimal(), Instant.parse("2026-09-08T12:00:00Z")),
                request("model-calls", "模型调用量", 12),
            ),
        )

        val items = CredentialWidgetRenderer.displayItems(ProviderId.Glm, snapshot)

        assertEquals("20%", items[0].value)
        assertTrue(items[0].detail.isEmpty())
        assertTrue(items[0].reset?.startsWith("重置 ") == true)
        assertEquals("12 次", items[1].value)
    }

    private fun balance(id: String, label: String, value: String) = UsageMetric(
        id = id,
        label = label,
        value = BigDecimal(value),
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Balance,
        semantic = UsageMetricSemantic.Balance,
        currencyCode = "CNY",
        healthState = UsageMetricHealthState.Normal,
    )

    private fun value(id: String, label: String, value: String) = UsageMetric(
        id = id,
        label = label,
        value = BigDecimal(value),
        unit = UsageMetricUnit.Currency,
        presentation = UsageMetricPresentation.Value,
        semantic = UsageMetricSemantic.Value,
        currencyCode = "CNY",
        healthState = UsageMetricHealthState.Normal,
    )

    private fun availability() = UsageMetric(
        id = "availability",
        label = "账户状态",
        value = BigDecimal.ONE,
        unit = UsageMetricUnit.Boolean_,
        presentation = UsageMetricPresentation.Status,
        semantic = UsageMetricSemantic.Status,
        healthState = UsageMetricHealthState.Normal,
    )

    private fun percent(id: String, label: String, percentage: BigDecimal, resetAt: Instant) = UsageMetric(
        id = id,
        label = label,
        used = percentage,
        limit = 100.toBigDecimal(),
        remaining = 100.toBigDecimal().subtract(percentage),
        unit = UsageMetricUnit.Token,
        windowEnd = resetAt,
        presentation = UsageMetricPresentation.Progress,
        semantic = UsageMetricSemantic.UsedQuota,
        healthState = UsageMetricHealthState.Normal,
    )

    private fun request(id: String, label: String, count: Int) = UsageMetric(
        id = id,
        label = label,
        value = count.toBigDecimal(),
        unit = UsageMetricUnit.Request,
        presentation = UsageMetricPresentation.Value,
        semantic = UsageMetricSemantic.Value,
        healthState = UsageMetricHealthState.Normal,
    )
}
