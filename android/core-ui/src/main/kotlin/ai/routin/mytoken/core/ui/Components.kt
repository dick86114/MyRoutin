package ai.routin.mytoken.core.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.animateColorAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 玻璃控件统一设计规则：
 * - 交互控件（按钮/开关/chip）统一胶囊圆角，容器卡片 14-16dp 圆角；
 * - 全局唯一强调色 = 主题 primary，破坏性操作 = 主题 error；
 * - 明暗两套主题都按底色亮度自动切换，文字对比度满足 WCAG AA。
 */

/** 玻璃按钮的语义色调。 */
enum class GlassButtonTone { Primary, Neutral, Destructive }

private data class GlassToneColors(
    val base: Color,
    val content: Color,
) {
    companion object {
        @Composable
        fun of(tone: GlassButtonTone): GlassToneColors {
            val scheme = MaterialTheme.colorScheme
            return when (tone) {
                GlassButtonTone.Primary -> GlassToneColors(scheme.primary, scheme.primary)
                GlassButtonTone.Neutral -> GlassToneColors(scheme.onSurface, scheme.onSurface)
                GlassButtonTone.Destructive -> GlassToneColors(scheme.error, scheme.error)
            }
        }
    }
}

@Composable
private fun isDarkTheme(): Boolean = MaterialTheme.colorScheme.background.luminance() < 0.5f

/**
 * 液态玻璃按钮：胶囊形、渐变玻璃底、同色系描边。
 * [GlassButtonTone.Primary] 只给当前区块的主操作，避免一屏多个强强调。
 */
@Composable
fun GlassButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tone: GlassButtonTone = GlassButtonTone.Neutral,
    enabled: Boolean = true,
) {
    val toneColors = GlassToneColors.of(tone)
    val dark = isDarkTheme()
    val shape = RoundedCornerShape(100)
    val containerAlpha = if (dark) 0.22f else 0.10f
    val contentAlpha = if (enabled) 1f else 0.45f
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .clip(shape)
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        toneColors.base.copy(alpha = containerAlpha * 1.6f),
                        toneColors.base.copy(alpha = containerAlpha * 0.7f),
                    )
                )
            )
            .border(1.dp, toneColors.base.copy(alpha = if (dark) 0.45f else 0.30f), shape)
            .clickable(
                interactionSource = interactionSource,
                indication = ripple(color = toneColors.base),
                enabled = enabled,
                onClick = onClick,
            )
            .padding(horizontal = 20.dp, vertical = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = toneColors.content.copy(alpha = contentAlpha),
        )
    }
}

/**
 * 液态玻璃开关：胶囊轨道 + 滑动圆点，选中态使用主题强调色。
 * 无障碍语义与 Material Switch 一致（Role.Switch + contentDescription）。
 */
@Composable
fun GlassSwitch(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
) {
    val dark = isDarkTheme()
    val primary = MaterialTheme.colorScheme.primary
    val onSurface = MaterialTheme.colorScheme.onSurface
    val trackBase = if (checked) primary else onSurface
    val trackAlpha = when {
        checked -> if (dark) 0.30f else 0.16f
        else -> if (dark) 0.10f else 0.07f
    }
    val thumbColor by animateColorAsState(
        targetValue = if (checked) primary else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "glassSwitchThumb",
    )
    val thumbOffset by animateDpAsState(
        targetValue = if (checked) 25.dp else 3.dp,
        label = "glassSwitchThumbOffset",
    )
    val trackWidth = 52.dp
    val trackHeight = 31.dp
    Box(
        modifier = modifier
            .width(trackWidth)
            .height(trackHeight)
            .clip(RoundedCornerShape(100))
            .background(trackBase.copy(alpha = trackAlpha))
            .border(1.dp, trackBase.copy(alpha = if (checked) 0.45f else 0.18f), RoundedCornerShape(100))
            .toggleable(
                value = checked,
                role = Role.Switch,
                onValueChange = { onCheckedChange?.invoke(it) },
            )
            .semantics { contentDescription?.let { this.contentDescription = it } },
    ) {
        Box(
            modifier = Modifier
                .padding(top = 2.5.dp)
                .padding(start = thumbOffset)
                .requiredSize(26.dp)
                .clip(RoundedCornerShape(100))
                .background(thumbColor),
        )
    }
}

/** 与整体玻璃语言统一的 FilterChip 配色：选中态用强调色而不是默认的绿系 secondaryContainer。 */
@Composable
fun glassFilterChipColors(selected: Boolean) = FilterChipDefaults.filterChipColors(
    containerColor = Color.Transparent,
    labelColor = MaterialTheme.colorScheme.onSurfaceVariant,
    selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = if (isDarkTheme()) 0.26f else 0.14f),
    selectedLabelColor = MaterialTheme.colorScheme.primary,
)

@Composable
fun glassFilterChipBorder(selected: Boolean) = FilterChipDefaults.filterChipBorder(
    enabled = true,
    selected = selected,
    borderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = if (isDarkTheme()) 0.22f else 0.28f),
    selectedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = if (isDarkTheme()) 0.60f else 0.50f),
    borderWidth = 1.dp,
    selectedBorderWidth = 1.dp,
)

/**
 * 液态玻璃输入框：玻璃容器 + 透明输入底；聚焦时显示强调色描边。
 * 保留 Material OutlinedTextField 的完整编辑行为（密钥遮罩、trailing 图标、testTag）。
 */
@Composable
fun GlassTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    trailingIcon: @Composable (() -> Unit)? = null,
) {
    LiquidGlassSurface(shape = RoundedCornerShape(14.dp)) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            label = { Text(text = label) },
            singleLine = singleLine,
            visualTransformation = visualTransformation,
            trailingIcon = trailingIcon,
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                focusedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.55f),
                unfocusedBorderColor = Color.Transparent,
                disabledBorderColor = Color.Transparent,
                cursorColor = MaterialTheme.colorScheme.primary,
                focusedLabelColor = MaterialTheme.colorScheme.primary,
                unfocusedLabelColor = MaterialTheme.colorScheme.onSurfaceVariant,
            ),
            // modifier（含 testTag）落在输入框本体上，语义（RequestFocus 等）才能被测试命中。
            modifier = modifier.fillMaxWidth(),
        )
    }
}

/**
 * Compose 的玻璃拟态实现：半透明多层底色 + 高光描边 + 顶部反光。
 * Android 10+ 可稳定渲染，且不会牺牲文字对比度。
 */
@Composable
fun LiquidGlassSurface(
    modifier: Modifier = Modifier,
    shape: RoundedCornerShape = RoundedCornerShape(24.dp),
    contentAlignment: Alignment = Alignment.TopStart,
    content: @Composable BoxScope.() -> Unit,
) {
    val isDark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val baseColor = if (isDark) Color(0xFF151921) else Color.White
    val borderColor = if (isDark) Color.White.copy(alpha = 0.20f) else Color.White.copy(alpha = 0.72f)
    val backgroundBrush = remember(isDark, baseColor) {
        Brush.verticalGradient(
            colors = listOf(
                baseColor.copy(alpha = if (isDark) 0.78f else 0.82f),
                baseColor.copy(alpha = if (isDark) 0.62f else 0.68f),
            )
        )
    }
    val borderBrush = remember(isDark, borderColor) {
        Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = if (isDark) 0.36f else 0.90f),
                borderColor.copy(alpha = 0.14f),
                Color.White.copy(alpha = if (isDark) 0.22f else 0.64f),
            )
        )
    }
    Box(
        modifier = modifier
            .clip(shape)
            .background(brush = backgroundBrush)
            .border(width = Dp.Hairline, brush = borderBrush, shape = shape),
        contentAlignment = contentAlignment,
    ) {
        content()
    }
}

data class GlassNavItem(
    val label: String,
    val icon: ImageVector,
    val contentDescription: String,
    val selected: Boolean,
    val onClick: () -> Unit,
)

@Composable
fun LiquidGlassBottomBar(
    items: List<GlassNavItem>,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxWidth()) {
        LiquidGlassSurface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 16.dp)
                .padding(bottom = 4.dp)
                .fillMaxWidth()
                .height(64.dp),
            shape = RoundedCornerShape(32.dp),
            contentAlignment = Alignment.Center,
        ) {
            Row(
                modifier = Modifier.fillMaxSize().padding(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                items.forEachIndexed { index, item ->
                    if (index > 0) Box(modifier = Modifier.size(2.dp))
                    val interactionSource = remember { MutableInteractionSource() }
                    val contentColor by animateColorAsState(
                        targetValue = if (item.selected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        label = "tabContentColor",
                    )
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxSize()
                            .clip(RoundedCornerShape(26.dp))
                            .clickable(
                                interactionSource = interactionSource,
                                indication = ripple(color = contentColor),
                                onClick = item.onClick,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp, vertical = 5.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = item.contentDescription,
                                tint = contentColor,
                            )
                            Text(
                                text = item.label,
                                style = MaterialTheme.typography.labelSmall,
                                color = contentColor,
                            )
                        }
                    }
                }
            }
        }
    }
}
@Composable
fun SectionCard(
    title: String,
    modifier: Modifier = Modifier,
    supportingText: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                if (supportingText != null) {
                    Text(
                        text = supportingText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
            content()
        }
    }
}

@Composable
fun SettingRow(
    title: String,
    supportingText: String? = null,
    trailing: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
            )
            if (supportingText != null) {
                Text(
                    text = supportingText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        trailing()
    }
}
