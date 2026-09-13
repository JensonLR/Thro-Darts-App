package thro.client

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import thro.journal.Ending
import thro.journal.Journal
import thro.journal.MatchId
import thro.journal.MatchRecord
import thro.journal.Seat

// Every match this phone has kept (PD-026, and the iOS Home list it is parallel to).
//
// **The journal already held all of this.** `Journal.matches()` has existed since ADR-006 and the Android
// client never read it: you could score a match and then never see it again, which makes the app a
// calculator rather than a record. That is the whole of what this file fixes, and it needs no account and
// no network — the journal is the phone's own and always was.
//
// **Structurally parallel to iOS, deliberately** (ADR-002 for the engine; the same argument holds for what
// is drawn from it). `AppStore.HomeMatch` on iOS carries the record, the two leg counts, whether it is
// complete, how it ended, and — the interesting one — why it could not be read when it could not. Two
// clients that word the same fact differently are two products, and the second one is the one nobody
// checks. So the states, the words and the ordering are the phone's.
//
// **Three status words, not two.** A match that was abandoned is finished and is *not* a result. A row that
// called it "In progress" would be wrong and a row that called it a win would be worse. The same reasoning
// puts `Unreadable` first: a match whose own rows will not replay still happened, and it stays on the list
// saying so rather than vanishing and leaving somebody to wonder whether they imagined it.

/// One line on the list. Built by [ThroMatchList], which is where the reasoning lives; this is only shape.
public data class ThroMatchRow(
    val record: MatchRecord,
    val legsHome: Int,
    val legsAway: Int,
    val complete: Boolean = false,
    /// Why this match's rows would not replay, when they would not. Null is the ordinary case.
    val unreadable: String? = null,
    /// How it ended short (PD-016), or null if it ran to its finish or is still running.
    val ending: Ending? = null,
) {
    public val id: MatchId get() = record.id

    /// The status word. Order matters: unreadable beats ended, and ended beats complete.
    public val status: String
        get() = when {
            unreadable != null -> "Unreadable"
            ending is Ending.Retired -> "Retired"
            ending is Ending.Abandoned -> "No result"
            complete -> "Finished"
            else -> "In progress"
        }

    /// `3–2`, or nothing at all when the rows would not replay — a score read off a journal that will not
    /// open is a number with nothing behind it, and this product does not print those.
    public val score: String? get() = if (unreadable != null) null else "$legsHome–$legsAway"

    public val title: String get() = "${record.homeName} v ${record.awayName}"

    /// Who won, in the two names already on the row. Null while it is unfinished, unreadable, or a draw
    /// that cannot happen but is not worth crashing over.
    public val wonBy: String?
        get() {
            if (unreadable != null || !complete) return null
            return when (val how = ending) {
                // Retiring is losing: the seat named is the one that stopped, so the other one won.
                is Ending.Retired -> if (how.by == Seat.HOME) record.awayName else record.homeName
                Ending.Abandoned -> null
                null -> when {
                    legsHome > legsAway -> record.homeName
                    legsAway > legsHome -> record.awayName
                    else -> null
                }
            }
        }
}

public object ThroMatchList {

    /// Newest first, which is the order somebody looks for the one they just played.
    ///
    /// **A match that will not replay is still on the list.** `replayVisits` can throw — a truncated write,
    /// a row from a future version of the app — and the tempting handling is to drop the match. That would
    /// be the app deciding that something the player did never happened. It stays, with the reason on it.
    public fun rows(journal: Journal, archived: Boolean? = false): List<ThroMatchRow> =
        journal.matches(archived = archived)
            .sortedByDescending { it.startedAt }
            .map { row(journal, it) }

    public fun row(journal: Journal, record: MatchRecord): ThroMatchRow {
        val ending = runCatching { journal.ending(record.id) }.getOrNull()
        return runCatching {
            val state = journal.replay(record.id)
            ThroMatchRow(
                record = record,
                legsHome = state.legsWonTotal[state.home] ?: 0,
                legsAway = state.legsWonTotal[state.away] ?: 0,
                // Both kinds of ending close the keypad, so both are complete; `ending` says which.
                complete = state.winner != null || ending != null,
                ending = ending,
            )
        }.getOrElse { trouble ->
            ThroMatchRow(
                record = record,
                legsHome = 0,
                legsAway = 0,
                unreadable = trouble.message ?: trouble::class.simpleName ?: "unknown",
                ending = ending,
            )
        }
    }

    /// `12 Sept`, or `12 Sept 2025` once it is not this year — the year is noise on a list of last month's
    /// darts and is the only thing you want on a list of last season's.
    ///
    /// **The locale is a parameter, and the month's spelling is not ours to choose.** The first version
    /// hard-coded an expectation of `12 Sep` and the test failed with `12 Sept`, because CLDR 42 changed
    /// the abbreviation for September in `en-GB` and the JDK follows CLDR. That is the platform being
    /// right: a British reader writes *Sept*. iOS reads its month names from the same source, so the two
    /// clients agree without either of them holding a table — which they would not if this had been
    /// "fixed" by pinning a pattern of our own.
    public fun day(
        at: Instant,
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault(),
    ): String {
        val then = at.atZone(zone)
        val pattern = if (then.year == now.atZone(zone).year) "d MMM" else "d MMM yyyy"
        return DateTimeFormatter.ofPattern(pattern, locale).format(then)
    }

    /// What the list says when there is nothing on it. Not "no matches" — the player knows that; what they
    /// do not know is that it is going to keep them, which is the reason to play one on this phone.
    public const val NOTHING_YET: String = "Every match you score stays here, on this phone."
}
