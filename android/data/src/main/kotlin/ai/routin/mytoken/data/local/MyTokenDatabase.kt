package ai.routin.mytoken.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [CredentialEntity::class, UsageSnapshotEntity::class],
    version = 1,
    exportSchema = true
)
abstract class MyTokenDatabase : RoomDatabase() {
    abstract fun credentialDao(): CredentialDao
    abstract fun usageSnapshotDao(): UsageSnapshotDao

    companion object {
        const val NAME = "mytoken.db"
    }
}
