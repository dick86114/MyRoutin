package ai.routin.mytoken.widget

import ai.routin.mytoken.MainActivity
import ai.routin.mytoken.R
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.feature.home.ProviderCatalog
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

internal data class WidgetMetricDisplay(
    val label: String,
    val value: String,
    val detail: String,
    val reset: String? = null,
    val progressPercent: Int? = null,
)

/** Header, status, and shared metric formatting for the credential widget. */
internal object CredentialWidgetRenderer {

    fun render(
        context: Context,
        appWidgetId: Int,
        credential: Credential?,
        snapshot: UsageSnapshot?,
        statusText: String,
        refreshing: Boolean = false,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.credential_widget)

        val serviceIntent = CredentialWidgetViewsService.bindIntent(context, appWidgetId)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            views.setRemoteAdapter(R.id.widget_metrics, serviceIntent)
        } else {
            @Suppress("DEPRECATION")
            views.setRemoteAdapter(appWidgetId, R.id.widget_metrics, serviceIntent)
        }
        views.setEmptyView(R.id.widget_metrics, R.id.widget_metrics_empty)

        if (credential == null) {
            views.setTextViewText(R.id.widget_provider, context.getString(R.string.app_name))
            views.setTextViewText(R.id.widget_name, context.getString(R.string.widget_choose))
            views.setViewVisibility(R.id.widget_subscription, android.view.View.GONE)
            views.setViewVisibility(R.id.widget_refresh, android.view.View.GONE)
            views.setViewVisibility(R.id.widget_metrics_empty, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_metrics_empty, "点击选择凭证")
            views.setOnClickPendingIntent(R.id.widget_content, configPendingIntent(context, appWidgetId))
            views.setTextViewText(R.id.widget_status, "点击小组件选择要显示的凭证")
            return views
        }

        val providerName = ProviderCatalog.displayName(credential.providerId)
        val plan = snapshot?.planName.orEmpty()
        views.setTextViewText(
            R.id.widget_provider,
            if (plan.isEmpty()) providerName else "$providerName · $plan",
        )
        views.setTextViewText(R.id.widget_name, credential.name)
        renderSubscription(views, snapshot)
        views.setViewVisibility(R.id.widget_refresh, android.view.View.VISIBLE)
        views.setFloat(R.id.widget_refresh, "setAlpha", if (refreshing) 0.3f else 1f)
        views.setOnClickPendingIntent(
            R.id.widget_content,
            detailPendingIntent(context, appWidgetId, credential.id),
        )
        views.setOnClickPendingIntent(R.id.widget_name, configPendingIntent(context, appWidgetId))
        views.setOnClickPendingIntent(R.id.widget_refresh, WidgetRefresher.refreshPendingIntent(context, appWidgetId))
        views.setPendingIntentTemplate(
            R.id.widget_metrics,
            detailPendingIntent(context, appWidgetId, credential.id),
        )
        views.setTextViewText(R.id.widget_status, if (refreshing) "正在刷新…" else statusText)
        return views
    }

    /** 用户点击刷新后立即反馈，不等网络请求完成。 */
    fun renderRefreshing(context: Context, appWidgetId: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.credential_widget)
        views.setViewVisibility(R.id.widget_refresh, android.view.View.VISIBLE)
        views.setFloat(R.id.widget_refresh, "setAlpha", 0.3f)
        views.setTextViewText(R.id.widget_status, "正在刷新…")
        return views
    }

    private fun renderSubscription(views: RemoteViews, snapshot: UsageSnapshot?) {
        val start = snapshot?.subscriptionStartAt
        val end = snapshot?.subscriptionEndAt
        if (start == null && end == null) {
            views.setViewVisibility(R.id.widget_subscription, android.view.View.GONE)
            return
        }
        views.setViewVisibility(R.id.widget_subscription, android.view.View.VISIBLE)
        views.setTextViewText(
            R.id.widget_subscription,
            "开始 ${formatFullTime(start)} · 结束 ${formatFullTime(end)}",
        )
    }

    private fun configPendingIntent(context: Context, appWidgetId: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            appWidgetId + 100_000,
            Intent(context, CredentialWidgetConfigActivity::class.java)
                .setAction(CredentialWidgetConfigActivity.ACTION_EDIT_WIDGET)
                .putExtra(WidgetRefresher.EXTRA_WIDGET_ID, appWidgetId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun detailPendingIntent(context: Context, appWidgetId: Int, credentialId: java.util.UUID): PendingIntent =
        PendingIntent.getActivity(
            context,
            appWidgetId + 300_000,
            Intent(context, MainActivity::class.java)
                .setAction(MainActivity.ACTION_OPEN_CREDENTIAL)
                .setFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                .putExtra(MainActivity.EXTRA_CREDENTIAL_ID, credentialId.toString()),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * Mirrors the home card branches instead of forcing every provider through
     * a generic widget template.
     */
    internal fun displayItems(
        providerId: ProviderId,
        snapshot: UsageSnapshot?,
    ): List<WidgetMetricDisplay> {
        val metrics = snapshot?.metrics.orEmpty()
        return when (providerId) {
            ProviderId.DeepSeek -> deepSeekItems(metrics)
            ProviderId.Glm -> glmItems(metrics)
            ProviderId.NewAPI -> newApiItems(metrics)
            ProviderId.Volcengine -> volcengineItems(metrics)
            ProviderId.CommandCode -> commandCodeItems(metrics)
            else -> metrics.map { item(providerId, it) }
        }
    }

    /** Same fields as generic home cells, but uses BalanceCell's captions. */
    private fun deepSeekItems(metrics: List<UsageMetric>): List<WidgetMetricDisplay> = metrics.map { metric ->
        when (metric.presentation) {
            UsageMetricPresentation.Balance -> WidgetMetricDisplay(
                label = balanceCaption(metric),
                value = formatCurrency(metric.value, metric.currencyCode),
                detail = "",
            )
            UsageMetricPresentation.Status -> WidgetMetricDisplay(
                label = statusCaption(metric),
                value = if (metric.healthState == UsageMetricHealthState.Unavailable) "不可用" else "可用",
                detail = "",
            )
            else -> item(ProviderId.DeepSeek, metric)
        }
    }

    /** GLM home layout suppresses used/limit and shows only percent plus reset. */
    private fun glmItems(metrics: List<UsageMetric>): List<WidgetMetricDisplay> = metrics.map { metric ->
        when {
            metric.presentation == UsageMetricPresentation.Progress -> progressItem(
                metric,
                showAmounts = false,
            )
            metric.id == "model-calls" || metric.id == "zcode-mcp" -> WidgetMetricDisplay(
                label = metric.label,
                value = "${formatCompact(metric.value)} 次",
                detail = "",
            )
            else -> item(ProviderId.Glm, metric)
        }
    }

    /** Volcengine home card shows the first two progress cells and the monthly cell. */
    private fun volcengineItems(metrics: List<UsageMetric>): List<WidgetMetricDisplay> {
        val selected = buildList {
            addAll(metrics.take(2))
            metrics.firstOrNull { it.id == "monthly" }?.let { monthly ->
                if (none { existing -> existing.id == monthly.id }) add(monthly)
            }
        }
        return selected.map { item(ProviderId.Volcengine, it) }
    }

    private fun commandCodeItems(metrics: List<UsageMetric>): List<WidgetMetricDisplay> {
        val byId = metrics.associateBy(UsageMetric::id)
        return listOf(
            "five-hour",
            "weekly",
            "credit-progress",
            "request-count",
            "purchased-remaining",
            "free-remaining",
        ).mapNotNull { id -> byId[id]?.let { item(ProviderId.CommandCode, it) } }
    }

    private fun newApiItems(metrics: List<UsageMetric>): List<WidgetMetricDisplay> {

        val byId = metrics.associateBy(UsageMetric::id)
        val items = mutableListOf<WidgetMetricDisplay>()
        byId["quota-progress"]?.let { items += item(ProviderId.NewAPI, it) }

        val tokenIds = listOf(
            "today-token",
            "one-day-token",
            "seven-day-token",
            "thirty-day-token",
        )
        tokenIds.forEach { id ->
            byId[id]?.let { token ->
                val cost = byId["$id-cost"]
                val costText = cost?.value?.let { " · ≈ ${formatCurrency(it, cost.currencyCode)}" }.orEmpty()
                items += WidgetMetricDisplay(
                    label = token.label,
                    value = formatGrouped(token.value),
                    detail = "单位 Token$costText",
                )
            }
        }

        listOf(
            "rpm" to "近 60 秒请求",
            "tpm" to "近 60 秒 Token",
            "request-count" to "当前用户全部 API 请求",
        ).forEach { (id, detail) ->
            byId[id]?.let { metric ->
                items += WidgetMetricDisplay(
                    label = if (id == "rpm") "RPM" else if (id == "tpm") "TPM" else metric.label,
                    value = formatCompact(metric.value),
                    detail = detail,
                )
            }
        }
        return items
    }

    private fun item(providerId: ProviderId, metric: UsageMetric): WidgetMetricDisplay {
        val percent = progressPercent(metric)
        return when (metric.presentation) {
            UsageMetricPresentation.Progress -> progressItem(
                metric,
                showAmounts = providerId != ProviderId.Glm,
            )
            UsageMetricPresentation.Balance -> WidgetMetricDisplay(
                label = balanceCaption(metric),
                value = formatCurrency(metric.value, metric.currencyCode),
                detail = "",
            )
            UsageMetricPresentation.Status -> WidgetMetricDisplay(
                label = statusCaption(metric),
                value = if (metric.healthState == UsageMetricHealthState.Unavailable) "不可用" else "可用",
                detail = "",
            )
            UsageMetricPresentation.Value -> WidgetMetricDisplay(
                label = metric.label,
                value = when (metric.unit) {
                    UsageMetricUnit.Request -> "${formatCompact(metric.value)} 次"
                    UsageMetricUnit.Token -> formatGrouped(metric.value)
                    else -> formatAmount(metric.value, metric)
                },
                detail = "",
            )
        }
    }

    private fun progressItem(
        metric: UsageMetric,
        showAmounts: Boolean,
    ): WidgetMetricDisplay {
        val percent = progressPercent(metric)
        return WidgetMetricDisplay(
            label = metric.label,
            value = "${percent?.roundToInt() ?: 0}%",
            detail = if (showAmounts) {
                buildString {
                    append("已用 ")
                    append(formatAmount(metric.used, metric))
                    append(" / ")
                    append(formatAmount(metric.limit, metric))
                    metric.remaining?.let {
                        append(" · 剩余 ")
                        append(formatAmount(it, metric))
                    }
                }
            } else {
                ""
            },
            reset = metric.windowEnd?.let {
                val resetAt = "重置 ${formatShortTime(it)}"
                val remaining = remainingDuration(it)
                if (remaining.isEmpty()) resetAt else "$resetAt · 剩余 $remaining"
            },
            progressPercent = percent?.roundToInt()?.coerceIn(0, 100),
        )
    }

    private fun balanceCaption(metric: UsageMetric): String = when (metric.id) {
        "balance" -> "账户余额"
        "grantedBalance" -> "赠金余额"
        "toppedUpBalance" -> "充值余额"
        else -> metric.label
    }

    private fun statusCaption(metric: UsageMetric): String = when (metric.id) {
        "availability" -> "账户状态"
        else -> metric.label
    }

    internal fun metricItemViews(context: Context, item: WidgetMetricDisplay): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_metric_item)
        views.setTextViewText(R.id.widget_metric_label, item.label)
        views.setTextViewText(R.id.widget_metric_value, item.value)
        views.setTextViewText(R.id.widget_metric_detail, item.detail)
        if (item.progressPercent == null) {
            views.setViewVisibility(R.id.widget_metric_progress, android.view.View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_metric_progress, android.view.View.VISIBLE)
            views.setProgressBar(
                R.id.widget_metric_progress,
                100,
                item.progressPercent,
                false,
            )
        }
        if (item.reset == null) {
            views.setViewVisibility(R.id.widget_metric_reset, android.view.View.GONE)
            views.setTextViewText(R.id.widget_metric_reset, "")
        } else {
            views.setViewVisibility(R.id.widget_metric_reset, android.view.View.VISIBLE)
            views.setTextViewText(R.id.widget_metric_reset, item.reset)
        }
        return views
    }

    private fun progressPercent(metric: UsageMetric): Double? {
        val used = metric.used ?: return null
        val limit = metric.limit ?: return null
        if (limit.compareTo(BigDecimal.ZERO) == 0) return null
        return used.toDouble() / limit.toDouble() * 100.0
    }

    private fun formatAmount(value: BigDecimal?, metric: UsageMetric): String = when (metric.unit) {
        UsageMetricUnit.Currency -> formatCurrency(value, metric.currencyCode)
        else -> formatPlain(value)
    }

    private fun formatPlain(value: BigDecimal?): String {
        if (value == null) return "-"
        val stripped = value.stripTrailingZeros()
        return if (stripped.compareTo(BigDecimal.ZERO) == 0) "0" else stripped.toPlainString()
    }

    private fun formatGrouped(value: BigDecimal?): String {
        if (value == null) return "-"
        val plain = formatPlain(value)
        val negative = plain.startsWith("-")
        val body = if (negative) plain.substring(1) else plain
        val dot = body.indexOf('.')
        val integer = if (dot < 0) body else body.substring(0, dot)
        val fraction = if (dot < 0) "" else body.substring(dot)
        val grouped = integer.reversed().chunked(3).joinToString(",").reversed()
        return (if (negative) "-" else "") + grouped + fraction
    }

    private fun formatCompact(value: BigDecimal?): String {
        val number = value?.toDouble() ?: return "-"
        return when {
            number >= 1_000_000 || number <= -1_000_000 -> String.format(Locale.US, "%.1fM", number / 1_000_000)
            number >= 1_000 || number <= -1_000 -> String.format(Locale.US, "%.1fK", number / 1_000)
            else -> formatPlain(value)
        }
    }

    private fun formatCurrency(value: BigDecimal?, currencyCode: String?): String {
        val amount = value?.setScale(2, RoundingMode.HALF_UP)?.toPlainString() ?: "-"
        return when (currencyCode?.uppercase()) {
            "CNY", "RMB", "¥" -> "¥$amount"
            "USD", "$" -> "\$$amount"
            "EUR", "€" -> "€$amount"
            null -> amount
            else -> "$amount $currencyCode"
        }
    }

    private fun remainingDuration(end: Instant): String {
        val now = Instant.now()
        if (!end.isAfter(now)) return "已结束"
        val totalMinutes = java.time.Duration.between(now, end).toMinutes().coerceAtLeast(1)
        val days = totalMinutes / (24 * 60)
        val hours = (totalMinutes % (24 * 60)) / 60
        val minutes = totalMinutes % 60
        return listOfNotNull(
            if (days > 0) "${days}天" else null,
            if (hours > 0) "${hours}小时" else null,
            if (minutes > 0) "${minutes}分钟" else null,
        ).joinToString(" ").ifEmpty { "0分钟" }
    }

    private fun formatShortTime(instant: Instant?): String {
        if (instant == null) return "-"
        return DateTimeFormatter.ofPattern("MM-dd HH:mm").format(instant.atZone(ZoneId.systemDefault()))
    }

    private fun formatFullTime(instant: Instant?): String {
        if (instant == null) return "-"
        return DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").format(instant.atZone(ZoneId.systemDefault()))
    }
}
