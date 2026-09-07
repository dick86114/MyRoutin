package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** 首页显示 section of the settings page (mobile-only display options). */
@Composable
fun DisplaySettingsSection(
    settings: DisplaySettings,
    onCardDensityChange: (CardDensity) -> Unit,
    onShowDisabledCredentialsChange: (Boolean) -> Unit,
    onDefaultExpandGroupsChange: (Boolean) -> Unit,
    onShowUsageProgressChange: (Boolean) -> Unit,
    onShowBalanceChange: (Boolean) -> Unit,
    onShowResetTimeChange: (Boolean) -> Unit,
) {
    Section(title = "首页显示") {
        Text(
            text = "卡片密度",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(vertical = 4.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = settings.cardDensity == CardDensity.STANDARD,
                onClick = { onCardDensityChange(CardDensity.STANDARD) },
                label = { Text(text = "标准") },
            )
            FilterChip(
                selected = settings.cardDensity == CardDensity.COMPACT,
                onClick = { onCardDensityChange(CardDensity.COMPACT) },
                label = { Text(text = "紧凑") },
            )
        }
        SettingSwitchRow(
            label = "显示已停用凭证",
            checked = settings.showDisabledCredentials,
            onChange = onShowDisabledCredentialsChange,
        )
        SettingSwitchRow(
            label = "默认展开分组",
            checked = settings.defaultExpandGroups,
            onChange = onDefaultExpandGroupsChange,
        )
        Text(
            text = "指标显隐",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(vertical = 4.dp),
        )
        SettingSwitchRow(
            label = "显示用量进度",
            checked = settings.showUsageProgress,
            onChange = onShowUsageProgressChange,
        )
        SettingSwitchRow(
            label = "显示余额",
            checked = settings.showBalance,
            onChange = onShowBalanceChange,
        )
        SettingSwitchRow(
            label = "显示重置时间",
            checked = settings.showResetTime,
            onChange = onShowResetTimeChange,
        )
    }
}
