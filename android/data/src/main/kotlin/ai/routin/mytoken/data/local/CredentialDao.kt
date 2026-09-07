package ai.routin.mytoken.data.local

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface CredentialDao {
    @Query("SELECT * FROM credentials ORDER BY sortOrder ASC, name ASC")
    fun observeAll(): Flow<List<CredentialEntity>>

    @Query("SELECT * FROM credentials ORDER BY sortOrder ASC, name ASC")
    suspend fun getAll(): List<CredentialEntity>

    @Upsert
    suspend fun upsert(credential: CredentialEntity)

    @Query("DELETE FROM credentials WHERE id = :id")
    suspend fun deleteById(id: String)
}

@Dao
interface UsageSnapshotDao {
    @Upsert
    suspend fun upsert(snapshot: UsageSnapshotEntity)

    @Query("SELECT * FROM usage_snapshots WHERE credentialId = :id")
    suspend fun findById(id: String): UsageSnapshotEntity?

    @Query("DELETE FROM usage_snapshots WHERE credentialId = :id")
    suspend fun deleteById(id: String)
}
