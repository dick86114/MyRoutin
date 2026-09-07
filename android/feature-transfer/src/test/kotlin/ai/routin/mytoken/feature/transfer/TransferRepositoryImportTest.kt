package ai.routin.mytoken.feature.transfer

import ai.routin.mytoken.domain.model.AppError
import ai.routin.mytoken.domain.model.Credential
import ai.routin.mytoken.domain.model.CredentialKind
import ai.routin.mytoken.domain.model.CredentialMetadataKey
import ai.routin.mytoken.domain.model.CredentialSecret
import ai.routin.mytoken.domain.model.ProviderId
import java.time.Instant
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TransferRepositoryImportTest {
    private val credentialId = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
    private val secondCredentialId = "B2C3D4E5-F6A7-4B8C-9D0E-1F2A3B4C5D6E"

    // -- preview --------------------------------------------------------------

    @Test
    fun `preview shows provider, credential and sensitive item counts`() = runTest {
        val repository = repository()
        val packageData = packageWithSecrets()
        val preview = repository.preview(packageData)
        assertEquals(2, preview.providerCount)
        assertEquals(2, preview.credentialCount)
        assertEquals(2, preview.sensitiveItemCount)
    }

    @Test
    fun `metadata-only package has zero sensitive items`() = runTest {
        val repository = repository()
        val preview = repository.preview(metadataOnlyPackage())
        assertEquals(1, preview.credentialCount)
        assertEquals(0, preview.sensitiveItemCount)
    }

    @Test
    fun `preview items flag existing conflicts and secret availability`() = runTest {
        val repository = repository()
        val existing = FakeCredentialRepository().apply {
            save(
                Credential(
                    id = UUID.fromString(credentialId),
                    providerId = ProviderId.DeepSeek,
                    credentialKind = CredentialKind.BearerApiKey,
                    name = "Existing Key"
                ),
                CredentialSecret.BearerToken("old-token")
            )
        }
        val repo = TransferRepositoryImpl(client(), existing)
        val items = repo.previewItems(packageWithSecrets())
        val conflicting = items.first { it.credentialId.toString().equals(credentialId, ignoreCase = true) }
        val fresh = items.first { it.credentialId.toString().equals(secondCredentialId, ignoreCase = true) }
        assertTrue(conflicting.conflictsWithExisting)
        assertTrue(conflicting.hasSecret)
        assertFalse(fresh.conflictsWithExisting)
        assertTrue(fresh.hasSecret)
    }

    // -- import ---------------------------------------------------------------

    @Test
    fun `import persists credentials and secrets through the repository`() = runTest {
        val store = FakeCredentialRepository()
        val repository = TransferRepositoryImpl(client(), store)
        val summary = repository.import(packageWithSecrets(), ImportConflictMode.SKIP).getOrThrow()

        assertEquals(2, summary.importedCount)
        assertEquals(0, summary.overwrittenCount)
        assertEquals(0, summary.skippedCount)
        val secret = store.readSecret(UUID.fromString(credentialId))
        assertTrue(secret is CredentialSecret.BearerToken)
        assertEquals("ExampleToken", (secret as CredentialSecret.BearerToken).token)
        val credential = store.credentials.getValue(UUID.fromString(credentialId))
        assertEquals("https://api.example.com/v1", credential.metadata[CredentialMetadataKey.BaseURL])
    }

    @Test
    fun `import with skip mode keeps existing credentials`() = runTest {
        val store = FakeCredentialRepository()
        store.save(
            Credential(
                id = UUID.fromString(credentialId),
                providerId = ProviderId.DeepSeek,
                credentialKind = CredentialKind.BearerApiKey,
                name = "Existing Key"
            ),
            CredentialSecret.BearerToken("old-token")
        )
        val repository = TransferRepositoryImpl(client(), store)

        val summary = repository.import(packageWithSecrets(), ImportConflictMode.SKIP).getOrThrow()

        assertEquals(1, summary.skippedCount)
        assertEquals(1, summary.importedCount)
        assertEquals("old-token", (store.secrets.getValue(UUID.fromString(credentialId)) as CredentialSecret.BearerToken).token)
    }

    @Test
    fun `import with overwrite mode replaces existing credentials`() = runTest {
        val store = FakeCredentialRepository()
        store.save(
            Credential(
                id = UUID.fromString(credentialId),
                providerId = ProviderId.DeepSeek,
                credentialKind = CredentialKind.BearerApiKey,
                name = "Existing Key"
            ),
            CredentialSecret.BearerToken("old-token")
        )
        val repository = TransferRepositoryImpl(client(), store)

        val summary = repository.import(packageWithSecrets(), ImportConflictMode.OVERWRITE).getOrThrow()

        assertEquals(1, summary.overwrittenCount)
        assertEquals(1, summary.importedCount)
        val overwritten = store.credentials.getValue(UUID.fromString(credentialId))
        assertEquals("Example Key", overwritten.name)
        assertEquals("ExampleToken", (store.secrets.getValue(UUID.fromString(credentialId)) as CredentialSecret.BearerToken).token)
    }

    @Test
    fun `import of metadata-only package skips credentials without secrets`() = runTest {
        val store = FakeCredentialRepository()
        val repository = TransferRepositoryImpl(client(), store)
        val summary = repository.import(metadataOnlyPackage(), ImportConflictMode.SKIP).getOrThrow()
        assertEquals(0, summary.importedCount)
        assertEquals(1, summary.skippedWithoutSecretCount)
        assertTrue(store.credentials.isEmpty())
    }

    @Test
    fun `failed import rolls back newly imported credentials`() = runTest {
        val store = FakeCredentialRepository()
        val repository = TransferRepositoryImpl(client(), store)
        store.failSaveFromIndex = 1 // first save succeeds, second fails

        val result = repository.import(packageWithSecrets(), ImportConflictMode.SKIP)

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is AppError.Storage)
        assertTrue("rollback must remove the first imported credential", store.credentials.isEmpty())
        assertTrue(store.secrets.isEmpty())
    }

    @Test
    fun `failed overwrite restores the original credential and secret`() = runTest {
        val store = FakeCredentialRepository()
        store.save(
            Credential(
                id = UUID.fromString(credentialId),
                providerId = ProviderId.DeepSeek,
                credentialKind = CredentialKind.BearerApiKey,
                name = "Existing Key"
            ),
            CredentialSecret.BearerToken("old-token")
        )
        // Fail from the third save: first save = setup, second = overwrite (fails).
        store.failSaveFromIndex = 1
        val repository = TransferRepositoryImpl(client(), store)

        val result = repository.import(packageWithSecrets(), ImportConflictMode.OVERWRITE)

        assertTrue(result.isFailure)
        val restored = store.credentials.getValue(UUID.fromString(credentialId))
        assertEquals("Existing Key", restored.name)
        assertEquals("old-token", (store.secrets.getValue(UUID.fromString(credentialId)) as CredentialSecret.BearerToken).token)
        assertNull(store.secrets[UUID.fromString(secondCredentialId)])
    }

    @Test
    fun `access key pair entry imports both parts`() = runTest {
        val store = FakeCredentialRepository()
        val repository = TransferRepositoryImpl(client(), store)
        val akSkId = "C3D4E5F6-A7B8-4C9D-8E0F-1F2A3B4C5D6E"
        val packageJson = TransferFixtures.PACKAGE_JSON
            .replace(
                "\"sortOrder\":0}]",
                "\"sortOrder\":0}," +
                    "{\"credentialId\":\"$akSkId\",\"credentialKind\":\"accessKeyPair\"," +
                    "\"isEnabled\":true,\"metadata\":{},\"name\":\"Volc Key\"," +
                    "\"providerId\":\"volcengine\",\"schemaVersion\":1,\"sortOrder\":1}]"
            )
            .replace(
                "\"entries\":[{\"bearerToken\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"$credentialId\"}]",
                "\"entries\":[" +
                    "{\"bearerToken\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"$credentialId\"}," +
                    "{\"accessKeyID\":\"${b64("my-access-key")}\",\"secretAccessKey\":\"${b64("my-secret-key")}\"," +
                    "\"credentialId\":\"$akSkId\"}]"
            )
        val packageData = TransferPackageCodec.decode(packageJson.toByteArray())
        val summary = repository.import(packageData, ImportConflictMode.SKIP).getOrThrow()

        assertEquals(2, summary.importedCount)
        val secret = store.secrets.getValue(UUID.fromString(akSkId))
        assertTrue(secret is CredentialSecret.AccessKeyPair)
        assertEquals("my-access-key", (secret as CredentialSecret.AccessKeyPair).accessKeyID)
        assertEquals("my-secret-key", secret.secretAccessKey)
    }

    @Test
    fun `secret entry not matching credential kind fails import`() = runTest {
        val store = FakeCredentialRepository()
        val repository = TransferRepositoryImpl(client(), store)
        val badPackage = TransferPackageCodec.decode(
            packageWithSecretsJson()
                .replace("\"bearerToken\":\"RXhhbXBsZVRva2Vu\"", "\"apiKey\":\"RXhhbXBsZVRva2Vu\"")
                .toByteArray()
        )
        val result = repository.import(badPackage, ImportConflictMode.SKIP)
        assertTrue(result.exceptionOrNull() is AppError.Decode)
        assertTrue(store.credentials.isEmpty())
    }

    // -- decrypt validation ---------------------------------------------------

    @Test
    fun `decrypt rejects unsupported protocol version`() = runTest {
        val repository = repository()
        val message = TransferEncryptedMessage(
            protocolVersion = 2,
            sessionId = TransferFixtures.SESSION_ID,
            nonce = b64(TransferFixtures.NONCE),
            ciphertext = b64(ByteArray(16)),
            authenticationTag = b64(ByteArray(16))
        )
        val result = repository.decrypt(EncryptedTransferPackage(TransferFixtures.SESSION_ID, message, ByteArray(32)))
        assertTrue(result.exceptionOrNull() is AppError.Authentication)
    }

    @Test
    fun `decrypt rejects short nonce`() = runTest {
        val repository = repository()
        val message = TransferEncryptedMessage(
            protocolVersion = 1,
            sessionId = TransferFixtures.SESSION_ID,
            nonce = b64(ByteArray(8)),
            ciphertext = b64(ByteArray(16)),
            authenticationTag = b64(ByteArray(16))
        )
        val result = repository.decrypt(EncryptedTransferPackage(TransferFixtures.SESSION_ID, message, ByteArray(32)))
        assertTrue(result.exceptionOrNull() is AppError.Authentication)
    }

    @Test
    fun `decrypt rejects malformed base64 fields`() = runTest {
        val repository = repository()
        val message = TransferEncryptedMessage(
            protocolVersion = 1,
            sessionId = TransferFixtures.SESSION_ID,
            nonce = "!!!not base64!!!",
            ciphertext = b64(ByteArray(16)),
            authenticationTag = b64(ByteArray(16))
        )
        val result = repository.decrypt(EncryptedTransferPackage(TransferFixtures.SESSION_ID, message, ByteArray(32)))
        assertTrue(result.exceptionOrNull() is AppError.Decode)
    }

    // -- helpers ---------------------------------------------------------------

    private fun repository(): TransferRepositoryImpl = TransferRepositoryImpl(client(), FakeCredentialRepository())

    private fun client(): TransferClient = TransferClient(
        clock = java.time.Clock.fixed(Instant.parse("2026-09-07T03:00:00Z"), java.time.ZoneOffset.UTC)
    )

    /** Secret envelope fields use unpadded base64url (see Base64UrlLexical). */
    private fun b64(value: String): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray(Charsets.UTF_8))

    private fun b64(value: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value)

    private fun packageWithSecretsJson(): String =
        TransferFixtures.PACKAGE_JSON.replace(
            "\"sortOrder\":0}],",
            "\"sortOrder\":0}," +
                "{\"credentialId\":\"$secondCredentialId\",\"credentialKind\":\"apiKey\"," +
                "\"isEnabled\":true,\"metadata\":{},\"name\":\"Second Key\",\"providerId\":\"routin\"," +
                "\"schemaVersion\":1,\"sortOrder\":1}],"
        )

    private fun packageWithSecrets(): TransferPackageV1 = TransferPackageCodec.decode(
        packageWithSecretsJson()
            .replace(
                "\"entries\":[{\"bearerToken\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"$credentialId\"}]",
                "\"entries\":[" +
                    "{\"bearerToken\":\"RXhhbXBsZVRva2Vu\",\"credentialId\":\"$credentialId\"}," +
                    "{\"apiKey\":\"${b64("second-key")}\",\"credentialId\":\"$secondCredentialId\"}]"
            )
            .toByteArray()
    )

    private fun metadataOnlyPackage(): TransferPackageV1 = TransferPackageCodec.decode(
        TransferFixtures.PACKAGE_JSON
            .replace(
                Regex("\"entries\":\\[.*?](,)"),
                "\"entries\":[]$1"
            )
            .toByteArray()
    )
}
