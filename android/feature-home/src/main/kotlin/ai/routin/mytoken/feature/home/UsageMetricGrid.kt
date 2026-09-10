package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.roundToInt

internal data class MetricTone(val color: Color)

internal fun statusColor(metric: UsageMetric, percent: Double?, colors: StatusColors): Color =
    when (metric.healthState) {
        UsageMetricHealthState.Normal -> colors.normal
        UsageMetricHealthState.Warning -> colors.warning
        UsageMetricHealthState.Critical, UsageMetricHealthState.Unavailable -> colors.critical
        UsageMetricHealthState.Stale, UsageMetricHealthState.Unknown -> if (percent == null) colors.neutral else colors.secondaryFallback()
    }

/** 百分比驱动变色：和 macOS UsageMetricPresentation.color(for:) 保持一致。 */
internal fun progressColor(percent: Double?, colors: StatusColors): Color = when {
    percent == null -> colors.neutral
    percent >= 80 -> colors.critical
    percent >= 50 -> colors.warning
    else -> colors.normal
}

private fun StatusColors.secondaryFallback(): Color = neutral

internal fun formatDecimal(value: BigDecimal?): String {
    if (value == null) return "-"
    val stripped = value.stripTrailingZeros()
    return if (stripped.compareTo(BigDecimal.ZERO) == 0) "0" else stripped.toPlainString()
}

internal fun formatGrouped(value: BigDecimal?): String {
    if (value == null) return "-"
    val plain = formatDecimal(value)
    val negative = plain.startsWith("-")
    val body = if (negative) plain.substring(1) else plain
    val dot = body.indexOf('.')
    val integer = if (dot < 0) body else body.substring(0, dot)
    val fraction = if (dot < 0) "" else body.substring(dot)
    val grouped = integer.reversed().chunked(3).joinToString(",").reversed()
    return (if (negative) "-" else "") + grouped + fraction
}

internal fun formatCompact(value: BigDecimal?): String {
    if (value == null) return "-"
    val number = value.toDouble()
    return when {
        number >= 1_000_000 || number <= -1_000_000 -> String.format("%.1fM", number / 1_000_000)
        number >= 1_000 || number <= -1_000 -> String.format("%.1fK", number / 1_000)
        else -> formatDecimal(value)
    }
}

internal fun progressPercent(metric: UsageMetric): Double? {
    val used = metric.used ?: return null
    val limit = metric.limit ?: return null
    if (limit.compareTo(BigDecimal.ZERO) == 0) return null
    return used.toDouble() / limit.toDouble() * 100.0
}

private val shortResetFormatter = DateTimeFormatter.ofPattern("MM-dd HH:mm")
private val timeFormatter = DateTimeFormatter.ofPattern("HH:mm")
private val subscriptionFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

internal fun formatResetTime(instant: Instant): String {
    val zone = ZoneId.systemDefault()
    val local = instant.atZone(zone)
    return if (local.toLocalDate() == LocalDate.now(zone)) timeFormatter.format(local) else shortResetFormatter.format(local)
}

internal fun formatRemainingDuration(end: Instant, now: Instant): String {
    if (!end.isAfter(now)) return "已结束"
    val totalMinutes = max(1L, Duration.between(now, end).toMinutes())
    val days = totalMinutes / (24 * 60)
    val hours = (totalMinutes % (24 * 60)) / 60
    val minutes = totalMinutes % 60
    val parts = buildList {
        if (days > 0) add("${days}天")
        if (hours > 0) add("${hours}小时")
        if (minutes > 0 || isEmpty()) add("${minutes}分钟")
    }
    return parts.joinToString(" ")
}

internal data class CommandCodeDetailLine(
    val text: String,
    val highlight: Boolean = false,
)

internal fun commandCodeProgressDetailLines(
    metric: UsageMetric,
    now: Instant,
): List<CommandCodeDetailLine> = buildList {
    add(CommandCodeDetailLine("已用 ${formatCommandCodeAmount(metric.used)} / ${formatCommandCodeAmount(metric.limit)}"))
    add(CommandCodeDetailLine("剩余 ${formatCommandCodeAmount(metric.remaining)}"))
    metric.windowEnd?.let { end ->
        add(CommandCodeDetailLine("重置 ${formatResetTime(end)}"))
        add(
            CommandCodeDetailLine(
                text = "剩余 ${formatRemainingDuration(end, now)}",
                highlight = end.isAfter(now) && Duration.between(now, end).toMinutes() < 60,
            )
        )
    }
}

@Composable
internal fun RemainingDurationText(end: Instant, colors: StatusColors, modifier: Modifier = Modifier) {
    val now = Instant.now()
    val highlight = end.isAfter(now) && Duration.between(now, end).toMinutes() < 60
    Text(
        text = "剩余 ${formatRemainingDuration(end, now)}",
        style = MaterialTheme.typography.labelSmall,
        color = if (highlight) colors.normal else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

internal fun formatSubscriptionTime(instant: Instant?): String {
    if (instant == null) return "-"
    return subscriptionFormatter.format(instant.atZone(ZoneId.systemDefault()))
}

internal fun formatCommandCodeAmount(value: BigDecimal?): String =
    value?.setScale(2, java.math.RoundingMode.HALF_UP)?.toPlainString() ?: "-"

internal fun formatCurrency(value: BigDecimal?, currencyCode: String?): String {
    val amount = value?.setScale(2, java.math.RoundingMode.HALF_UP)?.toPlainString() ?: "-"
    return when (currencyCode?.uppercase()) {
        "CNY", "RMB", "¥" -> "¥$amount"
        "USD", "$" -> "\$$amount"
        "EUR", "€" -> "€$amount"
        null -> amount
        else -> "$amount $currencyCode"
    }
}


@Composable
internal fun UsageProgressBar(
    percent: Double?,
    color: Color,
    modifier: Modifier = Modifier,
) {
    val fraction = ((percent ?: 0.0).coerceIn(0.0, 100.0) / 100.0).toFloat()
    val track = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
    Canvas(modifier = modifier.fillMaxWidth().height(6.dp)) {
        val radius = CornerRadius(size.height / 2f, size.height / 2f)
        drawRoundRect(color = track, cornerRadius = radius)
        if (fraction > 0f) {
            drawRoundRect(
                color = color,
                size = Size(size.width * fraction, size.height),
                cornerRadius = radius,
            )
        }
    }
}

@Composable
fun UsageMetricGrid(
    metrics: List<UsageMetric>,
    modifier: Modifier = Modifier,
    columns: Int = 2,
) {
    val colors = statusColors()
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        metrics.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { metric ->
                    MetricCell(metric, colors, Modifier.weight(1f))
                }
                repeat(columns - row.size) { Spacer(modifier = Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun MetricCell(metric: UsageMetric, colors: StatusColors, modifier: Modifier = Modifier) {
    when (metric.presentation) {
        ai.routin.mytoken.domain.model.UsageMetricPresentation.Progress -> ProgressCell(metric, colors, modifier)
        ai.routin.mytoken.domain.model.UsageMetricPresentation.Balance -> BalanceCell(metric, colors, modifier)
        ai.routin.mytoken.domain.model.UsageMetricPresentation.Status -> StatusCell(metric, colors, modifier)
        ai.routin.mytoken.domain.model.UsageMetricPresentation.Value -> ValueCell(metric, colors, modifier)
    }
}

@Composable
private fun ProgressCell(metric: UsageMetric, colors: StatusColors, modifier: Modifier = Modifier) {
    val percent = progressPercent(metric)
    val color = progressColor(percent, colors)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(metric.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text("${percent?.roundToInt() ?: 0}%", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
        }
        UsageProgressBar(percent = percent, color = color)
        MetricText("已用 ${formatAmount(metric.used, metric)} / ${formatAmount(metric.limit, metric)}")
        metric.remaining?.let { MetricText("剩余 ${formatAmount(it, metric)}") }
        metric.windowEnd?.let {
            MetricText("重置 ${formatResetTime(it)}")
            RemainingDurationText(it, colors)
        }
    }
}

@Composable
private fun BalanceCell(metric: UsageMetric, colors: StatusColors, modifier: Modifier = Modifier) {
    val caption = when (metric.id) {
        "balance" -> "账户余额"
        "grantedBalance" -> "赠金余额"
        "toppedUpBalance" -> "充值余额"
        else -> metric.label
    }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(formatAmount(metric.value, metric), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = statusColor(metric, null, colors))
        Text(caption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StatusCell(metric: UsageMetric, colors: StatusColors, modifier: Modifier = Modifier) {
    val available = metric.healthState != UsageMetricHealthState.Unavailable
    val caption = if (metric.id == "availability") "账户状态" else metric.label
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(if (available) "可用" else "不可用", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = statusColor(metric, null, colors))
        Text(caption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ValueCell(metric: UsageMetric, colors: StatusColors, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(formatAmount(metric.value, metric), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
        Text(metric.label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun GLMMetrics(metrics: List<UsageMetric>, modifier: Modifier = Modifier) {
    val colors = statusColors()
    val progress = metrics.filter { it.presentation == ai.routin.mytoken.domain.model.UsageMetricPresentation.Progress }
    val calls = metrics.filter { it.id == "model-calls" || it.id == "zcode-mcp" }
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        progress.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { metric ->
                    val percent = progressPercent(metric)
                    val color = progressColor(percent, colors)
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(metric.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                            Text("${percent?.roundToInt() ?: 0}%", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
                        }
                        UsageProgressBar(percent = percent, color = color)
                        metric.windowEnd?.let {
                            Text("重置 ${formatResetTime(it)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            RemainingDurationText(it, colors)
                        }
                    }
                }
                repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        calls.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { metric ->
                    Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                        Text(metric.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                        Text("${formatCompact(metric.value)} 次", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    }
                }
                repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
internal fun VolcengineMetrics(metrics: List<UsageMetric>, modifier: Modifier = Modifier) {
    val colors = statusColors()
    val rowItems = metrics.take(2)
    val monthly = metrics.firstOrNull { it.id == "monthly" }
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            rowItems.forEach { ProgressCell(it, colors, Modifier.weight(1f)) }
            repeat(2 - rowItems.size) { Spacer(Modifier.weight(1f)) }
        }
        monthly?.let {
            val percent = progressPercent(it)
            val color = progressColor(percent, colors)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(it.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                    Text("${percent?.roundToInt() ?: 0}%", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
                }
                UsageProgressBar(percent = percent, color = color)
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        MetricText("已用 ${formatAmount(it.used, it)} / ${formatAmount(it.limit, it)}")
                        it.windowEnd?.let { end -> MetricText("重置 ${formatResetTime(end)}") }
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        it.remaining?.let { value -> MetricText("剩余 ${formatAmount(value, it)}") }
                        it.windowEnd?.let { end -> RemainingDurationText(end, colors) }
                    }
                }
            }
        }
    }
}

@Composable
internal fun NewAPIMetrics(metrics: List<UsageMetric>, modifier: Modifier = Modifier) {
    val colors = statusColors()
    val quota = metrics.firstOrNull { it.id == "quota-progress" }
    val tokens = listOf("today-token", "one-day-token", "seven-day-token", "thirty-day-token").mapNotNull { id -> metrics.firstOrNull { it.id == id } }
    val activities = listOf(
        Triple("RPM", metrics.firstOrNull { it.id == "rpm" }, "近 60 秒请求"),
        Triple("TPM", metrics.firstOrNull { it.id == "tpm" }, "近 60 秒 Token"),
        Triple("账户累计请求", metrics.firstOrNull { it.id == "request-count" }, "当前用户全部 API 请求"),
    )
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        quota?.let {
            val percent = progressPercent(it)
            val color = progressColor(percent, colors)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(it.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                    Text("${percent?.roundToInt() ?: 0}%", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
                }
                UsageProgressBar(percent = percent, color = color)
                Row {
                    MetricText("已用 ${formatAmount(it.used, it)} / ${formatAmount(it.limit, it)}", Modifier.weight(1.2f))
                    it.remaining?.let { value -> MetricText("剩余 ${formatAmount(value, it)}", Modifier.weight(1f)) }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row {
                Text("Token 消耗", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                Text("单位 Token", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            tokens.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    row.forEach { item -> TokenCell(item, metrics.firstOrNull { cost -> cost.id == "${item.id}-cost" }, Modifier.weight(1f)) }
                    repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("请求活动", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                activities.forEach { (label, metric, detail) ->
                    Column(modifier = Modifier.weight(1f)) {
                        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(formatCompact(metric?.value), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Text(detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun TokenCell(metric: UsageMetric, cost: UsageMetric?, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(metric.label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(formatGrouped(metric.value), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Text("≈ ${formatCurrency(cost?.value, cost?.currencyCode)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun formatAmount(value: BigDecimal?, metric: UsageMetric): String = when (metric.unit) {
    ai.routin.mytoken.domain.model.UsageMetricUnit.Currency -> formatCurrency(value, metric.currencyCode)
    else -> formatDecimal(value)
}

@Composable
private fun MetricText(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)
}

@Composable
internal fun CommandCodeMetrics(metrics: List<UsageMetric>, modifier: Modifier = Modifier) {
    val byId = metrics.associateBy(UsageMetric::id)
    val colors = statusColors()
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            CommandCodeProgressMetric(byId["five-hour"], "5 小时", colors, Modifier.weight(1f))
            CommandCodeProgressMetric(byId["weekly"], "周", colors, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            CommandCodeMonthlyMetric(byId["credit-progress"], colors, Modifier.weight(1f))
            CommandCodeRequestMetric(byId["request-count"], Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            CommandCodeValueMetric(byId["purchased-remaining"], "购买剩余", colors, Modifier.weight(1f))
            CommandCodeValueMetric(byId["free-remaining"], "赠送剩余", colors, Modifier.weight(1f))
        }
    }
}

@Composable
private fun CommandCodeProgressMetric(
    metric: UsageMetric?,
    fallbackLabel: String,
    colors: StatusColors,
    modifier: Modifier = Modifier,
) {
    if (metric == null) {
        CommandCodePlaceholder(fallbackLabel, modifier)
        return
    }
    val percent = progressPercent(metric)
    val color = progressColor(percent, colors)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(metric.label.ifEmpty { fallbackLabel }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text("${percent?.roundToInt() ?: 0}%", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
        }
        UsageProgressBar(percent = percent, color = color)
        commandCodeProgressDetailLines(metric, Instant.now()).forEach { line ->
            Text(
                text = line.text,
                style = MaterialTheme.typography.labelSmall,
                color = if (line.highlight) colors.normal else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CommandCodeMonthlyMetric(
    metric: UsageMetric?,
    colors: StatusColors,
    modifier: Modifier = Modifier,
) {
    if (metric == null) {
        CommandCodePlaceholder("月", modifier)
        return
    }
    val percent = progressPercent(metric)
    val color = progressColor(percent, colors)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(metric.label.ifEmpty { "月" }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text("${percent?.roundToInt() ?: 0}%", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = color)
        }
        UsageProgressBar(percent = percent, color = color)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "已用 ${formatCurrency(metric.used, metric.currencyCode)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "剩余 ${formatCurrency(metric.remaining, metric.currencyCode)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CommandCodeRequestMetric(metric: UsageMetric?, modifier: Modifier = Modifier) {
    if (metric == null) {
        CommandCodePlaceholder("累计请求", modifier)
        return
    }
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = metric.label.ifEmpty { "累计请求" },
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text("${formatCompact(metric.value)} 次", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun CommandCodeValueMetric(
    metric: UsageMetric?,
    fallbackLabel: String,
    colors: StatusColors,
    modifier: Modifier = Modifier,
) {
    if (metric == null) {
        CommandCodePlaceholder(fallbackLabel, modifier)
        return
    }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(metric.label.ifEmpty { fallbackLabel }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            text = formatCurrency(metric.value, metric.currencyCode),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = statusColor(metric, null, colors),
        )
    }
}

@Composable
private fun CommandCodePlaceholder(label: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("-", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
}
