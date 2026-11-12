package org.avoperformance.horse.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Update
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "horses", indices = [Index(value = ["code"], unique = true)])
data class HorseEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** Identifier written to the watch (max 23 bytes), e.g. HORSE_001. */
    val code: String,
    val name: String,
    val breed: String = "",
    val birthYear: Int? = null,
    val notes: String = "",
    val active: Boolean = true,
    /** Local file (app storage) with the horse photo, or null. */
    val photoPath: String? = null,
)

@Entity(tableName = "riders", indices = [Index(value = ["code"], unique = true)])
data class RiderEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val code: String,
    val name: String,
    val notes: String = "",
    val active: Boolean = true,
)

/** One training recorded by the watch, as known by the phone. Key = watch session id (unique by construction). */
@Entity(tableName = "trainings")
data class TrainingEntity(
    @PrimaryKey val sessionId: String,
    val watchAddress: String,
    val segments: Int,
    val totalBytes: Long,
    val downloadedBytes: Long = 0,
    val localSha256: String? = null,
    val watchSha256: String? = null,
    val serverSha256: String? = null,
    val state: String,
    val watchState: String,
    val startRtcMs: Long,
    val activeMs: Long,
    val horseCode: String? = null,
    val riderCode: String? = null,
    val localDir: String? = null,
    val lastError: String? = null,
    val updatedMs: Long = System.currentTimeMillis(),
    // analysis (only from the downloaded file; null until analysed)
    val distanceM: Double? = null,
    val maxSpeedMs: Double? = null,
    val durationS: Double? = null,
    val fixTimeS: Double? = null,
    val floatTimeS: Double? = null,
    val imuSamples: Long? = null,
    val gnssUsable: Int? = null,
)

/** Optional marine context saved for a training, independent of GNSS recording. */
@Entity(tableName = "training_marine")
data class TrainingMarineEntity(
    @PrimaryKey val sessionId: String,
    val location: String,
    val sampleMs: Long,
    val source: String,
    val levelMsl: Double?,
    val waveM: Double?,
    val wavePeriodS: Double?,
    val waterC: Double?,
    val windKmh: Double?,
    val gustKmh: Double?,
    val tideTrend: String,
    val tideCoefficient: Int? = null,
    val coefficientSource: String? = null,
    val savedMs: Long = System.currentTimeMillis(),
)

@Dao
interface TrainingMarineDao {
    @Query("SELECT * FROM training_marine WHERE sessionId = :id") suspend fun byId(id: String): TrainingMarineEntity?
    @Query("SELECT * FROM training_marine WHERE sessionId = :id") fun observe(id: String): Flow<TrainingMarineEntity?>
    @Upsert suspend fun upsert(value: TrainingMarineEntity)
}

/** Local copy of the watch geofence slots (edited on the map, then sent to the watch). */
@Entity(tableName = "fences")
data class FenceEntity(
    @PrimaryKey val slot: Int,
    val name: String,
    val type: Int,                 // FenceType.code
    val centerLatE7: Int = 0,
    val centerLonE7: Int = 0,
    val radiusCm: Long = 0,
    /** "lat,lon;lat,lon;…" in 1e-7 degrees */
    val vertices: String = "",
    val active: Boolean = false,
    val syncedWithWatch: Boolean = false,
    val updatedMs: Long = System.currentTimeMillis(),
)

@Entity(tableName = "log")
data class LogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timeMs: Long = System.currentTimeMillis(),
    val level: String,
    val tag: String,
    val message: String,
)

@Dao
interface HorseDao {
    @Query("SELECT * FROM horses ORDER BY active DESC, code") fun all(): Flow<List<HorseEntity>>
    @Query("SELECT * FROM horses WHERE id = :id") suspend fun byId(id: Long): HorseEntity?
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(h: HorseEntity): Long
    @Update suspend fun update(h: HorseEntity)
    @Query("DELETE FROM horses WHERE id = :id") suspend fun delete(id: Long)
}

@Dao
interface RiderDao {
    @Query("SELECT * FROM riders ORDER BY active DESC, code") fun all(): Flow<List<RiderEntity>>
    @Query("SELECT * FROM riders WHERE id = :id") suspend fun byId(id: Long): RiderEntity?
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insert(r: RiderEntity): Long
    @Update suspend fun update(r: RiderEntity)
    @Query("DELETE FROM riders WHERE id = :id") suspend fun delete(id: Long)
}

@Dao
interface TrainingDao {
    @Query("SELECT * FROM trainings ORDER BY startRtcMs DESC") fun all(): Flow<List<TrainingEntity>>
    @Query("SELECT * FROM trainings") suspend fun snapshot(): List<TrainingEntity>
    @Query("SELECT * FROM trainings WHERE sessionId = :id") suspend fun byId(id: String): TrainingEntity?
    @Query("SELECT * FROM trainings WHERE sessionId = :id") fun observe(id: String): Flow<TrainingEntity?>
    @Upsert suspend fun upsert(t: TrainingEntity)
}

@Dao
interface FenceDao {
    @Query("SELECT * FROM fences ORDER BY slot") fun all(): Flow<List<FenceEntity>>
    @Query("SELECT * FROM fences ORDER BY slot") suspend fun snapshot(): List<FenceEntity>
    @Upsert suspend fun upsert(f: FenceEntity)
    @Query("DELETE FROM fences WHERE slot = :slot") suspend fun delete(slot: Int)
}

@Dao
interface LogDao {
    @Query("SELECT * FROM log ORDER BY id DESC LIMIT :n") fun last(n: Int): Flow<List<LogEntity>>
    @Insert suspend fun insert(l: LogEntity)
    @Query("DELETE FROM log WHERE id < (SELECT MAX(id) FROM log) - 5000") suspend fun trim()
}

// ---------------------------------------------------------------- Sharing between users (Firebase)

/** Outgoing delivery (training → AVO recipient). Persistent queue: survives restarts. */
@Entity(tableName = "share_out", primaryKeys = ["sessionId", "recipient"])
data class ShareOutEntity(
    val sessionId: String,
    val recipient: String,
    val recipientName: String,
    val origin: String,
    val state: String,
    val transferId: String?,
    val attempts: Int,
    val lastError: String?,
    val createdMs: Long,
    val updatedMs: Long,
    val receivedMs: Long?,
    val horseCode: String?,
)

/** Incoming delivery (reception history and deliveries pending confirmation). */
@Entity(tableName = "share_in")
data class ShareInEntity(
    @PrimaryKey val transferId: String,
    val fromCode: String,
    val fromName: String,
    val sessionId: String,
    val horseName: String,
    val size: Long,
    val state: String,
    val receivedMs: Long,
    val message: String?,
    val localFile: String?,
)

/** Automatic recipients: scope "GLOBAL" or a horse code. */
@Entity(tableName = "share_recipients", primaryKeys = ["scope", "code"])
data class ShareRecipientEntity(val scope: String, val code: String, val name: String)

@Dao
interface ShareDao {
    @Query("SELECT * FROM share_out ORDER BY updatedMs DESC") fun outFlow(): Flow<List<ShareOutEntity>>
    @Query("SELECT * FROM share_out") fun outAll(): List<ShareOutEntity>
    @Query("SELECT * FROM share_out WHERE sessionId = :id") fun outFor(id: String): Flow<List<ShareOutEntity>>
    @Upsert fun upsertOut(e: ShareOutEntity)
    @Query("SELECT * FROM share_in ORDER BY receivedMs DESC") fun inFlow(): Flow<List<ShareInEntity>>
    @Query("SELECT * FROM share_in") fun inAll(): List<ShareInEntity>
    @Upsert fun upsertIn(e: ShareInEntity)
    @Query("SELECT * FROM share_recipients ORDER BY name") fun recipientsFlow(): Flow<List<ShareRecipientEntity>>
    @Query("SELECT * FROM share_recipients") fun recipientsAll(): List<ShareRecipientEntity>
    @Upsert fun upsertRecipient(e: ShareRecipientEntity)
    @Query("DELETE FROM share_recipients WHERE scope = :scope AND code = :code") fun deleteRecipient(scope: String, code: String)
}

@Database(entities = [HorseEntity::class, RiderEntity::class, TrainingEntity::class, FenceEntity::class, LogEntity::class, TrainingMarineEntity::class, ShareOutEntity::class, ShareInEntity::class, ShareRecipientEntity::class], version = 5, exportSchema = true)
abstract class AvoDatabase : RoomDatabase() {
    abstract fun horses(): HorseDao
    abstract fun riders(): RiderDao
    abstract fun trainings(): TrainingDao
    abstract fun fences(): FenceDao
    abstract fun log(): LogDao
    abstract fun marine(): TrainingMarineDao
    abstract fun share(): ShareDao

    companion object {
        fun create(ctx: Context): AvoDatabase = Room.databaseBuilder(ctx, AvoDatabase::class.java, "avo.db")
            .addMigrations(object : androidx.room.migration.Migration(1, 2) {
                override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                    db.execSQL("CREATE TABLE IF NOT EXISTS training_marine (sessionId TEXT NOT NULL PRIMARY KEY, location TEXT NOT NULL, sampleMs INTEGER NOT NULL, source TEXT NOT NULL, levelMsl REAL, waveM REAL, wavePeriodS REAL, waterC REAL, windKmh REAL, gustKmh REAL, tideTrend TEXT NOT NULL, savedMs INTEGER NOT NULL)")
                }
            }, object : androidx.room.migration.Migration(2, 3) {
                override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                    db.execSQL("ALTER TABLE training_marine ADD COLUMN tideCoefficient INTEGER")
                    db.execSQL("ALTER TABLE training_marine ADD COLUMN coefficientSource TEXT")
                }
            }, object : androidx.room.migration.Migration(3, 4) {
                override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                    db.execSQL("ALTER TABLE horses ADD COLUMN photoPath TEXT")
                }
            }, object : androidx.room.migration.Migration(4, 5) {
                // Sharing between users (Firebase): only adds tables; existing data is not touched.
                override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                    db.execSQL("CREATE TABLE IF NOT EXISTS share_out (sessionId TEXT NOT NULL, recipient TEXT NOT NULL, recipientName TEXT NOT NULL, origin TEXT NOT NULL, state TEXT NOT NULL, transferId TEXT, attempts INTEGER NOT NULL, lastError TEXT, createdMs INTEGER NOT NULL, updatedMs INTEGER NOT NULL, receivedMs INTEGER, horseCode TEXT, PRIMARY KEY(sessionId, recipient))")
                    db.execSQL("CREATE TABLE IF NOT EXISTS share_in (transferId TEXT NOT NULL PRIMARY KEY, fromCode TEXT NOT NULL, fromName TEXT NOT NULL, sessionId TEXT NOT NULL, horseName TEXT NOT NULL, size INTEGER NOT NULL, state TEXT NOT NULL, receivedMs INTEGER NOT NULL, message TEXT, localFile TEXT)")
                    db.execSQL("CREATE TABLE IF NOT EXISTS share_recipients (scope TEXT NOT NULL, code TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY(scope, code))")
                }
            }).build()
    }
}
