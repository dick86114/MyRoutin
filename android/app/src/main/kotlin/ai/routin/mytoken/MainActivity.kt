package ai.routin.mytoken

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/**
 * Single-activity Compose host. Renders the bottom navigation app (home dashboard,
 * credential management, settings) wired to the real repositories and providers.
 */
class MainActivity : ComponentActivity() {

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
        lifecycle.addObserver(permissionRefreshObserver)
        notificationPermissionGranted.value =
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        val graph = (application as MyTokenApplication).graph
        val appVersion = try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "0.1.0"
        } catch (_: Exception) {
            "0.1.0"
        }
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MyTokenApp(
                        graph = graph,
                        appVersion = appVersion,
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
}
