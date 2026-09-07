package thro.journal

import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.MatchState
import thro.engine.OutRule
import thro.engine.PlayerId
import thro.engine.Structure
import thro.engine.StructureMode
import java.time.Instant

/**
 * The values ADR-006's journal is written in.
 *
 * Deliberately the same shapes as `ThroJournal`'s on iOS, name for name, because ADR-002's whole
 * argument is that the domain is one domain and the platforms are two renderings of it. Where a
 * name differs here it is Kotlin convention (`RETIRED` for `.retired`), never a different idea.
 */

/** A rejection or a refusal the journal itself raises. Part of the contract, not an accident. */
public sealed class JournalException(message: String) : Exception(message) {
    public class Sqlite(message: String) : JournalException("SQLite: $message")

    /**
     * A pragma was requested and the database reports something else. `PRAGMA journal_mode = WAL`
     * does not fail when it cannot switch — it returns a row naming the mode actually in force — so
     * a configuration that is not read back is a configuration that is assumed.
     */
    public class ConfigurationNotInForce(
        public val pragma: String,
        public val wanted: String,
        public val got: String,
    ) : JournalException(
        "PRAGMA $pragma requested $wanted but the database reports $got; " +
            "the configuration is not in force",
    )

    public class MatchNotFound(public val id: String) : JournalException("no match $id in this journal")

    /** An undo was asked for and there is no standing visit to strike. */
    public class NothingToRetract : JournalException("there is no visit to undo")

    /**
     * A command id already in this journal was offered again for a **different** command.
     *
     * A repeat of the same command is a retry and returns what was stored; this is the other case,
     * and it is corruption rather than a retry — two different things claiming one identity. It is
     * refused loudly instead of being written as a second row, because the id is what a server uses
     * to recognise a command it has already seen.
     */
    public class CommandIdReused(public val commandId: String, public val stored: String) :
        JournalException("command id $commandId is already in this journal, for $stored")

    /**
     * The journal holds a command the engine rejects on replay. That is corruption, and a replay
     * that shrugged past it would rebuild a match that never happened.
     */
    public class ReplayRejected(public val seq: Long, public val reason: String) :
        JournalException("journal entry $seq rejected on replay: $reason")

    /** Something was written to a match already retired or abandoned (PD-016). An ending is final. */
    public class AlreadyEnded(public val ending: Ending) : JournalException(
        when (ending) {
            is Ending.Retired -> "this match was already retired, and an ending is final"
            is Ending.Abandoned -> "this match was already abandoned, and an ending is final"
        },
    )
}

/**
 * What the journal asks of SQLite, and what it can honestly verify afterwards.
 *
 * **This is deliberately smaller than the iOS configuration, and the difference is the point.**
 * `ThroJournal` sets four pragmas: WAL, `synchronous=FULL`, `fullfsync` and `checkpoint_fullfsync`.
 * The last two are Apple barriers — `F_FULLSYNC` — that push data past the drive's write cache, and
 * ADR-006 measured them on an iPhone at P95 1.64 ms.
 *
 * **Android has no equivalent barrier, and setting the pragma there would prove nothing.** SQLite
 * accepts `PRAGMA fullfsync` on every platform and stores the value, so reading it back would
 * return 1 and a verification built on that would pass while nothing had happened to the hardware.
 * A check that always passes is worse than no check, so this configuration does not ask for what it
 * cannot confirm. It asks for the two that are meaningful everywhere and reads both back.
 *
 * **No durability number is claimed for Android.** ADR-006's measurement is an iPhone measurement.
 * The equivalent run on a real Android device is outstanding, in the same way OD-020's watch
 * measurement is, and until somebody takes it this package makes no claim about how much of a
 * committed visit survives a battery being pulled.
 */
public data class DurabilityConfiguration(
    val journalMode: String,
    val synchronous: String,
) {
    public companion object {
        /**
         * What the client asks for. Named `candidate` rather than `measured` on purpose: the iOS
         * constant is called `measured` because a measurement exists behind it, and this one has
         * none yet.
         */
        public val candidate: DurabilityConfiguration =
            DurabilityConfiguration(journalMode = "WAL", synchronous = "FULL")
    }
}

@JvmInline
public value class DeviceId(public val value: String)

@JvmInline
public value class MatchId(public val value: String)

/**
 * Which competitor. Display names are presentation; the engine's PlayerIds are these two strings
 * for every local match, so a journal row never depends on how a name was spelled.
 */
public enum class Seat {
    HOME,
    AWAY,
    ;

    /** The stored form, which is the iOS one: lower case, so the two files are interchangeable. */
    public val stored: String get() = name.lowercase()

    public val playerId: PlayerId get() = PlayerId(stored)

    public val opponent: Seat get() = if (this == HOME) AWAY else HOME

    public companion object {
        public fun of(stored: String): Seat? = entries.firstOrNull { it.stored == stored }
        public fun of(player: PlayerId): Seat? = of(player.value)
    }
}

/** What is needed to start a local match. */
public data class NewMatch(
    val homeName: String,
    val awayName: String,
    val startingScore: Int = 501,
    val inRule: InRule = InRule.STRAIGHT,
    val outRule: OutRule = OutRule.DOUBLE,
    val legsMode: StructureMode = StructureMode.BEST_OF,
    val legsTarget: Int = 5,
    val throwFirst: Seat = Seat.HOME,
    /**
     * Who each name refers to, when the device knows (ADR-016). Null is normal and always readable:
     * a match without them is a match that cannot be claimed until its players are named.
     */
    val homePlayerId: String? = null,
    val awayPlayerId: String? = null,
)

public data class MatchRecord(
    val id: MatchId,
    val homeName: String,
    val awayName: String,
    val startingScore: Int,
    val inRule: InRule,
    val outRule: OutRule,
    val legsMode: StructureMode,
    val legsTarget: Int,
    val throwFirst: Seat,
    val startedAt: Instant,
    val homePlayerId: String?,
    val awayPlayerId: String?,
    /** When this match was put away (PD-026), or null while it is on Home. */
    val archivedAt: Instant?,
) {
    public val isArchived: Boolean get() = archivedAt != null

    public fun playerId(seat: Seat): String? = if (seat == Seat.HOME) homePlayerId else awayPlayerId

    public fun name(seat: Seat): String = if (seat == Seat.HOME) homeName else awayName

    public val format: MatchFormat get() = MatchFormat(
        startingScore = startingScore,
        inRule = inRule,
        outRule = outRule,
        legs = Structure(mode = legsMode, target = legsTarget),
        throwFirst = throwFirst.playerId,
    )

    public val initialState: MatchState get() =
        MatchState.start(format, Seat.HOME.playerId, Seat.AWAY.playerId)
}

/**
 * One committed row: a visit, or a retraction that strikes an earlier visit from the effective
 * record. A correction supersedes; it never deletes, and the struck row stays for an investigator
 * to read (PD-004).
 */
public data class JournalEntry(
    val matchId: MatchId,
    val deviceId: DeviceId,
    val deviceSeq: Long,
    val commandId: String,
    val kind: Kind,
    val seat: Seat,
    val visitTotal: Int,
    val dartsUsed: Int?,
    val dartsAtDouble: Int?,
    /** For a retraction: the `deviceSeq` of the visit it strikes. */
    val correctsSeq: Long?,
    val occurredAt: Instant,
) {
    /**
     * What a row is.
     *
     * `UNKNOWN` is not written by anything; it is what a row written by a LATER build reads back
     * as. It exists because the alternative — the one the iOS journal shipped with — was to fall
     * back to a visit, which would have replayed somebody else's confirmation as a nil-scoring
     * visit and quietly changed the score and every statistic derived from it. Replay throws on it.
     */
    public enum class Kind {
        VISIT,
        RETRACTION,
        CONFIRMATION,
        CONTEST,
        RETIREMENT,
        ABANDONMENT,
        UNKNOWN,
        ;

        public val stored: String get() = name.lowercase()

        /** The kinds that carry a score. Everything else is a fact about the record, not a throw. */
        public val isScoring: Boolean get() = this == VISIT

        /** The kinds that close a match short of its format (PD-016). Both are final. */
        public val endsTheMatch: Boolean get() = this == RETIREMENT || this == ABANDONMENT

        /**
         * The kinds that change what the result IS, and so make an earlier agreement stale. A
         * confirmation or a contest is somebody's opinion of the result and changes nothing.
         */
        public val changesTheResult: Boolean get() = isScoring || this == RETRACTION || endsTheMatch

        public companion object {
            public fun of(stored: String): Kind = entries.firstOrNull { it.stored == stored } ?: UNKNOWN
        }
    }

    /** The engine command a visit carries. Nothing else carries one; replay skips them. */
    public val command: thro.engine.Command?
        get() = if (!kind.isScoring) {
            null
        } else {
            thro.engine.Command.RecordVisit(
                player = seat.playerId,
                visitTotal = visitTotal,
                dartsUsed = dartsUsed,
                dartsAtDouble = dartsAtDouble,
            )
        }
}

/**
 * How a match ended short of its format (PD-016).
 *
 * A **retirement** is a concession: somebody stops and the other player wins, which is how darts
 * has always handled an injury or a walk-off, and it is a result that should count. An
 * **abandonment** has no winner — the pub shut, the lights went out — and inventing one would put a
 * win on somebody's record that nobody threw for. Collapsing them would force exactly one of those
 * two errors, which is why there are two.
 */
public sealed interface Ending {
    /** `by` is the player who **retired**. The other seat won. */
    public data class Retired(val by: Seat) : Ending

    /** Nobody won, and nobody is going to be given the win. */
    public data object Abandoned : Ending

    /** Who won, when anybody did. Null for an abandonment is the whole point of the type. */
    public val winner: Seat?
        get() = when (this) {
            is Retired -> by.opponent
            is Abandoned -> null
        }

    /**
     * Whether this ending produces a result at all. An abandoned match is a thing that happened,
     * not a match somebody won, so nothing downstream may treat it as one.
     */
    public val isResult: Boolean get() = winner != null

    public val kind: JournalEntry.Kind
        get() = when (this) {
            is Retired -> JournalEntry.Kind.RETIREMENT
            is Abandoned -> JournalEntry.Kind.ABANDONMENT
        }
}

/**
 * One visit as the engine saw it, produced by replay. Carries what the statistics need and what the
 * journal row alone cannot say: the remaining before and after, whether it bust, whether it won the
 * leg, and the visit's ordinal within the leg FOR THAT SEAT — per (player, leg), never shared
 * across the two competitors, which is the mistake that once put the wrong three visits into a
 * first-nine average.
 */
public data class ReplayedVisit(
    val seat: Seat,
    val legOrdinal: Int,
    val visitOrdinal: Int,
    val visitTotal: Int,
    val dartsUsed: Int?,
    val dartsAtDouble: Int?,
    val remainingBefore: Int,
    val remainingAfter: Int,
    val bust: Boolean,
    val wonLeg: Boolean,
)

/** Who stands behind the result as it is recorded right now (PD-011). */
public data class Standing(
    val confirmed: Set<Seat>,
    val contested: Set<Seat>,
    /**
     * A visit, a retraction or an ending was written **after** the last attestation, so what
     * somebody agreed to is no longer what is recorded. The attestation is not deleted — nothing
     * here ever is — it simply no longer describes this result, and the label says so.
     */
    val stale: Boolean,
) {
    public val bothConfirmed: Boolean get() = confirmed == Seat.entries.toSet() && !stale
    public val anyContest: Boolean get() = contested.isNotEmpty() && !stale
}
