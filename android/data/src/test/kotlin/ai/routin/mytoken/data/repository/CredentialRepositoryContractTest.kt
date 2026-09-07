package ai.routin.mytoken.data.repository

import ai.routin.mytoken.core.security.SecretStore
import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import ai.routin.mytoken.domain.model.UsageMetric
import ai.routin.mytoken.domain.model.UsageMetricHealthState
import ai.routin.mytoken.domain.model.UsageMetricPresentation
import ai.routin.mytoken.domain.model.UsageMetricSemantic
import ai.routin.mytoken.domain.model.UsageMetricUnit
import ai.routin.mytoken.domain.model.UsageSnapshot
import ai.routin.mytoken.data.local.CredentialDao
import ai.routin.mytoken.data.local.CredentialEntity
import ai.routin.mytoken.data.local.MyTokenDatabase
import ai.routin.mytoken.data.local.UsageSnapshotDao
import ai.routin.mytoken.data.local.UsageSnapshotEntity
import ai.routin.mytoken.data.local.UsageSnapshotJsonCodec
import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import org.mockito.Mockito
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Contract tests for the secure credential repository: observable metadata, encrypted secret
 * round-trip, and the save/delete transaction boundaries (secret failure must not leave
 * metadata residue; delete cascades to secret and snapshot cache).
 *
 * All fixture values below are synthetic test data, never real credentials.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CredentialRepositoryContractTest {

    private class FakeSecretStore : SecretStore {
        val storage = mutableMapOf<UUID, ByteArray>()
        var nextSaveError: Throwable? = null

        override suspend fun save(id: UUID, secret: ByteArray) {
            nextSaveError?.let { throw it }
            storage[id] = secret
        }

        override suspend fun read(id: UUID): ByteArray? = storage[id]

        override suspend fun delete(id: UUID) {
            storage.remove(id)
        }
    }

    private lateinit var database: MyTokenDatabase
    private lateinit var secretStore: FakeSecretStore
    private lateinit var repository: CredentialRepositoryImpl

    private val credentialId = UUID.fromString("00000000-0000-0000-0000-000000000001")

    private fun credential(
        id: UUID = credentialId,
        name: String = "test-fixture-credential",
        sortOrder: Int = 0
    ) = Credential(
        id = id,
        providerId = ProviderId.Routin,
        credentialKind = CredentialKind.BearerApiKey,
        name = name,
        isEnabled = true,
        sortOrder = sortOrder,
        metadata = mapOf(
            CredentialMetadataKey.BaseURL to "https://example.invalid/api",
            CredentialMetadataKey.PlanType to "personal"
        )
    )

    private fun bearerSecret() = CredentialSecret.BearerToken(token = "test-fixture-token-not-real")

    private fun snapshot(id: UUID = credentialId) = UsageSnapshot(
        credentialId = id,
        fetchedAt = Instant.parse("2026-09-07T00:00:00Z"),
        metrics = listOf(
            UsageMetric(
                id = "fiveHour",
                label = "5 小时",
                used = BigDecimal("12.5"),
                limit = BigDecimal("100"),
                remaining = BigDecimal("87.5"),
                unit = UsageMetricUnit.Currency,
                presentation = UsageMetricPresentation.Progress,
                semantic = UsageMetricSemantic.UsedQuota,
                currencyCode = "USD",
                healthState = UsageMetricHealthState.Normal
            )
        )
    )

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, MyTokenDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        secretStore = FakeSecretStore()
        repository = CredentialRepositoryImpl(
            database = database,
            secretStore = secretStore
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun observeCredentials_emitsEmptyBeforeAnythingIsSaved() = runTest {
        assertEquals(emptyList<Credential>(), repository.observeCredentials().first())
    }

    @Test
    fun save_persistsMetadataAndSecretRoundTrips() = runTest {
        val credential = credential()
        repository.save(credential, bearerSecret())

        val observed = repository.observeCredentials().first()
        assertEquals(listOf(credential), observed)

        val secret = repository.readSecret(credentialId)
        assertEquals(bearerSecret(), secret)
    }

    @Test
    fun observeCredentials_ordersBySortOrder() = runTest {
        val first = credential(id = UUID.randomUUID(), name = "b", sortOrder = 2)
        val second = credential(id = UUID.randomUUID(), name = "a", sortOrder = 1)
        repository.save(first, bearerSecret())
        repository.save(second, bearerSecret())

        val ids = repository.observeCredentials().first().map { it.id }
        assertEquals(listOf(second.id, first.id), ids)
    }

    @Test
    fun save_whenSecretWriteFails_leavesNoMetadataResidue() = runTest {
        secretStore.nextSaveError = AppError.Storage("simulated keystore failure")

        assertThrows(AppError.Storage::class.java) {
            kotlinx.coroutines.runBlocking {
                repository.save(credential(), bearerSecret())
            }
        }

        assertEquals(emptyList<Credential>(), repository.observeCredentials().first())
        assertNull(repository.readSecret(credentialId))
    }

    @Test
    fun save_whenMetadataWriteFails_rollsBackSecret() = runTest {
        // Simulate a Room-level metadata write failure with a mock database whose DAO access
        // / transaction machinery throws; the repository must roll back the secret it wrote.
        val failingDatabase = Mockito.mock(MyTokenDatabase::class.java)
        Mockito.`when`(failingDatabase.credentialDao())
            .thenReturn(Mockito.mock(CredentialDao::class.java))
        Mockito.doThrow(RuntimeException("simulated metadata write failure"))
            .`when`(failingDatabase).beginTransaction()
        val failingRepository = CredentialRepositoryImpl(
            database = failingDatabase,
            secretStore = secretStore
        )

        assertThrows(AppError.Storage::class.java) {
            kotlinx.coroutines.runBlocking {
                failingRepository.save(credential(), bearerSecret())
            }
        }

        assertFalse(secretStore.storage.containsKey(credentialId))
    }

    @Test
    fun delete_cascadesToMetadataSecretAndSnapshotCache() = runTest {
        val credential = credential()
        repository.save(credential, bearerSecret())
        repository.cacheSnapshot(snapshot())

        repository.delete(credentialId)

        assertEquals(emptyList<Credential>(), repository.observeCredentials().first())
        assertNull(repository.readSecret(credentialId))
        assertFalse(secretStore.storage.containsKey(credentialId))
        assertNull(database.usageSnapshotDao().findById(credentialId.toString()))
    }

    @Test
    fun delete_unknownId_isIdempotent() = runTest {
        repository.delete(UUID.randomUUID())
        assertTrue(secretStore.storage.isEmpty())
    }

    @Test
    fun readSecret_returnsNullWhenUnknown() = runTest {
        assertNull(repository.readSecret(UUID.randomUUID()))
    }

    @Test
    fun cacheSnapshot_andCachedSnapshot_roundTrip() = runTest {
        repository.cacheSnapshot(snapshot())
        assertEquals(snapshot(), repository.cachedSnapshot(credentialId))
    }

    @Test
    fun cachedSnapshot_returnsNullForUnknownId() = runTest {
        assertNull(repository.cachedSnapshot(UUID.randomUUID()))
    }

    @Test
    fun delete_cascadesSnapshot_evenWhenSnapshotJsonWasWrittenSeparately() = runTest {
        repository.save(credential(), bearerSecret())
        database.usageSnapshotDao().upsert(
            ai.routin.mytoken.data.local.UsageSnapshotEntity(
                credentialId = credentialId.toString(),
                fetchedAtEpochMs = 0L,
                metricsJson = UsageSnapshotJsonCodec.encode(snapshot())
            )
        )

        repository.delete(credentialId)

        assertNull(database.usageSnapshotDao().findById(credentialId.toString()))
    }
}
