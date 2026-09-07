package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
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
class CredentialListViewModelTest {

    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: FakeCredentialRepository
    private lateinit var orderStore: FakeCredentialOrderStore

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = FakeCredentialRepository()
        orderStore = FakeCredentialOrderStore()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun credential(
        id: String,
        name: String,
        provider: ProviderId = ProviderId.Routin,
        enabled: Boolean = true,
    ) = Credential(
        id = UUID.fromString(id.padStart(8, '0') + "-0000-0000-0000-000000000000"),
        providerId = provider,
        credentialKind = if (provider == ProviderId.Volcengine) CredentialKind.AccessKeyPair else CredentialKind.BearerApiKey,
        name = name,
        isEnabled = enabled,
        sortOrder = 0,
    )

    private fun viewModel() = CredentialListViewModel(repository, orderStore)

    private fun rows(state: CredentialListUiState, provider: ProviderId): List<String> =
        state.groups.first { it.providerId == provider }.rows.map { it.credential.name }

    @Test
    fun groupsCredentialsByProviderInRepositoryOrder() = runTest(dispatcher) {
        val a = credential("00000001", "A 主力")
        val b = credential("00000002", "B 备用", provider = ProviderId.DeepSeek)
        repository.credentials.value = listOf(a, b)
        val vm = viewModel()
        advanceUntilIdle()

        val state = vm.state.value
        assertFalse(state.isLoading)
        assertEquals(2, state.credentialCount)
        assertEquals(listOf(ProviderId.Routin, ProviderId.DeepSeek), state.groups.map { it.providerId })
        assertEquals(listOf("A 主力"), rows(state, ProviderId.Routin))
        assertEquals(listOf("B 备用"), rows(state, ProviderId.DeepSeek))
    }

    @Test
    fun searchFiltersRowsByNameAcrossGroups() = runTest(dispatcher) {
        repository.credentials.value = listOf(
            credential("00000001", "主力账号"),
            credential("00000002", "备用账号"),
        )
        val vm = viewModel()
        advanceUntilIdle()

        vm.setSearchQuery("备用")
        advanceUntilIdle()

        assertEquals("备用", vm.state.value.searchQuery)
        assertEquals(1, vm.state.value.credentialCount)
        assertEquals(listOf("备用账号"), rows(vm.state.value, ProviderId.Routin))

        vm.setSearchQuery("不存在")
        advanceUntilIdle()
        assertTrue(vm.state.value.groups.isEmpty())
    }

    @Test
    fun toggleEnabledSavesCredentialWithFlippedStateKeepingSecret() = runTest(dispatcher) {
        val a = credential("00000001", "A 主力")
        repository.credentials.value = listOf(a)
        repository.secrets.value = mapOf(a.id to CredentialSecret.BearerToken("plan-secret-8F2A"))
        val vm = viewModel()
        advanceUntilIdle()

        vm.toggleEnabled(a)
        advanceUntilIdle()

        val saved = repository.credentials.value.single()
        assertFalse(saved.isEnabled)
        assertEquals(
            CredentialSecret.BearerToken("plan-secret-8F2A"),
            repository.secrets.value[saved.id],
        )
    }

    @Test
    fun toggleEnabledWithoutSecretShowsErrorInsteadOfSaving() = runTest(dispatcher) {
        val a = credential("00000001", "A 主力")
        repository.credentials.value = listOf(a)
        val vm = viewModel()
        advanceUntilIdle()

        vm.toggleEnabled(a)
        advanceUntilIdle()

        assertEquals("凭证密钥缺失，无法修改启用状态", vm.state.value.errorMessage)
        assertTrue(repository.credentials.value.single().isEnabled)
    }

    @Test
    fun deleteRequiresConfirmationAndRemovesCredential() = runTest(dispatcher) {
        val a = credential("00000001", "A 主力")
        repository.credentials.value = listOf(a)
        val vm = viewModel()
        advanceUntilIdle()

        vm.requestDelete(a)
        advanceUntilIdle()
        assertEquals(a, vm.state.value.pendingDeletion)

        vm.confirmDelete()
        advanceUntilIdle()

        assertEquals(listOf(a.id), repository.deletedIds.value)
        assertNull(vm.state.value.pendingDeletion)
        assertTrue(vm.state.value.groups.isEmpty())
    }

    @Test
    fun dismissDeleteKeepsCredential() = runTest(dispatcher) {
        val a = credential("00000001", "A 主力")
        repository.credentials.value = listOf(a)
        val vm = viewModel()
        advanceUntilIdle()

        vm.requestDelete(a)
        vm.dismissDelete()
        advanceUntilIdle()

        assertNull(vm.state.value.pendingDeletion)
        assertTrue(repository.deletedIds.value.isEmpty())
    }

    @Test
    fun moveWithinGroupPersistsNewOrderIndependently() = runTest(dispatcher) {
        val a = credential("00000001", "A")
        val b = credential("00000002", "B")
        val c = credential("00000003", "C")
        repository.credentials.value = listOf(a, b, c)
        val vm = viewModel()
        advanceUntilIdle()

        vm.moveWithinGroup(ProviderId.Routin, fromRow = 0, toRow = 2)
        advanceUntilIdle()

        assertEquals(1, orderStore.savedOrders)
        val persisted = orderStore.orderState.value
        assertEquals(listOf(b.id, c.id, a.id).map { it.toString() }, persisted)
        assertEquals(listOf("B", "C", "A"), rows(vm.state.value, ProviderId.Routin))
    }

    @Test
    fun persistedOrderSurvivesReloadAndAppliesAcrossGroups() = runTest(dispatcher) {
        val a = credential("00000001", "A")
        val b = credential("00000002", "B", provider = ProviderId.DeepSeek)
        repository.credentials.value = listOf(a, b)
        orderStore.orderState.value = listOf(b.id.toString(), a.id.toString())
        val vm = viewModel()
        advanceUntilIdle()

        // Group order follows the first appearance in the persisted order.
        assertEquals(listOf(ProviderId.DeepSeek, ProviderId.Routin), vm.state.value.groups.map { it.providerId })
        assertEquals(listOf("B"), rows(vm.state.value, ProviderId.DeepSeek))
        assertEquals(listOf("A"), rows(vm.state.value, ProviderId.Routin))
    }

    @Test
    fun pinnedCredentialFloatsToTopOfItsGroup() = runTest(dispatcher) {
        val a = credential("00000001", "A")
        val b = credential("00000002", "B")
        repository.credentials.value = listOf(a, b)
        orderStore.pinnedState.value = setOf(b.id.toString())
        val vm = viewModel()
        advanceUntilIdle()

        val groupRows = vm.state.value.groups.single().rows
        assertEquals(listOf("B", "A"), groupRows.map { it.credential.name })
        assertTrue(groupRows.first().isPinned)
        assertFalse(groupRows.last().isPinned)
    }

    @Test
    fun moveWithinGroupDuringSearchPersistsFullOrderKeepingHiddenCredentialsRelativeOrder() =
        runTest(dispatcher) {
            val a = credential("00000001", "Alpha 主力")
            val b = credential("00000002", "Beta 备用")
            val c = credential("00000003", "Gamma 主力")
            repository.credentials.value = listOf(a, b, c)
            val vm = viewModel()
            advanceUntilIdle()

            vm.setSearchQuery("备用")
            advanceUntilIdle()
            assertEquals(listOf("Beta 备用"), rows(vm.state.value, ProviderId.Routin))

            // Drag the single visible row one position down within the FULL group
            // (fromRow=0 → toRow=1 swaps the first two entries of the full group).
            vm.moveWithinGroup(ProviderId.Routin, fromRow = 0, toRow = 1)
            advanceUntilIdle()

            val persisted = orderStore.orderState.value
            // The persisted list is a permutation of ALL credentials, not just the
            // visible ones: hidden credentials keep their original relative order.
            assertEquals(listOf(b.id, a.id, c.id).map { it.toString() }, persisted)

            vm.setSearchQuery("")
            advanceUntilIdle()
            assertEquals(listOf("Beta 备用", "Alpha 主力", "Gamma 主力"), rows(vm.state.value, ProviderId.Routin))
        }

    @Test
    fun invalidMoveIndicesAreIgnored() = runTest(dispatcher) {        val a = credential("00000001", "A")
        val b = credential("00000002", "B")
        repository.credentials.value = listOf(a, b)
        val vm = viewModel()
        advanceUntilIdle()

        vm.moveWithinGroup(ProviderId.Routin, fromRow = 0, toRow = 5)
        advanceUntilIdle()

        assertEquals(0, orderStore.savedOrders)
        assertEquals(listOf("A", "B"), rows(vm.state.value, ProviderId.Routin))
    }

    @Test
    fun orderEntriesForDeletedCredentialsAreDropped() = runTest(dispatcher) {
        val a = credential("00000001", "A")
        val b = credential("00000002", "B")
        repository.credentials.value = listOf(a, b)
        orderStore.orderState.value = listOf(b.id.toString(), a.id.toString())
        val vm = viewModel()
        advanceUntilIdle()

        vm.requestDelete(b)
        vm.confirmDelete()
        advanceUntilIdle()

        assertEquals(listOf(a.id.toString()), orderStore.orderState.value)
    }
}
