package ai.routin.mytoken.widget

import ai.routin.mytoken.MyTokenApplication
import ai.routin.mytoken.core.ui.MyTokenTheme
import ai.routin.mytoken.feature.settings.AppThemeMode
import ai.routin.mytoken.feature.settings.DisplaySettings
import ai.routin.mytoken.feature.home.ProviderCatalog
import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.util.UUID
import kotlinx.coroutines.launch

class CredentialWidgetConfigActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(Activity.RESULT_CANCELED)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val graph = (application as MyTokenApplication).graph
        val store = WidgetSelectionStore(this)
        setContent {
            val displaySettings by graph.displaySettingsStore.settings
                .collectAsState(initial = DisplaySettings())
            val darkTheme = when (displaySettings.themeMode) {
                AppThemeMode.SYSTEM -> isSystemInDarkTheme()
                AppThemeMode.LIGHT -> false
                AppThemeMode.DARK -> true
            }
            val credentials by remember { graph.credentialRepository.observeCredentials() }
                .collectAsState(initial = emptyList())
            val selectableCredentials = credentials.filter { it.isEnabled }
            val scope = rememberCoroutineScope()

            MyTokenTheme(darkTheme = darkTheme) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    CredentialSelector(
                        title = if (intent?.action == ACTION_EDIT_WIDGET) "更换凭证" else "选择小组件凭证",
                        selectedId = store.selectedCredentialId(appWidgetId),
                        credentials = selectableCredentials,
                        onSelect = { credential ->
                            scope.launch {
                                store.setSelectedCredential(appWidgetId, credential.id)
                                CredentialWidgetUpdater.update(this@CredentialWidgetConfigActivity, graph, appWidgetId)
                                setResult(
                                    Activity.RESULT_OK,
                                    Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
                                )
                                finish()
                            }
                        },
                    )
                }
            }
        }
    }

    companion object {
        const val ACTION_EDIT_WIDGET = "ai.routin.mytoken.action.EDIT_WIDGET_CREDENTIAL"
    }
}

@Composable
private fun CredentialSelector(
    title: String,
    selectedId: UUID?,
    credentials: List<ai.routin.mytoken.domain.model.Credential>,
    onSelect: (ai.routin.mytoken.domain.model.Credential) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        if (credentials.isEmpty()) {
            Text(
                text = "还没有可用凭证。先打开 MyToken 添加凭证，再重新添加小组件。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(credentials, key = { it.id }) { credential ->
                    val selected = credential.id == selectedId
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(
                                if (selected) {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                } else {
                                    MaterialTheme.colorScheme.surface
                                },
                            )
                            .clickable { onSelect(credential) }
                            .padding(horizontal = 14.dp, vertical = 13.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = credential.name,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                            )
                            Text(
                                text = ProviderCatalog.displayName(credential.providerId),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (selected) {
                            Text(
                                text = "已选",
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.labelLarge,
                            )
                        }
                    }
                }
            }
        }
    }
}
