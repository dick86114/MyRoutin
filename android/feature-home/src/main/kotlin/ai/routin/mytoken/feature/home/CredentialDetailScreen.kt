package ai.routin.mytoken.feature.home

import ai.routin.mytoken.core.ui.SectionCard
import ai.routin.mytoken.core.ui.GlassButton
import ai.routin.mytoken.core.ui.GlassButtonTone
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.UsageMetric
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val fullTimeFormatter = DateTimeFormatter.ofPattern("yyyy年MM月dd日 HH:mm:ss")

internal fun formatFullTime(instant: Instant?): String {
    if (instant == null) return "-"
    return fullTimeFormatter.format(instant.atZone(ZoneId.systemDefault()))
}

internal fun credentialKindLabel(
    kind: CredentialKind,
    provider: ai.routin.mytoken.domain.model.ProviderId,
): String = when (kind) {
    CredentialKind.BearerApiKey -> if (provider == ai.routin.mytoken.domain.model.ProviderId.Routin) "Plan Key" else "Bearer Token"
    CredentialKind.ApiKey -> "API Key"
    CredentialKind.AccessKeyPair -> "Access Key Pair"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CredentialDetailScreen(
    card: CredentialCardUi?,
    lowThresholdPercent: Int? = null,
    onBack: () -> Unit,
    onRefresh: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onCheckIn: (() -> Unit)? = null,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = card?.credential?.name ?: "凭证详情",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(imageVector = Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
        bottomBar = {
            if (card != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    GlassButton(
                        onClick = onRefresh,
                        modifier = Modifier.weight(1f),
                        tone = GlassButtonTone.Primary,
                        text = "刷新",
                    )
                    if (onCheckIn != null) {
                        GlassButton(
                            onClick = onCheckIn,
                            modifier = Modifier.weight(1f),
                            text = "签到",
                        )
                    }
                    GlassButton(
                        onClick = onEdit,
                        modifier = Modifier.weight(1f),
                        text = "编辑",
                    )
                    GlassButton(
                        onClick = onDelete,
                        modifier = Modifier.weight(1f),
                        tone = GlassButtonTone.Destructive,
                        text = "删除",
                    )
                }
            }
        },
    ) { padding ->
        if (card == null) {
            Text(
                text = "凭证不存在或已被删除",
                modifier = Modifier
                    .padding(padding)
                    .padding(24.dp),
            )
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text(
                        text = card.credential.name,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "${ProviderCatalog.displayName(card.credential.providerId)} · " +
                            credentialKindLabel(
                                kind = card.credential.credentialKind,
                                provider = card.credential.providerId,
                            ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (card.credential.isEnabled) Icons.Filled.CheckCircle else Icons.Filled.PauseCircle,
                        contentDescription = null,
                        tint = if (card.credential.isEnabled) statusColors().normal else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = if (card.credential.isEnabled) "已启用" else "已停用",
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }

            SectionCard(title = "状态") {
                DetailRow(
                    label = "最近更新",
                    value = card.snapshot?.fetchedAt?.let(::formatFullTime) ?: "尚未成功更新",
                )
                DetailRow(label = "当前状态", value = currentStatus(card))
                DetailRow(label = "套餐", value = planName(card))
                DetailRow(label = "数据时间", value = card.snapshot?.fetchedAt?.let(::formatFullTime) ?: "-")
                card.error?.let {
                    DetailRow(
                        label = "失败原因",
                        value = it.message ?: "刷新用量失败",
                        valueColor = MaterialTheme.colorScheme.error,
                    )
                }
            }

            UsageMetricsSection(card)
            if (card.credential.providerId == ai.routin.mytoken.domain.model.ProviderId.Routin) {
                RoutinPlanSection(card)
            }
            MetadataSection(
                metadata = card.credential.metadata,
                providerId = card.credential.providerId,
                lowThresholdPercent = lowThresholdPercent,
            )
        }
    }
}

@Composable
private fun UsageMetricsSection(card: CredentialCardUi) {
    SectionCard(title = "用量指标") {
        val metrics = card.snapshot?.metrics.orEmpty()
        if (metrics.isEmpty()) {
            Text(text = "暂无用量数据", style = MaterialTheme.typography.bodyMedium)
        } else {
            UsageMetricGrid(metrics = metrics)
        }
    }
}

@Composable
private fun RoutinPlanSection(card: CredentialCardUi) {
    val snapshot = card.snapshot ?: return
    val fiveHour = snapshot.metrics.firstOrNull { it.id == "fiveHour" }
    val weekly = snapshot.metrics.firstOrNull { it.id == "weekly" }
    SectionCard(title = "套餐状态") {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            DetailColumn("套餐", snapshot.planName.ifEmpty { "Plan Key" }, Modifier.weight(1f))
            DetailColumn("类型", usageType(snapshot.usageKind), Modifier.weight(1f))
            DetailColumn("状态", subscriptionStatus(card, snapshot.status), Modifier.weight(1f))
        }
    }

    SectionCard(title = "订阅与周期") {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            DetailColumn("订阅开始", formatFullTime(snapshot.subscriptionStartAt), Modifier.weight(1f))
            DetailColumn("订阅结束", formatFullTime(snapshot.subscriptionEndAt), Modifier.weight(1f))
        }
        Row(
            modifier = Modifier.padding(top = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            DetailColumn("5 小时结束", formatFullTime(fiveHour?.windowEnd), Modifier.weight(1f))
            DetailColumn("周结束", formatFullTime(weekly?.windowEnd), Modifier.weight(1f))
        }
    }

    SectionCard(title = "账户与模型") {
        val multipliers = snapshot.groupMultipliers
        DetailColumn(
            label = "分组倍率",
            value = if (multipliers.isEmpty()) {
                "-"
            } else {
                multipliers.joinToString("、") { "${it.name} ×${formatDecimal(it.multiplier)}" }
            },
        )
        DetailColumn(
            label = "允许模型",
            value = snapshot.allowedModels.ifEmpty { listOf("-") }.joinToString("、"),
            modifier = Modifier.padding(top = 10.dp),
        )
    }
}

@Composable
private fun MetadataSection(
    metadata: Map<CredentialMetadataKey, String>,
    providerId: ai.routin.mytoken.domain.model.ProviderId,
    lowThresholdPercent: Int?,
) {
    val showThreshold = providerId == ai.routin.mytoken.domain.model.ProviderId.DeepSeek && lowThresholdPercent != null
    if (metadata.isEmpty() && !showThreshold) return
    val uriHandler = LocalUriHandler.current
    SectionCard(title = "配置") {
        metadata.entries.sortedBy { it.key.rawValue }.forEach { (key, value) ->
            val label = metadataLabel(key)
            if (key == CredentialMetadataKey.WebsiteURL) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = value,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.clickable {
                            runCatching { uriHandler.openUri(value) }
                        },
                    )
                }
            } else {
                DetailRow(label = label, value = metadataValue(key, value))
            }
        }
        if (showThreshold) {
            DetailRow(label = "低额度预警值", value = "$lowThresholdPercent")
        }
    }
}

@Composable
internal fun DetailRow(
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurface,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = valueColor,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(1.4f),
        )
    }
}

@Composable
internal fun DetailColumn(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    valueColor: Color = MaterialTheme.colorScheme.onSurface,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = valueColor,
        )
    }
}

private fun currentStatus(card: CredentialCardUi): String = when {
    !card.credential.isEnabled -> "已停用"
    card.status == ai.routin.mytoken.domain.usage.RefreshStatus.Loading -> "正在刷新"
    card.status == ai.routin.mytoken.domain.usage.RefreshStatus.Failed -> "更新失败"
    card.snapshot == null -> "暂无用量数据"
    card.isStale -> "数据已过期"
    else -> "用量数据可用"
}

private fun planName(card: CredentialCardUi): String {
    card.snapshot?.planName?.takeIf { it.isNotEmpty() }?.let { return it }
    return when (card.credential.providerId) {
        ai.routin.mytoken.domain.model.ProviderId.Routin -> "Plan Key"
        ai.routin.mytoken.domain.model.ProviderId.DeepSeek -> "API 余额"
        ai.routin.mytoken.domain.model.ProviderId.Glm -> "Coding Plan"
        ai.routin.mytoken.domain.model.ProviderId.Volcengine ->
            if (card.credential.metadata[CredentialMetadataKey.PlanType] == "coding") "Coding Plan" else "Agent Plan"
        ai.routin.mytoken.domain.model.ProviderId.NewAPI -> "API 额度"
    }
}

private fun usageType(kind: String?): String = when (kind) {
    "periodic" -> "周期订阅"
    "tokenPack" -> "Token 资源包"
    "balance" -> "余额查询"
    "codingPlan" -> "Coding Plan"
    "agentPlan" -> "Agent Plan"
    "usageStats" -> "用量统计"
    else -> "-"
}

private fun subscriptionStatus(card: CredentialCardUi, status: Int?): String = when {
    card.status == ai.routin.mytoken.domain.usage.RefreshStatus.Failed -> card.error?.message ?: "更新失败"
    card.snapshot == null -> "暂无数据"
    card.isStale -> "已过期"
    status == null || status == 1 -> "正常"
    else -> "状态 $status"
}

private fun metadataLabel(key: CredentialMetadataKey): String = when (key) {
    CredentialMetadataKey.BaseURL -> "接口地址"
    CredentialMetadataKey.UserID -> "用户 ID"
    CredentialMetadataKey.Region -> "区域"
    CredentialMetadataKey.PlanType -> "计划类型"
    CredentialMetadataKey.UsageKind -> "用量类型"
    CredentialMetadataKey.WebsiteURL -> "官网地址"
}

private fun metadataValue(key: CredentialMetadataKey, value: String): String = when (key) {
    CredentialMetadataKey.PlanType -> if (value == "coding") "Coding Plan" else "Agent Plan"
    CredentialMetadataKey.UsageKind -> if (value == "tokenPack") "Token 资源包" else value
    else -> value
}
