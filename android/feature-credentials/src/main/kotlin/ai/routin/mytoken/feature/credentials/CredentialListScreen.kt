package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.UUID
import kotlin.math.roundToInt

private fun kindLabel(kind: CredentialKind): String = when (kind) {
    CredentialKind.BearerApiKey -> "Bearer Token"
    CredentialKind.ApiKey -> "API Key"
    CredentialKind.AccessKeyPair -> "Access Key Pair"
}

/**
 * Credential management screen: provider-grouped list, search, enable/disable toggles,
 * long-press drag ordering (Android-local persistence), edit/delete entries with a
 * deletion confirmation, and the "import from Mac" entry.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CredentialListScreen(
    state: CredentialListUiState,
    onSearchQueryChange: (String) -> Unit,
    onToggleEnabled: (Credential) -> Unit,
    onTogglePinned: (Credential, Boolean) -> Unit,
    onMoveWithinGroup: (ProviderId, Int, Int) -> Unit,
    onEditCredential: (UUID) -> Unit,
    onRequestDelete: (Credential) -> Unit,
    onDismissDelete: () -> Unit,
    onConfirmDelete: () -> Unit,
    onImportFromMac: () -> Unit,
    onAddManually: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = "凭证") },
                actions = {
                    IconButton(onClick = onImportFromMac) {
                        Icon(
                            imageVector = Icons.Filled.Add,
                            contentDescription = "从 Mac 导入",
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = onSearchQueryChange,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .testTag("credential_search"),
                singleLine = true,
                placeholder = { Text(text = "搜索凭证") },
            )
            state.errorMessage?.let { message ->
                // Non-blocking error surface; the message never contains secret material.
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
            if (state.groups.isEmpty()) {
                EmptyState(onImportFromMac = onImportFromMac, onAddManually = onAddManually)
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    state.groups.forEach { group ->
                        item(key = "header-${group.providerId}") {
                            Text(
                                text = group.displayName,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                        items(group.rows, key = { it.credential.id }) { row ->
                            val index = group.rows.indexOf(row)
                            CredentialRow(
                                row = row,
                                providerName = group.displayName,
                                onToggleEnabled = { onToggleEnabled(row.credential) },
                                onTogglePinned = onTogglePinned,
                                onMove = { from, to -> onMoveWithinGroup(group.providerId, from, to) },
                                rowIndex = index,
                                onEdit = { onEditCredential(row.credential.id) },
                                onRequestDelete = { onRequestDelete(row.credential) },
                            )
                        }
                    }
                }
            }
        }
    }

    state.pendingDeletion?.let { target ->
        AlertDialog(
            onDismissRequest = onDismissDelete,
            title = { Text(text = "删除凭证") },
            text = {
                Text(
                    text = "确定删除「${target.name}」吗？只删除本机数据，不影响供应商账户。",
                )
            },
            confirmButton = {
                TextButton(onClick = onConfirmDelete) {
                    Text(text = "删除", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = onDismissDelete) {
                    Text(text = "取消")
                }
            },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CredentialRow(
    row: CredentialRowUi,
    providerName: String,
    rowIndex: Int,
    onToggleEnabled: () -> Unit,
    onTogglePinned: (Credential, Boolean) -> Unit,
    onMove: (Int, Int) -> Unit,
    onEdit: () -> Unit,
    onRequestDelete: () -> Unit,
) {
    var dragOffset by remember { mutableFloatStateOf(0f) }
    var rowHeight by remember { mutableStateOf(1f) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .onSizeChanged { rowHeight = it.height.toFloat().coerceAtLeast(1f) }
            .pointerInput(row.credential.id) {
                detectDragGesturesAfterLongPress(
                    onDragStart = { dragOffset = 0f },
                    onDrag = { _, amount -> dragOffset += amount.y },
                    onDragEnd = {
                        val shift = (dragOffset / rowHeight).roundToInt()
                        if (shift != 0) onMove(rowIndex, rowIndex + shift)
                        dragOffset = 0f
                    },
                    onDragCancel = { dragOffset = 0f },
                )
            },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.DragHandle,
                contentDescription = "长按拖动排序",
                modifier = Modifier.padding(end = 4.dp),
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .combinedClickable(onClick = onEdit, onLongClick = onRequestDelete),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = row.credential.name,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Medium,
                    )
                    if (row.isPinned) {
                        Spacer(modifier = Modifier.height(0.dp))
                        Icon(
                            imageVector = Icons.Filled.PushPin,
                            contentDescription = "已置顶",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                    }
                }
                Text(
                    text = "$providerName · ${kindLabel(row.credential.credentialKind)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(
                onClick = { onTogglePinned(row.credential, !row.isPinned) },
                modifier = Modifier.semantics {
                    contentDescription = if (row.isPinned) "取消置顶" else "置顶凭证"
                },
            ) {
                Icon(
                    imageVector = if (row.isPinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    contentDescription = null,
                )
            }
            Switch(
                checked = row.credential.isEnabled,
                onCheckedChange = { onToggleEnabled() },
                modifier = Modifier.semantics { contentDescription = "启用 ${row.credential.name}" },
            )
            IconButton(
                onClick = onRequestDelete,
                modifier = Modifier.semantics { contentDescription = "删除 ${row.credential.name}" },
            ) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun EmptyState(
    onImportFromMac: () -> Unit,
    onAddManually: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "尚未添加凭证",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "先在 Mac 的 MyToken 中发起迁移，或手动添加一个供应商凭证",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(24.dp))
            TextButton(onClick = onImportFromMac) {
                Text(text = "从 Mac 导入")
            }
            TextButton(onClick = onAddManually) {
                Text(text = "手动添加")
            }
        }
    }
}
