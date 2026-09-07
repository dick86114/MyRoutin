package ai.routin.mytoken.feature.home

import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.UUID

/**
 * Collapsible provider section: header with provider accent color, credential count and
 * expand/collapse toggle, followed by the provider's credential cards. Mirrors the macOS
 * popover provider grouping in a touch-friendly vertical layout.
 */
@Composable
fun ProviderGroupSection(
    group: ProviderGroupUi,
    onToggleGroup: (ProviderId) -> Unit,
    onOpenCredential: (UUID) -> Unit,
    onRefreshCredential: (UUID) -> Unit,
    modifier: Modifier = Modifier,
) {
    val accent = ProviderCatalog.accentColor(group.providerId)
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = accent.copy(alpha = 0.08f),
        border = BorderStroke(1.dp, accent.copy(alpha = 0.20f)),
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) { onToggleGroup(group.providerId) }
                    .semantics {
                        stateDescription = if (group.isCollapsed) "已收起" else "已展开"
                    }
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = group.displayName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = accent,
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = "${group.cards.size}",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.width(4.dp))
                Icon(
                    imageVector = if (group.isCollapsed) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowUp,
                    contentDescription = if (group.isCollapsed) {
                        "展开${group.displayName}分组"
                    } else {
                        "收起${group.displayName}分组"
                    },
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!group.isCollapsed) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp)
                        .padding(bottom = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    group.cards.forEach { card ->
                        CredentialUsageCard(
                            card = card,
                            onOpen = { onOpenCredential(card.credential.id) },
                            onRetry = { onRefreshCredential(card.credential.id) },
                        )
                    }
                }
            }
        }
    }
}
