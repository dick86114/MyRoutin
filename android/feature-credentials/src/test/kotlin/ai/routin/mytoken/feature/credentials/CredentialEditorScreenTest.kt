package ai.routin.mytoken.feature.credentials

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1100dp")
class CredentialEditorScreenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: StaticCredentialRepository
    private lateinit var providers: Map<ai.routin.mytoken.domain.model.ProviderId, ai.routin.mytoken.domain.usage.UsageProvider>
    private lateinit var viewModel: CredentialEditorViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = StaticCredentialRepository()
        providers = mapOf(
            ai.routin.mytoken.domain.model.ProviderId.Routin to
                FakeUsageProvider(ai.routin.mytoken.domain.model.ProviderId.Routin),
        )
        viewModel = CredentialEditorViewModel(repository, providers, credentialId = null)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    /** Polls [condition] while pumping the VM's test-scheduler and the Compose clock. */
    private fun waitUntilVm(timeoutMillis: Long = 5_000, condition: () -> Boolean) {
        composeRule.waitUntil(timeoutMillis) {
            dispatcher.scheduler.advanceUntilIdle()
            composeRule.waitForIdle()
            condition()
        }
    }

    private fun setContent() {
        composeRule.setContent {
            MaterialTheme {
                val state by viewModel.state.collectAsState()
                CredentialEditorScreen(
                    state = state,
                    onBack = {},
                    onProviderChange = viewModel::setProviderId,
                    onNameChange = viewModel::setName,
                    onApiKeyChange = viewModel::setApiKey,
                    onAccessKeyIDChange = viewModel::setAccessKeyID,
                    onSecretAccessKeyChange = viewModel::setSecretAccessKey,
                    onRegionChange = viewModel::setRegion,
                    onBaseURLChange = viewModel::setBaseURL,
                    onUserIDChange = viewModel::setUserID,
                    onWebsiteURLChange = viewModel::setWebsiteURL,
                    onToggleSecretVisible = viewModel::toggleSecretVisible,
                    onTestConnection = viewModel::testConnection,
                    onSave = viewModel::save,
                )
            }
        }
        dispatcher.scheduler.advanceUntilIdle()
        composeRule.waitForIdle()
    }

    @Test
    fun newEditorShowsProviderChipsAndBearerField() {
        setContent()

        composeRule.onNodeWithText("新增凭证").assertIsDisplayed()
        composeRule.onNodeWithText("Routin").assertIsDisplayed()
        composeRule.onNodeWithText("火山方舟").assertIsDisplayed()
        composeRule.onNodeWithText("名称").assertIsDisplayed()
        composeRule.onNodeWithText("API Key（Bearer Token）", substring = true).assertIsDisplayed()
        composeRule.onNodeWithText("测试连接").assertIsDisplayed()
        composeRule.onNodeWithText("保存").assertIsDisplayed()
    }

    @Test
    fun switchingToVolcengineShowsAccessKeyPairFields() {
        setContent()

        composeRule.onNodeWithText("火山方舟").performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Access Key ID").assertIsDisplayed()
        composeRule.onNodeWithText("Secret Access Key").assertIsDisplayed()
        composeRule.onNodeWithText("区域（默认 cn-beijing）").assertIsDisplayed()
    }

    @Test
    fun savingInvalidFormShowsChineseValidationErrorAndKeepsInput() {
        setContent()

        composeRule.onNodeWithTag("editor_name").performTextInput("主账号")
        composeRule.onNodeWithTag("editor_api_key").performTextInput("sk-invalid")
        composeRule.onNodeWithText("保存").performClick()
        waitUntilVm { viewModel.state.value.validationError != null }
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Key 必须以 plan- 开头").assertIsDisplayed()
        assertFalse(viewModel.state.value.saveCompleted)
        assertTrue(repository.saved.value.isEmpty())
    }

    @Test
    fun secretFieldIsMaskedByDefaultAndVisibilityToggleSwitchesIcon() {
        setContent()

        composeRule.onNodeWithContentDescription("显示密钥").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("显示密钥").performClick()
        composeRule.waitForIdle()

        assertTrue(viewModel.state.value.isSecretVisible)
        composeRule.onNodeWithContentDescription("隐藏密钥").assertIsDisplayed()
    }

    @Test
    fun successfulSaveMarksCompleted() {
        setContent()

        composeRule.onNodeWithTag("editor_name").performTextInput("主账号")
        composeRule.onNodeWithTag("editor_api_key").performTextInput("plan-main-8F2A")
        composeRule.onNodeWithText("保存").performClick()
        waitUntilVm { viewModel.state.value.saveCompleted }
        composeRule.waitForIdle()

        assertTrue(viewModel.state.value.saveCompleted)
        assertEquals("主账号", repository.saved.value.single().first.name)
    }

    @Test
    fun failedConnectionTestDisplaysFailureAndSaveStillPossible() {
        val provider = providers.values.single() as FakeUsageProvider
        provider.enqueue(
            Result.failure(
                ai.routin.mytoken.domain.usage.UsageProviderException.Unauthorized(),
            ),
        )
        setContent()

        composeRule.onNodeWithTag("editor_name").performTextInput("主账号")
        composeRule.onNodeWithTag("editor_api_key").performTextInput("plan-main-8F2A")
        composeRule.onNodeWithText("测试连接").performClick()
        waitUntilVm { viewModel.state.value.testResultMessage != null }
        composeRule.waitForIdle()

        composeRule.onNodeWithText("凭证无效或没有该供应商权限", substring = true).performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("测试失败仍可保存，失败原因不会丢失已填内容", substring = true).performScrollTo().assertIsDisplayed()

        composeRule.onNodeWithText("保存").performClick()
        waitUntilVm { viewModel.state.value.saveCompleted }
        assertTrue(viewModel.state.value.saveCompleted)
        assertEquals(1, repository.saved.value.size)
    }

    @Test
    fun connectionSuccessShowsSuccessMessage() {
        val provider = providers.values.single() as FakeUsageProvider
        provider.enqueue(
            Result.success(
                ai.routin.mytoken.domain.model.UsageSnapshot(
                    credentialId = java.util.UUID.randomUUID(),
                    fetchedAt = java.time.Instant.parse("2026-09-07T12:00:00Z"),
                    metrics = emptyList(),
                ),
            ),
        )
        setContent()

        composeRule.onNodeWithTag("editor_name").performTextInput("主账号")
        composeRule.onNodeWithTag("editor_api_key").performTextInput("plan-main-8F2A")
        composeRule.onNodeWithText("测试连接").performClick()
        waitUntilVm { viewModel.state.value.testResultMessage != null }
        composeRule.waitForIdle()

        composeRule.onNodeWithText("✓ 连接成功").assertIsDisplayed()
    }
}
