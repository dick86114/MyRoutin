package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.usage.UsageProvider
import ai.routin.mytoken.domain.usage.UsageProviderException
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CredentialEditorViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: StaticCredentialRepository
    private lateinit var routinProvider: FakeUsageProvider
    private lateinit var providers: MutableMap<ProviderId, UsageProvider>

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = StaticCredentialRepository()
        routinProvider = FakeUsageProvider(ProviderId.Routin)
        providers = mutableMapOf(ProviderId.Routin to routinProvider)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun existingCredential(
        provider: ProviderId = ProviderId.Routin,
        kind: CredentialKind = CredentialKind.BearerApiKey,
        secret: CredentialSecret = CredentialSecret.BearerToken("plan-existing-8F2A"),
    ): Credential {
        val credential = Credential(
            id = UUID.randomUUID(),
            providerId = provider,
            credentialKind = kind,
            name = "已有 Key",
            isEnabled = false,
            sortOrder = 3,
            metadata = mapOf(CredentialMetadataKey.PlanType to "agent"),
        )
        repository = StaticCredentialRepository(listOf(credential), mapOf(credential.id to secret))
        return credential
    }

    private fun newViewModel(providers: Map<ProviderId, UsageProvider> = this.providers) =
        CredentialEditorViewModel(repository = repository, providers = providers, credentialId = null)

    @Test
    fun newEditorDefaultsToRoutinAndNotSaving() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()

        val state = vm.state.value
        assertTrue(state.isNew)
        assertFalse(state.isLoading)
        assertEquals(ProviderId.Routin, state.providerId)
        assertEquals(CredentialKind.BearerApiKey, state.credentialKind)
        assertFalse(state.isSecretVisible)
    }

    @Test
    fun saveFailsValidationAndPreservesForm() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()

        vm.setName("主账号")
        vm.setApiKey("sk-invalid")
        vm.save()
        advanceUntilIdle()

        val state = vm.state.value
        assertEquals("Key 必须以 plan- 开头", state.validationError)
        assertFalse(state.saveCompleted)
        assertEquals("主账号", state.name)
        assertEquals("sk-invalid", state.apiKey)
        assertTrue(repository.saved.value.isEmpty())
    }

    @Test
    fun saveSucceedsForValidNewRoutinCredentialWithNextSortOrder() = runTest(dispatcher) {
        val existing = Credential(
            id = UUID.randomUUID(),
            providerId = ProviderId.DeepSeek,
            credentialKind = CredentialKind.ApiKey,
            name = "DS",
            sortOrder = 7,
        )
        repository = StaticCredentialRepository(listOf(existing))
        val vm = newViewModel()
        advanceUntilIdle()

        vm.setName("主账号")
        vm.setApiKey("plan-main-8F2A")
        vm.save()
        advanceUntilIdle()

        val state = vm.state.value
        assertNull(state.validationError)
        assertTrue(state.saveCompleted)

        val saved = repository.saved.value.single()
        assertEquals("主账号", saved.first.name)
        assertEquals(CredentialKind.BearerApiKey, saved.first.credentialKind)
        assertEquals(8, saved.first.sortOrder)
        assertTrue(saved.first.isEnabled)
        assertEquals("plan-main-8F2A", (saved.second as CredentialSecret.BearerToken).token)
    }

    @Test
    fun editLoadsExistingCredentialAndPreservesIdEnabledAndSortOrder() = runTest(dispatcher) {
        val existing = existingCredential()
        val vm = CredentialEditorViewModel(
            repository = repository,
            providers = providers,
            credentialId = existing.id,
        )
        advanceUntilIdle()

        val state = vm.state.value
        assertFalse(state.isNew)
        assertEquals("已有 Key", state.name)
        assertEquals("plan-existing-8F2A", state.apiKey)

        vm.setName("改名")
        vm.save()
        advanceUntilIdle()

        val saved = repository.saved.value.single()
        assertEquals(existing.id, saved.first.id)
        assertFalse(saved.first.isEnabled)
        assertEquals(3, saved.first.sortOrder)
        assertEquals("改名", saved.first.name)
        assertEquals("plan-existing-8F2A", (saved.second as CredentialSecret.BearerToken).token)
    }

    @Test
    fun secretIsMaskedByDefaultAndToggleReveals() = runTest(dispatcher) {
        existingCredential()
        val vm = CredentialEditorViewModel(
            repository = repository,
            providers = providers,
            credentialId = repository.credentials.value.single().id,
        )
        advanceUntilIdle()

        assertFalse(vm.state.value.isSecretVisible)
        vm.toggleSecretVisible()
        assertTrue(vm.state.value.isSecretVisible)
        vm.toggleSecretVisible()
        assertFalse(vm.state.value.isSecretVisible)
    }

    @Test
    fun testConnectionReportsSuccessFromMatchingProvider() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()
        routinProvider.enqueue(Result.success(snapshot(UUID.randomUUID())))

        vm.setName("主账号")
        vm.setApiKey("plan-main-8F2A")
        vm.testConnection()
        advanceUntilIdle()

        val state = vm.state.value
        assertTrue(state.testSucceeded!!)
        assertEquals("连接成功", state.testResultMessage)
        assertFalse(state.isTestingConnection)

        val (credential, secret) = routinProvider.requests.value.single()
        assertEquals("主账号", credential.name)
        assertEquals("plan-main-8F2A", (secret as CredentialSecret.BearerToken).token)
    }

    @Test
    fun testConnectionShowsFailureButStillAllowsSave() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()
        routinProvider.enqueue(Result.failure(UsageProviderException.Unauthorized()))

        vm.setName("主账号")
        vm.setApiKey("plan-main-8F2A")
        vm.testConnection()
        advanceUntilIdle()

        val state = vm.state.value
        assertFalse(state.testSucceeded!!)
        assertEquals("凭证无效或没有该供应商权限", state.testResultMessage)

        vm.save()
        advanceUntilIdle()
        assertTrue(vm.state.value.saveCompleted)
        assertEquals(1, repository.saved.value.size)
    }

    @Test
    fun testConnectionWithoutProviderShowsUnsupportedMessage() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()
        vm.setProviderId(ProviderId.Volcengine)
        vm.setName("方舟")
        vm.setAccessKeyID("AKTP")
        vm.setSecretAccessKey("c2VjcmV0")

        vm.testConnection()
        advanceUntilIdle()

        assertFalse(vm.state.value.testSucceeded!!)
        assertEquals("暂不支持该供应商的用量查询", vm.state.value.testResultMessage)
    }

    @Test
    fun testConnectionFailsValidationWithoutSavingAnything() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()

        vm.setName("主账号")
        vm.testConnection()
        advanceUntilIdle()

        assertFalse(vm.state.value.testSucceeded!!)
        assertEquals("请输入 plan Key", vm.state.value.testResultMessage)
        assertTrue(routinProvider.requests.value.isEmpty())
    }

    @Test
    fun switchingProviderUpdatesKindAndClearsTestResult() = runTest(dispatcher) {
        val vm = newViewModel()
        advanceUntilIdle()

        vm.setApiKey("plan-main-8F2A")
        vm.setProviderId(ProviderId.Volcengine)
        advanceUntilIdle()

        val state = vm.state.value
        assertEquals(CredentialKind.AccessKeyPair, state.credentialKind)
        assertNull(state.testResultMessage)
        assertNull(state.testSucceeded)
    }
}
