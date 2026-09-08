package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import ai.routin.mytoken.core.ui.GlassButton
import ai.routin.mytoken.core.ui.GlassButtonTone
import ai.routin.mytoken.core.ui.GlassTextField
import ai.routin.mytoken.core.ui.glassFilterChipBorder
import ai.routin.mytoken.core.ui.glassFilterChipColors
import ai.routin.mytoken.core.ui.LiquidGlassSurface
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp

private fun kindLabel(kind: CredentialKind): String = when (kind) {
    CredentialKind.BearerApiKey -> "Bearer Token"
    CredentialKind.ApiKey -> "API Key"
    CredentialKind.AccessKeyPair -> "Access Key Pair"
}

/**
 * Credential editor. Fields are shown dynamically per [CredentialKind]:
 * Bearer API Key (Routin/NewAPI), API Key (DeepSeek/GLM), or
 * Access Key / Secret Access Key (Volcengine). Secrets are masked by default with a
 * temporary reveal toggle; validation messages align with the macOS editor.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CredentialEditorScreen(
    state: CredentialEditorUiState,
    onBack: () -> Unit,
    onProviderChange: (ProviderId) -> Unit,
    onNameChange: (String) -> Unit,
    onApiKeyChange: (String) -> Unit,
    onAccessKeyIDChange: (String) -> Unit,
    onSecretAccessKeyChange: (String) -> Unit,
    onRegionChange: (String) -> Unit,
    onBaseURLChange: (String) -> Unit,
    onUserIDChange: (String) -> Unit,
    onWebsiteURLChange: (String) -> Unit,
    onToggleSecretVisible: () -> Unit,
    onTestConnection: () -> Unit,
    onSave: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(text = if (state.isNew) "新增凭证" else "编辑凭证") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "返回",
                        )
                    }
                },
            )
        },
    ) { padding ->
        if (state.isLoading) {
            Column(modifier = Modifier.padding(padding).fillMaxSize()) {}
            return@Scaffold
        }
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (state.isNew) {
                LiquidGlassSurface(shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp)) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            text = "供应商",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            ProviderId.entries.forEach { provider ->
                                FilterChip(
                                    selected = state.providerId == provider,
                                    onClick = { onProviderChange(provider) },
                                    label = { Text(text = ProviderNames.displayName(provider)) },
                                    colors = glassFilterChipColors(selected = state.providerId == provider),
                                    border = glassFilterChipBorder(selected = state.providerId == provider),
                                )
                            }
                        }
                    }
                }
            } else {
                Text(
                    text = "${ProviderNames.displayName(state.providerId)} · ${kindLabel(state.credentialKind)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            GlassTextField(
                value = state.name,
                onValueChange = onNameChange,
                label = "名称",
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("editor_name"),
            )

            when (state.credentialKind) {
                CredentialKind.BearerApiKey -> SecretField(
                    label = "API Key（Bearer Token）",
                    value = state.apiKey,
                    onValueChange = onApiKeyChange,
                    isVisible = state.isSecretVisible,
                    onToggleVisible = onToggleSecretVisible,
                    testTag = "editor_api_key",
                )
                CredentialKind.ApiKey -> SecretField(
                    label = "API Key",
                    value = state.apiKey,
                    onValueChange = onApiKeyChange,
                    isVisible = state.isSecretVisible,
                    onToggleVisible = onToggleSecretVisible,
                    testTag = "editor_api_key",
                )
                CredentialKind.AccessKeyPair -> {
            GlassTextField(
                value = state.accessKeyID,
                onValueChange = onAccessKeyIDChange,
                label = "Access Key ID",
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("editor_access_key_id"),
                    )
                    SecretField(
                        label = "Secret Access Key",
                        value = state.secretAccessKey,
                        onValueChange = onSecretAccessKeyChange,
                        isVisible = state.isSecretVisible,
                        onToggleVisible = onToggleSecretVisible,
                        testTag = "editor_secret_access_key",
                    )
            GlassTextField(
                value = state.region,
                onValueChange = onRegionChange,
                label = "区域（默认 cn-beijing）",
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("editor_region"),
                    )
                }
            }

            if (state.providerId == ProviderId.NewAPI) {
                GlassTextField(
                    value = state.baseURL,
                    onValueChange = onBaseURLChange,
                    label = "接口地址",
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("editor_base_url"),
                )
                GlassTextField(
                    value = state.userID,
                    onValueChange = onUserIDChange,
                    label = "用户 ID",
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("editor_user_id"),
                )
            }

            GlassTextField(
                value = state.websiteURL,
                onValueChange = onWebsiteURLChange,
                label = "官网地址（可选）",
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("editor_website_url"),
            )

            state.validationError?.let { message ->
                Text(
                    text = message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            GlassButton(
                onClick = onTestConnection,
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isTestingConnection,
                text = if (state.isTestingConnection) "测试中…" else "测试连接",
            )

            state.testResultMessage?.let { message ->
                Text(
                    text = if (state.testSucceeded == true) "✓ $message" else "✗ $message",
                    color = if (state.testSucceeded == true) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.error
                    },
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (state.testSucceeded == false) {
                Text(
                    text = "测试失败仍可保存，失败原因不会丢失已填内容",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            GlassButton(
                onClick = onSave,
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isSaving,
                tone = GlassButtonTone.Primary,
                text = if (state.isSaving) "保存中…" else "保存",
            )
        }
    }
}

@Composable
private fun SecretField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    isVisible: Boolean,
    onToggleVisible: () -> Unit,
    testTag: String,
) {
    GlassTextField(
        value = value,
        onValueChange = onValueChange,
        label = label,
        visualTransformation = if (isVisible) {
            VisualTransformation.None
        } else {
            PasswordVisualTransformation()
        },
        trailingIcon = {
            IconButton(onClick = onToggleVisible) {
                Icon(
                    imageVector = if (isVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = if (isVisible) "隐藏密钥" else "显示密钥",
                )
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .testTag(testTag),
    )
}
