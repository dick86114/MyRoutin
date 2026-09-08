package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.core.ui.SectionCard
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import ai.routin.mytoken.core.ui.GlassButton
import ai.routin.mytoken.core.ui.GlassButtonTone
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun TransferPreviewScreen(
    state: TransferUiState.PreviewReady,
    onConfirm: (ImportConflictMode) -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            text = "确认导入",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 4.dp),
        )

        SectionCard(
            title = "迁移摘要",
            supportingText = "导出时间：${state.exportedAt}",
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SummaryCell("供应商", "${state.preview.providerCount}", Modifier.weight(1f))
                SummaryCell("凭证", "${state.preview.credentialCount}", Modifier.weight(1f))
                SummaryCell("敏感项", "${state.preview.sensitiveItemCount}", Modifier.weight(1f))
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(state.items, key = { it.credentialId }) { item ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(10.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            text = item.name,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = "供应商 ${item.providerId} · ${item.credentialKind}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        val flags = buildList {
                            if (item.hasSecret) add("含敏感信息") else add("无密钥")
                            if (item.conflictsWithExisting) add("已存在")
                        }
                        Text(
                            text = flags.joinToString(" · "),
                            style = MaterialTheme.typography.labelMedium,
                            color = if (item.hasSecret) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
        ) {
            GlassButton(onClick = onCancel, text = "取消")
            GlassButton(onClick = { onConfirm(ImportConflictMode.SKIP) }, text = "跳过重复")
            GlassButton(
                onClick = { onConfirm(ImportConflictMode.OVERWRITE) },
                tone = GlassButtonTone.Primary,
                text = "覆盖导入",
            )
        }
    }
}

@Composable
private fun SummaryCell(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

@Composable
fun TransferCompletedScreen(
    summary: ImportSummary,
    onDone: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "导入完成",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "新导入 ${summary.importedCount} · 覆盖 ${summary.overwrittenCount} · " +
                "跳过 ${summary.skippedCount} · 无密钥 ${summary.skippedWithoutSecretCount}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp),
        )
        GlassButton(
            onClick = onDone,
            tone = GlassButtonTone.Primary,
            text = "完成",
        )
    }
}
