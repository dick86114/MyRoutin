package ai.routin.mytoken.feature.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

internal object ModelIdChipPalette {
    val colorIndices = listOf(
        Color(0xFF1565C0),
        Color(0xFF00838F),
        Color(0xFF3949AB),
        Color(0xFF2E7D32),
        Color(0xFFEF6C00),
        Color(0xFF6A1B9A),
        Color(0xFFAD1457),
        Color(0xFF00897B),
        Color(0xFF4E342E),
        Color(0xFFC62828),
        Color(0xFF37474F),
        Color(0xFFB26A00),
    )

    fun colorIndex(modelID: String): Int {
        var hash = 0xcbf29ce484222325UL
        modelID.forEach { character ->
            hash = (hash xor character.code.toULong()) * 0x100000001b3UL
        }
        return (hash % colorIndices.size.toULong()).toInt()
    }

    fun color(modelID: String): Color = colorIndices[colorIndex(modelID)]
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun AllowedModelsSection(models: List<String>, modifier: Modifier = Modifier) {
    var copiedModelID by remember { mutableStateOf<String?>(null) }
    val clipboard = LocalClipboardManager.current

    LaunchedEffect(copiedModelID) {
        if (copiedModelID != null) {
            delay(1_200)
            copiedModelID = null
        }
    }

    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            text = "允许模型",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (models.isNotEmpty()) {
            Text(
                text = "${models.size} 个 · 点击复制",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (models.isEmpty()) {
        Text(
            text = "接口未返回",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            modifier = modifier.padding(top = 8.dp),
        )
        return
    }

    FlowRow(
        modifier = modifier.fillMaxWidth().padding(top = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        models.forEach { modelID ->
            ModelIDChip(
                modelID = modelID,
                isCopied = copiedModelID == modelID,
                onCopy = { copied ->
                    clipboard.setText(AnnotatedString(copied))
                    copiedModelID = copied
                },
            )
        }
    }
}

@Composable
private fun ModelIDChip(
    modelID: String,
    isCopied: Boolean,
    onCopy: (String) -> Unit,
) {
    val accent = ModelIdChipPalette.color(modelID)
    val description = if (isCopied) "已复制模型 ID $modelID" else "复制模型 ID $modelID"

    Surface(
        onClick = { onCopy(modelID) },
        shape = CircleShape,
        color = accent.copy(alpha = if (isCopied) 0.24f else 0.11f),
        border = BorderStroke(1.dp, accent.copy(alpha = if (isCopied) 0.65f else 0.26f)),
        modifier = Modifier.semantics { contentDescription = description },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            Text(
                text = modelID,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
                color = accent,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (isCopied) {
                Icon(
                    imageVector = Icons.Filled.Check,
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.padding(0.dp),
                )
            }
        }
    }
}
