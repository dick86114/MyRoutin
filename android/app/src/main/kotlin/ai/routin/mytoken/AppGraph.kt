package ai.routin.mytoken

import ai.routin.mytoken.core.security.AndroidKeystoreSecretStore
import ai.routin.mytoken.data.local.MyTokenDatabase
import ai.routin.mytoken.data.repository.CredentialRepositoryImpl
import ai.routin.mytoken.domain.usage.RefreshCredentialsUseCase
import ai.routin.mytoken.provider.defaultUsageProviders
import ai.routin.mytoken.feature.credentials.DataStoreCredentialOrderStore
import ai.routin.mytoken.feature.settings.DataStoreDisplaySettingsStore
import ai.routin.mytoken.feature.settings.DataStoreRefreshSettingsStore
import ai.routin.mytoken.feature.transfer.TransferClient
import ai.routin.mytoken.feature.transfer.TransferRepositoryImpl
import android.content.Context
import androidx.room.Room

/**
 * Hand-rolled app graph (a full DI framework is out of scope for Task 9; Task 11 may
 * revisit the wiring when the navigation layer is rebuilt).
 */
class AppGraph(context: Context) {

    private val appContext = context.applicationContext

    val database: MyTokenDatabase by lazy {
        Room.databaseBuilder(appContext, MyTokenDatabase::class.java, MyTokenDatabase.NAME).build()
    }

    val credentialRepository: CredentialRepositoryImpl by lazy {
        CredentialRepositoryImpl(database, AndroidKeystoreSecretStore(appContext))
    }

    val providers: Map<ai.routin.mytoken.domain.model.ProviderId, ai.routin.mytoken.domain.usage.UsageProvider> by lazy {
        defaultUsageProviders()
    }

    val refreshUseCase: RefreshCredentialsUseCase by lazy {
        RefreshCredentialsUseCase(credentialRepository, providers)
    }

    val credentialOrderStore: DataStoreCredentialOrderStore by lazy {
        DataStoreCredentialOrderStore(appContext)
    }

    val displaySettingsStore: DataStoreDisplaySettingsStore by lazy {
        DataStoreDisplaySettingsStore(appContext)
    }

    val refreshSettingsStore: DataStoreRefreshSettingsStore by lazy {
        DataStoreRefreshSettingsStore(appContext)
    }

    val transferRepository: TransferRepositoryImpl by lazy {
        TransferRepositoryImpl(TransferClient(), credentialRepository)
    }
}
