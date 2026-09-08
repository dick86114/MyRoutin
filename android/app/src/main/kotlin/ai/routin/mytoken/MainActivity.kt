package ai.routin.mytoken

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import ai.routin.mytoken.core.ui.MyTokenTheme
import ai.routin.mytoken.feature.settings.AppThemeMode
import ai.routin.mytoken.feature.settings.DisplaySettings
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.core.app.NotificationManagerCompat
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import java.util.UUID

/**
 * Single-activity Compose host. Renders the bottom navigation app (home dashboard,
 * credential management, settings) wired to the real repositories and providers.
 */
class MainActivity : ComponentActivity() {

    private val pendingCredentialId = mutableStateOf<UUID?>(null)

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* silent: status is visible in Settings */ }

    /** Recomputed on every ON_RESUME so returning from system settings updates the
     *  Settings page without recreating the activity. */
    private val notificationPermissionGranted: MutableState<Boolean> = mutableStateOf(true)

    private val permissionRefreshObserver = LifecycleEventObserver { _, event ->
        if (event == Lifecycle.Event.ON_RESUME) {
            notificationPermissionGranted.value =
                NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        lifecycle.addObserver(permissionRefreshObserver)
        notificationPermissionGranted.value =
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        val graph = (application as MyTokenApplication).graph
        pendingCredentialId.value = intent?.getStringExtra(EXTRA_CREDENTIAL_ID)?.let(UUID::fromString)
        val appVersion = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "0.1.0"
        } catch (_: Exception) {
            "0.1.0"
        }
        setContent {
            val displaySettings by graph.displaySettingsStore.settings
                .collectAsState(initial = DisplaySettings())
            val darkTheme = when (displaySettings.themeMode) {
                AppThemeMode.SYSTEM -> androidx.compose.foundation.isSystemInDarkTheme()
                AppThemeMode.LIGHT -> false
                AppThemeMode.DARK -> true
            }
            val view = LocalView.current
            SideEffect {
                WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
                WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
            }
            MyTokenTheme(darkTheme = darkTheme) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MyTokenApp(
                        graph = graph,
                        appVersion = appVersion,
                        openCredentialId = pendingCredentialId.value,
                        onOpenCredentialConsumed = { pendingCredentialId.value = null },
                        notificationPermissionGranted = notificationPermissionGranted.value,
                        onRequestNotificationPermission = {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingCredentialId.value = intent.getStringExtra(EXTRA_CREDENTIAL_ID)?.let(UUID::fromString)
    }

    companion object {
        const val ACTION_OPEN_CREDENTIAL = "ai.routin.mytoken.action.OPEN_CREDENTIAL"
        const val EXTRA_CREDENTIAL_ID = "credentialId"
    }
}
