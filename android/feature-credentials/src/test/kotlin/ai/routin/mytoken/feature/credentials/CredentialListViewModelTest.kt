package ai.routin.mytoken.feature.credentials

import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.ProviderId
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
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CredentialListViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private lateinit var repository: FakeCredentialRepository
    private lateinit var orderStore: FakeCredentialOrderStore

    @Before fun setUp() { Dispatchers.setMain(dispatcher); repository = FakeCredentialRepository(); orderStore = FakeCredentialOrderStore() }
    @After fun tearDown() { Dispatchers.resetMain() }

    private fun credential(id: String, name: String) = Credential(
        id = UUID.randomUUID(),
        providerId = ProviderId.Routin,
        credentialKind = CredentialKind.BearerApiKey,
        name = name,
    )

    @Test
    fun globalMovePersistsOrder() = runTest(dispatcher) {
        val a = credential("1", "A"); val b = credential("2", "B")
        repository.credentials.value = listOf(a, b)
        val vm = CredentialListViewModel(repository, orderStore)
        advanceUntilIdle()
        vm.move(0, 1); advanceUntilIdle()
        assertEquals(listOf("B", "A"), vm.state.value.items.map { it.name })
        assertEquals(1, orderStore.savedOrders)
    }
}
