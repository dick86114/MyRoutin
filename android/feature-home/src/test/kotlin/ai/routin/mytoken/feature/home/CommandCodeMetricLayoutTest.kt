package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import java.math.BigDecimal
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

class CommandCodeMetricLayoutTest {
    @Test
    fun progressDetailsUseOneVerticalLinePerField() {
        val now = Instant.parse("2026-09-10T12:00:00Z")
        val metric = UsageMetric(
            id = "five-hour",
            label = "5 小时",
            used = BigDecimal("2.56"),
            limit = BigDecimal("14"),
            remaining = BigDecimal("11.44"),
            unit = UsageMetricUnit.Currency,
            windowEnd = now.plusSeconds(23 * 60),
            presentation = UsageMetricPresentation.Progress,
            semantic = UsageMetricSemantic.UsedQuota,
            currencyCode = "$",
            healthState = UsageMetricHealthState.Normal,
        )

        val lines = commandCodeProgressDetailLines(metric, now)

        assertEquals(
            listOf(
                "已用 2.56 / 14.00",
                "剩余 11.44",
                "重置 ${formatResetTime(metric.windowEnd!!)}",
                "剩余 23分钟",
            ),
            lines.map { it.text },
        )
        assertEquals(true, lines.last().highlight)
    }
}
