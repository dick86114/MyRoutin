package ai.routin.mytoken.feature.transfer

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Import confirmation screen. Shows counts and credential metadata only —
 * no secret material is ever rendered here.
 */
@Composable
fun TransferPreviewScreen(
    state: TransferUiState.PreviewReady,
    onConfirm: (ImportConflictMode) -> Unit,
    onCancel: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(text = "确认导入", style = MaterialTheme.typography.headlineSmall)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Text(text = "供应商：${state.preview.providerCount}")
            Text(text = "凭证：${state.preview.credentialCount}")
            Text(text = "敏感项：${state.preview.sensitiveItemCount}")
        }
        Text(
            text = "导出时间：${state.exportedAt}",
            style = MaterialTheme.typography.bodySmall
        )
        HorizontalDivider()
        LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f)) {
            items(state.items, key = { it.credentialId }) { item ->
                Card(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text(text = item.name, style = MaterialTheme.typography.titleMedium)
                        Text(
                            text = "供应商 ${item.providerId} · ${item.credentialKind}",
                            style = MaterialTheme.typography.bodySmall
                        )
                        val flags = buildList {
                            if (item.hasSecret) add("含敏感信息") else add("无密钥")
                            if (item.conflictsWithExisting) add("已存在，将按所选方式处理")
                        }
                        Text(text = flags.joinToString(" · "), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End)
        ) {
            OutlinedButton(onClick = onCancel) {
                Text(text = "取消")
            }
            Button(onClick = { onConfirm(ImportConflictMode.SKIP) }) {
                Text(text = "导入（跳过重复）")
            }
            Button(onClick = { onConfirm(ImportConflictMode.OVERWRITE) }) {
                Text(text = "导入（覆盖重复）")
            }
        }
    }
}

/** Completion view shown after a successful import. */
@Composable
fun TransferCompletedScreen(
    summary: ImportSummary,
    onDone: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(text = "导入完成", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "新导入 ${summary.importedCount} 项 · 覆盖 ${summary.overwrittenCount} 项 · " +
                "跳过 ${summary.skippedCount} 项 · 无密钥跳过 ${summary.skippedWithoutSecretCount} 项"
        )
        Button(onClick = onDone) {
            Text(text = "完成")
        }
    }
}
