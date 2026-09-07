package ai.routin.mytoken.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "credentials")
data class CredentialEntity(
    @PrimaryKey val id: String,
    val providerId: String,
    val credentialKind: String,
    val name: String,
    val isEnabled: Boolean,
    val sortOrder: Int,
    val baseURL: String?,
    val userID: String?,
    val region: String?,
    val planType: String?,
    val usageKind: String?,
    val websiteURL: String?
)
