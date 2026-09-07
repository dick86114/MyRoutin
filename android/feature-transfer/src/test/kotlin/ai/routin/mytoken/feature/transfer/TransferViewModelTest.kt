package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.domain.model.AppError
import java.time.Instant
import java.util.Base64
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TransferViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    private lateinit var repository: FakeTransferRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        repository = FakeTransferRepository()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun viewModel(): TransferViewModel = TransferViewModel(repository) { raw ->
        // Deterministic decoder: only the fixture URI is valid in tests.
        if (raw == TransferFixtures.QR_URI) {
            TransferQrCodePayload.decode(raw, TransferFixtures.NOW)
        } else {
            throw TransferQrCodePayloadException(
                TransferQrCodePayload.Reason.INVALID_ENCODING
            )
        }
    }

    @Test
    fun `scan success moves through connecting to preview`() = runTest {
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        val state = vm.state.value
        assertTrue("expected PreviewReady but was $state", state is TransferUiState.PreviewReady)
        val preview = (state as TransferUiState.PreviewReady).preview
        assertEquals(1, preview.credentialCount)
        assertEquals(1, preview.sensitiveItemCount)
    }

    @Test
    fun `invalid scan content shows failure without connecting`() = runTest {
        val vm = viewModel()
        vm.onQrCodeScanned("not a transfer uri")
        advanceUntilIdle()
        assertTrue(vm.state.value is TransferUiState.Failed)
        assertEquals(0, repository.connectCalls)
    }

    @Test
    fun `unreachable mac shows failure`() = runTest {
        repository.connectError = AppError.Network("cannot reach transfer host")
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        assertTrue(vm.state.value is TransferUiState.Failed)
        assertEquals(1, repository.connectCalls)
        assertEquals(0, repository.importCalls)
    }

    @Test
    fun `tampered ciphertext surfaces as authentication failure`() = runTest {
        repository.decryptError = AppError.Authentication("decryption failed")
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        assertTrue(vm.state.value is TransferUiState.Failed)
        assertEquals(0, repository.importCalls)
    }

    @Test
    fun `expired session shows failure`() = runTest {
        repository.connectError =
            TransferQrCodePayloadException(TransferQrCodePayload.Reason.EXPIRED)
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        assertTrue(vm.state.value is TransferUiState.Failed)
        // The connect error above surfaces before any import happens.
        assertEquals(0, repository.importCalls)
    }

    @Test
    fun `cancel before confirmation resets to idle without importing`() = runTest {
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        vm.cancel()
        assertEquals(TransferUiState.Idle, vm.state.value)
        assertEquals(0, repository.importCalls)
    }

    @Test
    fun `confirm import writes and completes`() = runTest {
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        vm.confirmImport(ImportConflictMode.SKIP)
        advanceUntilIdle()
        val state = vm.state.value
        assertTrue("expected Completed but was $state", state is TransferUiState.Completed)
        assertEquals(1, repository.importCalls)
        assertEquals(ImportConflictMode.SKIP, repository.lastConflictMode)
        assertEquals(1, repository.importedPackage!!.credentials.size)
    }

    @Test
    fun `connect failure never reaches decrypt or import`() = runTest {
        repository.connectError = AppError.Network("unreachable")
        val vm = viewModel()
        vm.onQrCodeScanned(TransferFixtures.QR_URI)
        advanceUntilIdle()
        assertEquals(1, repository.connectCalls)
        assertEquals(0, repository.decryptCalls)
        assertEquals(0, repository.importCalls)
    }
}

/** Fake [TransferRepository] recording calls for ViewModel tests. */
private class FakeTransferRepository : TransferRepository {
    var connectCalls = 0
    var decryptCalls = 0
    var importCalls = 0
    var connectError: Throwable? = null
    var decryptError: Throwable? = null
    var lastConflictMode: ImportConflictMode? = null
    var importedPackage: TransferPackageV1? = null

    private val packageData = TransferPackageCodec.decode(TransferFixtures.PACKAGE_JSON.toByteArray())
    private val encrypted = EncryptedTransferPackage(
        sessionId = TransferFixtures.SESSION_ID,
        message = TransferEncryptedMessage(
            protocolVersion = 1,
            sessionId = TransferFixtures.SESSION_ID,
            nonce = Base64.getEncoder().encodeToString(ByteArray(12)),
            ciphertext = Base64.getEncoder().encodeToString(ByteArray(16)),
            authenticationTag = Base64.getEncoder().encodeToString(ByteArray(16))
        ),
        sessionKey = ByteArray(32)
    )

    override suspend fun connect(payload: TransferQrCodePayload): Result<EncryptedTransferPackage> {
        connectCalls += 1
        connectError?.let { return Result.failure(it) }
        return Result.success(encrypted)
    }

    override suspend fun decrypt(packageData: EncryptedTransferPackage): Result<TransferPackageV1> {
        decryptCalls += 1
        decryptError?.let { return Result.failure(it) }
        return Result.success(this.packageData)
    }

    override suspend fun import(
        packageData: TransferPackageV1,
        conflictMode: ImportConflictMode
    ): Result<ImportSummary> {
        importCalls += 1
        lastConflictMode = conflictMode
        importedPackage = packageData
        return Result.success(ImportSummary(importedCount = 1, overwrittenCount = 0, skippedCount = 0, skippedWithoutSecretCount = 0))
    }

    override suspend fun preview(packageData: TransferPackageV1): ImportPreview = ImportPreview(
        providerCount = 1,
        credentialCount = 1,
        sensitiveItemCount = 1
    )

    override suspend fun previewItems(packageData: TransferPackageV1): List<TransferImportItem> = listOf(
        TransferImportItem(
            credentialId = UUID.fromString("A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"),
            providerId = "deepseek",
            credentialKind = "bearerAPIKey",
            name = "Example Key",
            hasSecret = true,
            conflictsWithExisting = false
        )
    )
}
