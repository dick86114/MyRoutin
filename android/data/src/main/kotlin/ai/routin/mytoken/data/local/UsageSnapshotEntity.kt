package ai.routin.mytoken.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Cached last-fetched usage snapshot per credential. */
@Entity(tableName = "usage_snapshots")
data class UsageSnapshotEntity(
    @PrimaryKey val credentialId: String,
    val fetchedAtEpochMs: Long,
    val metricsJson: String
)
