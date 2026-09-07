package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/** Color + text label pair so color is never the only information channel. */
internal data class MetricTone(val color: Color, val label: String) {
    companion object {
        fun of(metric: UsageMetric, percent: Double?, colors: StatusColors): MetricTone =
            when (metric.healthState) {
                UsageMetricHealthState.Normal -> MetricTone(colors.normal, "正常")
                UsageMetricHealthState.Warning -> MetricTone(colors.warning, "注意")
                UsageMetricHealthState.Critical -> MetricTone(colors.critical, "告急")
                UsageMetricHealthState.Unavailable -> MetricTone(colors.neutral, "不可用")
                UsageMetricHealthState.Stale -> MetricTone(colors.warning, "已过期")
                UsageMetricHealthState.Unknown -> when {
                    percent == null -> MetricTone(colors.neutral, "")
                    percent >= 80.0 -> MetricTone(colors.critical, "告急")
                    percent >= 50.0 -> MetricTone(colors.warning, "注意")
                    else -> MetricTone(colors.normal, "正常")
                }
            }
    }
}

/** Metric value formatting: strips trailing zeros, plain decimal string. */
internal fun formatDecimal(value: BigDecimal?): String {
    if (value == null) return "—"
    val stripped = value.stripTrailingZeros()
    if (stripped.compareTo(BigDecimal.ZERO) == 0) return "0"
    return stripped.toPlainString()
}

/** Progress percent (0..100) derived from used/limit; null when not computable. */
internal fun progressPercent(metric: UsageMetric): Double? {
    val used = metric.used ?: return null
    val limit = metric.limit ?: return null
    if (limit.compareTo(BigDecimal.ZERO) == 0) return null
    return used.toDouble() / limit.toDouble() * 100.0
}

private val resetTimeFormatter = DateTimeFormatter.ofPattern("M月d日 HH:mm")

internal fun formatResetTime(instant: java.time.Instant): String =
    resetTimeFormatter.format(instant.atZone(ZoneId.systemDefault()))

/**
 * 2-column metric grid replacing the macOS popover's horizontal compact rows.
 * Missing metrics simply do not render — no fabricated 0 or 100% values.
 */
@Composable
fun UsageMetricGrid(
    metrics: List<UsageMetric>,
    modifier: Modifier = Modifier,
    columns: Int = 2,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        metrics.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { metric ->
                    MetricCell(metric = metric, modifier = Modifier.weight(1f))
                }
                repeat(columns - row.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun MetricCell(
    metric: UsageMetric,
    modifier: Modifier = Modifier,
) {
    when (metric.presentation) {
        UsageMetricPresentation.Progress -> ProgressCell(metric, modifier)
        UsageMetricPresentation.Balance -> BalanceCell(metric, modifier)
        UsageMetricPresentation.Status -> StatusCell(metric, modifier)
        UsageMetricPresentation.Value -> ValueCell(metric, modifier)
    }
}

@Composable
private fun CellLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

@Composable
private fun ProgressCell(metric: UsageMetric, modifier: Modifier = Modifier) {
    val percent = progressPercent(metric)
    val tone = MetricTone.of(metric, percent, statusColors())
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CellLabel(metric.label, modifier = Modifier.weight(1f))
            if (percent != null) {
                Text(
                    text = "${percent.roundToInt()}%",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = tone.color,
                )
                if (tone.label.isNotEmpty()) {
                    Text(
                        text = tone.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = tone.color,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }
        }
        if (percent != null) {
            val clamped = (percent.coerceIn(0.0, 100.0)) / 100.0
            LinearProgressIndicator(
                progress = { clamped.toFloat() },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp),
                color = tone.color,
                trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
            )
        }
        if (metric.used != null && metric.limit != null) {
            Text(
                text = "已用 ${formatDecimal(metric.used)} / ${formatDecimal(metric.limit)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        metric.remaining?.let { remaining ->
            Text(
                text = "剩余 ${formatDecimal(remaining)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        metric.windowEnd?.let { windowEnd ->
            Text(
                text = "重置 ${formatResetTime(windowEnd)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun BalanceCell(metric: UsageMetric, modifier: Modifier = Modifier) {
    val tone = MetricTone.of(metric, null, statusColors())
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CellLabel(metric.label, modifier = Modifier.weight(1f))
            Text(
                text = "${formatDecimal(metric.value)} ${metric.currencyCode ?: "元"}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = tone.color,
            )
        }
        Text(
            text = "账户余额",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (tone.label.isNotEmpty()) {
            Text(
                text = tone.label,
                style = MaterialTheme.typography.labelSmall,
                color = tone.color,
            )
        }
    }
}

@Composable
private fun StatusCell(metric: UsageMetric, modifier: Modifier = Modifier) {
    val tone = MetricTone.of(metric, null, statusColors())
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        CellLabel(metric.label)
        Text(
            text = metric.value?.let { formatDecimal(it) } ?: (tone.label.ifEmpty { "—" }),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = tone.color,
        )
    }
}

@Composable
private fun ValueCell(metric: UsageMetric, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        CellLabel(metric.label)
        Text(
            text = formatDecimal(metric.value),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
