package ai.routin.mytoken.core.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Encrypts secrets with an AES-256-GCM key held in the Android Keystore and persists the
 * ciphertext in a file under the app's noBackupFilesDir. Mirrors the semantics of the
 * macOS KeychainSecretStore: save is upsert, read returns null when absent, delete is idempotent.
 */
class AndroidKeystoreSecretStore(
    context: Context,
    private val keyAliasPrefix: String = DEFAULT_KEY_ALIAS_PREFIX
) : SecretStore {

    private val storageDir: File = context.noBackupFilesDir

    override suspend fun save(id: UUID, secret: ByteArray) = withContext(Dispatchers.IO) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey(aliasFor(id)))
        val ciphertext = cipher.doFinal(secret)
        val iv = cipher.iv
        val payload = ByteArray(1 + iv.size + ciphertext.size)
        payload[0] = iv.size.toByte()
        iv.copyInto(payload, 1)
        ciphertext.copyInto(payload, 1 + iv.size)
        payloadFile(id).writeBytes(payload)
    }

    override suspend fun read(id: UUID): ByteArray? = withContext(Dispatchers.IO) {
        val file = payloadFile(id)
        if (!file.exists()) return@withContext null
        val payload = file.readBytes()
        val ivLength = payload[0].toInt()
        val iv = payload.copyOfRange(1, 1 + ivLength)
        val ciphertext = payload.copyOfRange(1 + ivLength, payload.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(aliasFor(id)), GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
        cipher.doFinal(ciphertext)
    }

    override suspend fun delete(id: UUID) = withContext(Dispatchers.IO) {
        payloadFile(id).delete()
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(aliasFor(id))) {
            keyStore.deleteEntry(aliasFor(id))
        }
    }

    private fun getOrCreateKey(alias: String): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun payloadFile(id: UUID): File = File(storageDir, "$PAYLOAD_PREFIX${id}.bin")

    private fun aliasFor(id: UUID): String = keyAliasPrefix + id

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val PAYLOAD_PREFIX = "cred-"
        const val DEFAULT_KEY_ALIAS_PREFIX = "mytoken.cred."
    }
}
