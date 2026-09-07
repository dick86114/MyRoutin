package ai.routin.mytoken

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.feature.credentials.CredentialEditorScreen
import ai.routin.mytoken.feature.credentials.CredentialEditorViewModel
import ai.routin.mytoken.feature.credentials.CredentialListScreen
import ai.routin.mytoken.feature.credentials.CredentialListViewModel
import ai.routin.mytoken.feature.credentials.RoutinCheckInLauncher
import ai.routin.mytoken.feature.home.HomeScreen
import ai.routin.mytoken.feature.home.HomeViewModel
import ai.routin.mytoken.feature.home.CredentialDetailScreen
import ai.routin.mytoken.feature.settings.CardDensity
import ai.routin.mytoken.feature.settings.SettingsScreen
import ai.routin.mytoken.feature.settings.SettingsViewModel
import ai.routin.mytoken.feature.transfer.ImportConflictMode
import ai.routin.mytoken.feature.transfer.TransferCompletedScreen
import ai.routin.mytoken.feature.transfer.TransferPreviewScreen
import ai.routin.mytoken.feature.transfer.TransferScannerScreen
import ai.routin.mytoken.feature.transfer.TransferUiState
import ai.routin.mytoken.feature.transfer.TransferViewModel
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import java.util.UUID
import kotlinx.coroutines.launch

/** Lightweight screen stack; Task 11 owns the full navigation layer. */
sealed interface AppScreen {
    data object Home : AppScreen
    data object Credentials : AppScreen
    data object Settings : AppScreen
    data class Detail(val credentialId: UUID) : AppScreen
    data class Editor(val credentialId: UUID?) : AppScreen
    data object Transfer : AppScreen
}

/**
 * Composes the bottom navigation (首页 / 凭证 / 设置) and wires the home detail
 * edit/delete placeholders to the credential editor and delete-confirmation flows.
 */
@Composable
fun MyTokenApp(
    graph: AppGraph,
    appVersion: String,
    notificationPermissionGranted: Boolean = true,
    onRequestNotificationPermission: () -> Unit = {},
) {
    var screen by remember { mutableStateOf<AppScreen>(AppScreen.Home) }
    val backStack = remember { mutableStateListOf<AppScreen>() }
    val scope = rememberCoroutineScope()

    fun navigate(target: AppScreen) {
        backStack.add(screen)
        screen = target
    }

    fun goBack() {
        screen = backStack.removeLastOrNull() ?: AppScreen.Home
    }

    BackHandler(enabled = backStack.isNotEmpty()) { goBack() }

    // nowTickIntervalMillis = null: the 30s freshness ticker keeps the main looper
    // permanently busy, which deadlocks Compose test idle detection (Task 11 will
    // wire a lifecycle-aware ticker instead of an unconditional ViewModel loop).
    val homeViewModel = remember {
        HomeViewModel(
            repository = graph.credentialRepository,
            refreshUseCase = graph.refreshUseCase,
            nowTickIntervalMillis = null,
        )
    }
    val credentialListViewModel = remember {
        CredentialListViewModel(graph.credentialRepository, graph.credentialOrderStore)
    }
    val settingsViewModel = remember {
        SettingsViewModel(graph.refreshSettingsStore, graph.displaySettingsStore, graph.notificationSettingsStore)
    }

    Scaffold(
        bottomBar = {
            if (screen is AppScreen.Home || screen is AppScreen.Credentials || screen is AppScreen.Settings) {
                NavigationBar {
                    NavigationBarItem(
                        selected = screen is AppScreen.Home,
                        onClick = { screen = AppScreen.Home },
                        icon = { Icon(imageVector = Icons.Filled.Home, contentDescription = null) },
                        label = { Text(text = "首页") },
                    )
                    NavigationBarItem(
                        selected = screen is AppScreen.Credentials,
                        onClick = { screen = AppScreen.Credentials },
                        icon = { Icon(imageVector = Icons.Filled.List, contentDescription = null) },
                        label = { Text(text = "凭证") },
                    )
                    NavigationBarItem(
                        selected = screen is AppScreen.Settings,
                        onClick = { screen = AppScreen.Settings },
                        icon = { Icon(imageVector = Icons.Filled.Settings, contentDescription = null) },
                        label = { Text(text = "设置") },
                    )
                }
            }
        },
    ) { padding ->
        Box(modifier = Modifier
            .padding(padding)
            .fillMaxSize()) {
            when (val current = screen) {
                AppScreen.Home -> {
                    val homeState by homeViewModel.state.collectAsState()
                    HomeScreen(
                        state = homeState,
                        onRefreshAll = homeViewModel::refreshAll,
                        onRefreshCredential = { id ->
                            homeState.groups.flatMap { it.cards }
                                .firstOrNull { it.credential.id == id }
                                ?.let { homeViewModel.refreshCredential(it.credential) }
                        },
                        onToggleGroup = homeViewModel::toggleGroup,
                        onOpenCredential = { id -> navigate(AppScreen.Detail(id)) },
                        onImportFromMac = { navigate(AppScreen.Transfer) },
                        onAddManually = { navigate(AppScreen.Editor(null)) },
                    )
                }
                AppScreen.Credentials -> {
                    val listState by credentialListViewModel.state.collectAsState()
                    CredentialListScreen(
                        state = listState,
                        onSearchQueryChange = credentialListViewModel::setSearchQuery,
                        onToggleEnabled = credentialListViewModel::toggleEnabled,
                        onTogglePinned = credentialListViewModel::setPinned,
                        onMoveWithinGroup = credentialListViewModel::moveWithinGroup,
                        onEditCredential = { id -> navigate(AppScreen.Editor(id)) },
                        onRequestDelete = credentialListViewModel::requestDelete,
                        onDismissDelete = credentialListViewModel::dismissDelete,
                        onConfirmDelete = credentialListViewModel::confirmDelete,
                        onImportFromMac = { navigate(AppScreen.Transfer) },
                        onAddManually = { navigate(AppScreen.Editor(null)) },
                    )
                }
                AppScreen.Settings -> {
                    val settingsState by settingsViewModel.state.collectAsState()
                    SettingsScreen(
                        state = settingsState,
                        appVersion = appVersion,
                        onBack = { goBack() },
                        onAutoRefreshChange = settingsViewModel::setAutoRefreshEnabled,
                        onIntervalChange = settingsViewModel::setRefreshIntervalMinutes,
                        onWifiOnlyChange = settingsViewModel::setWifiOnly,
                        onOpenAppRefreshChange = settingsViewModel::setOpenAppRefresh,
                        onRetryOnFailureChange = settingsViewModel::setRetryOnFailure,
                        onCardDensityChange = settingsViewModel::setCardDensity,
                        onShowDisabledCredentialsChange = settingsViewModel::setShowDisabledCredentials,
                        onDefaultExpandGroupsChange = settingsViewModel::setDefaultExpandGroups,
                        onShowUsageProgressChange = settingsViewModel::setShowUsageProgress,
                        onShowBalanceChange = settingsViewModel::setShowBalance,
                        onShowResetTimeChange = settingsViewModel::setShowResetTime,
                        onOpenTransfer = { navigate(AppScreen.Transfer) },
                        onNotificationsEnabledChange = settingsViewModel::setNotificationsEnabled,
                        onCredentialFailureAlertsChange = settingsViewModel::setCredentialFailureAlertsEnabled,
                        onLowThresholdChange = settingsViewModel::setLowAlertThreshold,
                        onHighThresholdChange = settingsViewModel::setHighAlertThreshold,
                        notificationPermissionGranted = notificationPermissionGranted,
                        onRequestNotificationPermission = onRequestNotificationPermission,
                    )
                }
                is AppScreen.Detail -> {
                    val homeState by homeViewModel.state.collectAsState()
                    val card = homeState.groups
                        .flatMap { it.cards }
                        .firstOrNull { it.credential.id == current.credentialId }
                    var deletionTarget by remember(current.credentialId) {
                        mutableStateOf<Credential?>(null)
                    }
                    // Routin credentials get a check-in entry that opens the official
                    // page in a Custom Tab (no DOM/cookie/password access, no logging).
                    val context = LocalContext.current
                    val onCheckIn = card?.credential
                        ?.takeIf { it.providerId == ProviderId.Routin }
                        ?.let { credential ->
                            {
                                RoutinCheckInLauncher.launch(context, credential)
                                Unit
                            }
                        }
                    CredentialDetailScreen(
                        card = card,
                        onBack = { goBack() },
                        onRefresh = { card?.let { homeViewModel.refreshCredential(it.credential) } },
                        onEdit = { navigate(AppScreen.Editor(current.credentialId)) },
                        onDelete = { deletionTarget = card?.credential },
                        onCheckIn = onCheckIn,
                    )
                    deletionTarget?.let { target ->
                        AlertDialog(
                            onDismissRequest = { deletionTarget = null },
                            title = { Text(text = "删除凭证") },
                            text = {
                                Text(text = "确定删除「${target.name}」吗？只删除本机数据，不影响供应商账户。")
                            },
                            confirmButton = {
                                TextButton(onClick = {
                                    deletionTarget = null
                                    scope.launch {
                                        runCatching { graph.credentialRepository.delete(target.id) }
                                        homeViewModel.refreshAll()
                                        screen = AppScreen.Home
                                        backStack.clear()
                                    }
                                }) {
                                    Text(text = "删除", color = MaterialTheme.colorScheme.error)
                                }
                            },
                            dismissButton = {
                                TextButton(onClick = { deletionTarget = null }) {
                                    Text(text = "取消")
                                }
                            },
                        )
                    }
                }
                is AppScreen.Editor -> {
                    val editorViewModel = remember(current.credentialId) {
                        CredentialEditorViewModel(
                            repository = graph.credentialRepository,
                            providers = graph.providers,
                            credentialId = current.credentialId,
                        )
                    }
                    val editorState by editorViewModel.state.collectAsState()
                    CredentialEditorScreen(
                        state = editorState,
                        onBack = { goBack() },
                        onProviderChange = editorViewModel::setProviderId,
                        onNameChange = editorViewModel::setName,
                        onApiKeyChange = editorViewModel::setApiKey,
                        onAccessKeyIDChange = editorViewModel::setAccessKeyID,
                        onSecretAccessKeyChange = editorViewModel::setSecretAccessKey,
                        onRegionChange = editorViewModel::setRegion,
                        onBaseURLChange = editorViewModel::setBaseURL,
                        onUserIDChange = editorViewModel::setUserID,
                        onWebsiteURLChange = editorViewModel::setWebsiteURL,
                        onToggleSecretVisible = editorViewModel::toggleSecretVisible,
                        onTestConnection = editorViewModel::testConnection,
                        onSave = editorViewModel::save,
                    )
                    if (editorState.saveCompleted) {
                        LaunchedEffect(editorState.saveCompleted) { goBack() }
                    }
                }
                AppScreen.Transfer -> {
                    val transferViewModel = remember {
                        TransferViewModel(graph.transferRepository)
                    }
                    val transferState by transferViewModel.state.collectAsState()
                    when (val state = transferState) {
                        is TransferUiState.Idle -> TransferScannerScreen(
                            isActive = true,
                            onQrCodeScanned = transferViewModel::onQrCodeScanned,
                            onCancel = { goBack() },
                        )
                        is TransferUiState.Connecting, is TransferUiState.Importing -> Column(
                            modifier = Modifier.fillMaxSize(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            CircularProgressIndicator()
                            Text(text = if (state is TransferUiState.Connecting) "连接中…" else "导入中…")
                        }
                        is TransferUiState.PreviewReady -> TransferPreviewScreen(
                            state = state,
                            onConfirm = { mode: ImportConflictMode -> transferViewModel.confirmImport(mode) },
                            onCancel = transferViewModel::cancel,
                        )
                        is TransferUiState.Completed -> TransferCompletedScreen(
                            summary = state.summary,
                            onDone = { goBack() },
                        )
                        is TransferUiState.Failed -> Column(
                            modifier = Modifier.fillMaxSize(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(text = state.message, color = MaterialTheme.colorScheme.error)
                            TextButton(onClick = transferViewModel::cancel) {
                                Text(text = "返回")
                            }
                        }
                    }
                }
            }
        }
    }
}
