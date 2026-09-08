package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.core.ui.LiquidGlassSurface
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.zIndex
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.util.UUID
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

private fun kindLabel(kind: CredentialKind): String = when (kind) {
    CredentialKind.BearerApiKey -> "Bearer Token"
    CredentialKind.ApiKey -> "API Key"
    CredentialKind.AccessKeyPair -> "Access Key Pair"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CredentialListScreen(
    state: CredentialListUiState,
    onToggleEnabled: (Credential) -> Unit,
    onMove: (Int, Int) -> Unit,
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
                title = {
                    Text(
                        text = "凭证",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                actions = {
                    IconButton(onClick = onImportFromMac) {
                        Icon(imageVector = Icons.Filled.QrCodeScanner, contentDescription = "从 Mac 导入")
                    }
                    IconButton(onClick = onAddManually) {
                        Icon(imageVector = Icons.Filled.Add, contentDescription = "手动添加")
                    }
                },
            )
        },
    ) { padding ->
        if (state.items.isEmpty()) {
            EmptyState(
                modifier = Modifier.padding(padding),
                onImportFromMac = onImportFromMac,
                onAddManually = onAddManually,
            )
        } else {
            val listState = rememberLazyListState()
            val hapticView = LocalView.current
            val reorderableState = rememberReorderableLazyListState(listState) { from, to ->
                onMove(from.index, to.index)
                hapticView.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            }
            LazyColumn(
                state = listState,
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 96.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(
                    state.items,
                    key = { _, item -> item.id },
                    contentType = { _, _ -> "credential-row" },
                ) { _, credential ->
                    ReorderableItem(reorderableState, key = credential.id) { isDragging ->
                        val elevation by animateDpAsState(
                            targetValue = if (isDragging) 8.dp else 0.dp,
                            label = "credentialDragElevation",
                        )
                        CredentialRow(
                            credential = credential,
                            providerName = ProviderNames.displayName(credential.providerId),
                            elevation = elevation,
                            isDragging = isDragging,
                            dragHandleModifier = Modifier.longPressDraggableHandle(
                                onDragStarted = {
                                    hapticView.performHapticFeedback(
                                        HapticFeedbackConstants.KEYBOARD_TAP,
                                    )
                                },
                                onDragStopped = {
                                    hapticView.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                                },
                            ),
                            onToggleEnabled = { onToggleEnabled(credential) },
                            onEdit = { onEditCredential(credential.id) },
                            onRequestDelete = { onRequestDelete(credential) },
                        )
                    }
                }
            }
        }
    }

    state.pendingDeletion?.let { target ->
        AlertDialog(
            onDismissRequest = onDismissDelete,
            title = { Text(text = "删除凭证") },
            text = { Text(text = "确定删除「${target.name}」吗？只删除本机数据，不影响供应商账户。") },
            confirmButton = {
                TextButton(onClick = onConfirmDelete) { Text(text = "删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = onDismissDelete) { Text(text = "取消") } },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CredentialRow(
    credential: Credential,
    providerName: String,
    elevation: androidx.compose.ui.unit.Dp,
    isDragging: Boolean,
    dragHandleModifier: Modifier,
    onToggleEnabled: () -> Unit,
    onEdit: () -> Unit,
    onRequestDelete: () -> Unit,
) {
    LiquidGlassSurface(
        modifier = Modifier
            .fillMaxWidth()
            .then(dragHandleModifier)
            .zIndex(if (isDragging) 1f else 0f)
            .graphicsLayer {
                scaleX = if (isDragging) 1.02f else 1f
                scaleY = if (isDragging) 1.02f else 1f
                shadowElevation = elevation.toPx()
                shape = androidx.compose.ui.graphics.RectangleShape
                clip = false
            },
        shape = RoundedCornerShape(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.DragHandle,
                contentDescription = "长按拖动排序",
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 10.dp),
            ) {
                Text(
                    text = credential.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "$providerName · ${kindLabel(credential.credentialKind)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(
                checked = credential.isEnabled,
                onCheckedChange = { onToggleEnabled() },
                modifier = Modifier.semantics { contentDescription = "启用 ${credential.name}" },
            )
            IconButton(onClick = onRequestDelete) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = "删除 ${credential.name}",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun EmptyState(
    modifier: Modifier = Modifier,
    onImportFromMac: () -> Unit,
    onAddManually: () -> Unit,
) {
    Box(modifier = modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = "尚未添加凭证", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "从 Mac 迁移，或手动添加供应商凭证",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(24.dp))
            Button(onClick = onImportFromMac) { Text(text = "从 Mac 导入") }
            Spacer(modifier = Modifier.height(8.dp))
            FilledTonalButton(onClick = onAddManually) { Text(text = "手动添加") }
        }
    }
}
