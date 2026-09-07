package ai.routin.mytoken.feature.credentials

import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Every delete path (credential list and home detail) must prune the persisted
 * order and pinned sets via [pruneCredential] so IDs of deleted credentials
 * never pile up.
 */
class CredentialOrderStorePruneTest {

    @Test
    fun pruneCredential_removesIdFromOrderAndPinned() = runTest {
        val id = UUID.randomUUID()
        val other = UUID.randomUUID()
        val store = FakeCredentialOrderStore().apply {
            orderState.value = listOf(id.toString(), other.toString(), id.toString())
            pinnedState.value = setOf(id.toString())
        }

        store.pruneCredential(id)

        assertEquals(listOf(other.toString()), store.orderState.value)
        assertEquals(emptySet<String>(), store.pinnedState.value)
    }

    @Test
    fun pruneCredential_ofUnknownId_keepsEverythingElseUntouched() = runTest {
        val known = UUID.randomUUID().toString()
        val store = FakeCredentialOrderStore().apply {
            orderState.value = listOf(known)
        }

        store.pruneCredential(UUID.randomUUID())

        assertEquals(listOf(known), store.orderState.value)
    }
}
