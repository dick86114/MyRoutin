package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.onNodeWithTag
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class CredentialListScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: FakeCredentialRepository
    private lateinit var orderStore: FakeCredentialOrderStore
    private lateinit var viewModel: CredentialListViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = FakeCredentialRepository()
        orderStore = FakeCredentialOrderStore()
        viewModel = CredentialListViewModel(repository, orderStore)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun advanceVm() {
        dispatcher.scheduler.advanceUntilIdle()
    }

    /** Polls [condition] while pumping both the VM scheduler and the Compose clock. */
    private fun waitUntilVm(timeoutMillis: Long = 5_000, condition: () -> Boolean) {
        composeRule.waitUntil(timeoutMillis) {
            advanceVm()
            composeRule.waitForIdle()
            condition()
        }
    }

    private fun credential(id: String, name: String, provider: ProviderId = ProviderId.Routin) =
        Credential(
            id = UUID.fromString(id.padStart(8, '0') + "-0000-0000-0000-000000000000"),
            providerId = provider,
            credentialKind = CredentialKind.BearerApiKey,
            name = name,
        )

    private fun setContent() {
        composeRule.setContent {
            MaterialTheme {
                val state by viewModel.state.collectAsState()
                CredentialListScreen(
                    state = state,
                    onSearchQueryChange = viewModel::setSearchQuery,
                    onToggleEnabled = viewModel::toggleEnabled,
                    onTogglePinned = viewModel::setPinned,
                    onMoveWithinGroup = viewModel::moveWithinGroup,
                    onEditCredential = {},
                    onRequestDelete = viewModel::requestDelete,
                    onDismissDelete = viewModel::dismissDelete,
                    onConfirmDelete = viewModel::confirmDelete,
                    onImportFromMac = {},
                    onAddManually = {},
                )
            }
        }
        advanceVm()
        composeRule.waitForIdle()
    }

    @Test
    fun rendersProviderGroupedRows() {
        repository.credentials.value = listOf(
            credential("00000001", "主力 Key"),
            credential("00000002", "备用 Key", provider = ProviderId.DeepSeek),
        )
        advanceVm()
        setContent()

        composeRule.onNodeWithText("Routin").assertIsDisplayed()
        composeRule.onNodeWithText("主力 Key").assertIsDisplayed()
        composeRule.onNodeWithText("DeepSeek").performScrollTo()
        composeRule.onNodeWithText("备用 Key").performScrollTo()
    }

    @Test
    fun searchBoxFiltersRenderedRows() {
        repository.credentials.value = listOf(
            credential("00000001", "主力 Key"),
            credential("00000002", "备用 Key"),
        )
        advanceVm()
        setContent()

        composeRule.onNodeWithTag("credential_search").performTextReplacement("备用")
        waitUntilVm { viewModel.state.value.credentialCount == 1 }

        composeRule.onNodeWithText("备用 Key").assertIsDisplayed()
    }

    @Test
    fun enableSwitchShowsStateAndToggles() {
        val key = credential("00000001", "主力 Key")
        repository.credentials.value = listOf(key)
        repository.secrets.value = mapOf(key.id to CredentialSecret.BearerToken("plan-secret-8F2A"))
        advanceVm()
        setContent()

        composeRule.onNodeWithContentDescription("启用 主力 Key").assertIsOn()
        composeRule.onNodeWithContentDescription("启用 主力 Key").performClick()
        waitUntilVm { !repository.credentials.value.single().isEnabled }

        assertTrue(repository.savedSecrets.value.containsKey(key.id))
        assertEquals(
            CredentialSecret.BearerToken("plan-secret-8F2A"),
            repository.secrets.value[key.id],
        )
    }

    @Test
    fun deleteShowsConfirmationDialogWithLocalOnlyScopeAndDeletesOnConfirm() {
        val key = credential("00000001", "主力 Key")
        repository.credentials.value = listOf(key)
        advanceVm()
        setContent()

        composeRule.onNodeWithContentDescription("删除 主力 Key").performClick()
        waitUntilVm { viewModel.state.value.pendingDeletion != null }
        composeRule.onNodeWithText("删除凭证").assertIsDisplayed()
        composeRule.onNodeWithText("只删除本机数据，不影响供应商账户", substring = true).assertIsDisplayed()

        composeRule.onNodeWithText("删除").performClick()
        waitUntilVm { repository.deletedIds.value.isNotEmpty() }
        assertEquals(listOf(key.id), repository.deletedIds.value)
    }

    @Test
    fun deleteCancelKeepsCredential() {
        val key = credential("00000001", "主力 Key")
        repository.credentials.value = listOf(key)
        advanceVm()
        setContent()

        composeRule.onNodeWithContentDescription("删除 主力 Key").performClick()
        waitUntilVm { viewModel.state.value.pendingDeletion != null }
        composeRule.onNodeWithText("取消").performClick()
        waitUntilVm { viewModel.state.value.pendingDeletion == null }

        assertNull(viewModel.state.value.pendingDeletion)
        assertTrue(repository.deletedIds.value.isEmpty())
    }

    @Test
    fun emptyStateShowsImportAndManualAddEntries() {
        setContent()

        composeRule.onNodeWithText("尚未添加凭证").assertIsDisplayed()
        composeRule.onNodeWithText("从 Mac 导入").assertIsDisplayed()
        composeRule.onNodeWithText("手动添加").assertIsDisplayed()
    }
}
