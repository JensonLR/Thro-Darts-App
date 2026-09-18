package thro.api

import java.sql.Connection
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID
import thro.api.http.Contract

/**
 * Tell THRØ (PD-119): a sentence on the secretary's desk becomes a typed act to confirm.
 *
 * The shape is the one TypeSafe's function-calling cookbook describes. One request carries a Choice over the acts the
 * desk can perform and every argument each act could take, as closed sets: the season's own fixtures and teams by
 * name, side and date; the scorelines and times code has already found in the text; the parts of a date. The model
 * matches meaning to an option and returns a probability for each; code reads only what the chosen act needs, does
 * the calendar and the arithmetic itself, cross-checks what it can (the side the sentence says won against the
 * numbers), and hands back a card with its least certain part named. A person confirms. Nothing is recorded here.
 */
public class Understanding(private val model: SystemOne, private val today: () -> LocalDate) {

    public data class Fixture(val fixtureId: UUID, val home: String, val homeTeamId: UUID, val away: String, val awayTeamId: UUID, val at: Instant, val decided: Boolean)
    public data class Team(val teamId: UUID, val name: String)
    /** What the desk knows: the season's fixtures and teams, and the season's own dates. */
    public data class Desk(val fixtures: List<Fixture>, val teams: List<Team>, val seasonStart: LocalDate, val seasonEnd: LocalDate)

    public data class Alternative(val fixtureId: UUID, val label: String, val p: Double)
    public data class Picked(val fixtureId: UUID, val home: String, val away: String, val at: Instant, val p: Double, val alternatives: List<Alternative>)
    public data class Result(val legsHome: Int, val legsAway: Int)
    public data class Award(val toTeamId: UUID, val toName: String, val reason: String)
    /** The points rules a sentence states; a part it does not state is null and is left as it stands. */
    public data class Points(val win: Int?, val draw: Int?, val loss: Int?, val perLeg: Int?)
    /** Where a fixture is moved to. With no time in the sentence, the fixture keeps the clock time it had. */
    public data class Move(val on: LocalDate, val time: LocalTime, val to: Instant)
    public data class Schedule(val homeTeamId: UUID, val home: String, val awayTeamId: UUID, val away: String, val on: LocalDate?, val time: LocalTime?, val scheduledAt: Instant?)
    /**
     * What the sentence was read as. [ready] when every part the act needs is there and nothing contradicts; [doubt]
     * names the part that is missing or in question. [confidence] is the least certain of the parts read, as the
     * cookbook has it: one wrong argument spoils the call, so the weakest link is the number that matters.
     */
    public data class Understood(
        val text: String, val act: String, val confidence: Double, val ready: Boolean, val say: String, val doubt: String?,
        val fixture: Picked?, val result: Result?, val award: Award?, val schedule: Schedule?, val reason: String?,
        val move: Move? = null,
        val points: Points? = null,
    )

    public companion object {
        /**
         * How many options a Choice is given before the way out (PD-157). TypeSafe document 255 as the ceiling, and
         * "none" takes one of them.
         *
         * It was 200, chosen for no stated reason, and a real division is bigger than that: Stockton Thursday's
         * eighteen teams play 306 fixtures in a double round-robin, so 106 of them were cut off the end of the list
         * the model was allowed to choose from — and a fixture that is not an option cannot be picked, however
         * plainly the sentence names it. Past 254 the answer is two passes (a Choice over the season's weeks, then
         * over that week's fixtures), not a longer list.
         */
        public const val OPTION_CEILING: Int = 254

        /**
         * How sure a read has to be before THRØ offers it for a tap (PD-157).
         *
         * `ready` was `doubt == null` — every part present and nothing contradicting. But every part present is not
         * every part right: the scorecard holds "station 5 riverside b 1" read *reversed* at 0.39, with nothing
         * contradicting it, and that card was ready. The number is 0.6 because that is what PD-125 measured as the
         * band below which an answer flips between runs; a third threshold would be one more number to keep true.
         */
        public const val SURE_ENOUGH: Double = 0.6

        /**
         * The option a Choice picked, and **how sure the model was** — its `confidence`, not the winner's share of
         * the distribution (PD-157).
         *
         * These were three byte-similar copies, each reading `probabilities[choice]` and falling back to
         * `confidence`. That is the wrong way round. TypeSafe derive `confidence` from the whole distribution, so
         * it is the statistic that tells a winner at 0.45 with a runner-up at 0.44 apart from a winner at 0.45 with
         * the rest spread thin — which is exactly the difference between a read worth offering and a guess.
         * `probabilities[choice]` remains the fallback for an answer that carries no confidence, and
         * `distribution` still reads the probabilities for the alternatives a card lists.
         */
        /**
         * The season's fixtures whose **both sides** this sentence names (PD-158). Code only: no model, no tokens.
         *
         * This is the floor PD-154 said to publish before buying a question. On the sealed set of twenty sentences
         * about fixtures a season has not got, it throws out all twenty on its own — so a question asked to do the
         * same job has nothing left to win, and a question asked to do a *different* job has a number to beat.
         *
         * What it deliberately does not do is choose **which** of a pair's two meetings is meant. A double
         * round-robin has every pair playing twice, presence finds both, and nothing in "Grange A beat Dolphin 5-3"
         * says which leg. That is a job for a date, and where the sentence carries none it is a job for a person.
         * Saying so here is the difference between a floor and a guess.
         */
        public fun fixturesNamed(desk: Desk, text: String): List<Fixture> =
            desk.fixtures.filter { TeamNames.mentions(text, it.home) && TeamNames.mentions(text, it.away) }

        internal fun pick(answers: Map<String, Any?>, id: String): Pair<String, Double>? {
            val a = answers[id] as? Map<*, *> ?: return null
            val option = a["choice"] as? String ?: return null
            val sure = (a["confidence"] as? Number)?.toDouble()
                ?: ((a["probabilities"] as? Map<*, *>)?.get(option) as? Number)?.toDouble() ?: 0.0
            return option to sure
        }

        /** Darts in the UK: every date and time the desk reads is London's. */
        public val ZONE: ZoneId = ZoneId.of("Europe/London")
        public val ACTS: Map<String, String> = linkedMapOf(
            "result" to "Recording what a fixture finished as: the legs each side won, e.g. 'Grange A beat Dolphin 5-3' — often just two teams and two numbers, however tersely: 'Dolphin 6 Bell B 2', 'station 5 riverside b 1'",
            "award" to "Awarding a fixture nobody played to one side: a walkover, a forfeit, a team that did not turn up",
            "void" to "Annulling a result already recorded, so the fixture is played again",
            "move" to "Moving a fixture already in the season to another day or time: a postponement, a rearrangement, 'is off until'",
            "schedule" to "Adding a new fixture to the season: two teams and a date",
            "points" to "Setting the league's points rules for its table: how many points for a win, a draw, a loss, or for each leg won",
            "none" to "None of these: a question, a note, a greeting, or something the desk cannot do",
        )
        /** "5-3", "7–2", "5 to 3", "5 v 3". Not "20:30": a colon is a clock, not a scoreline. */
        private val SCORE = Regex("""(?<!\d)(\d{1,2})\s*(?:-|–|—|to|v)\s*(\d{1,2})(?!\d)""", RegexOption.IGNORE_CASE)
        /** The same expression, for [ResultsSheet] to split a scoreline `scorelines` has already found (PD-159). */
        public val SCORE_PUBLIC: Regex get() = SCORE
        /** "8", "20:30", "7.30pm", "8 o'clock". Not "15th": an ordinal is a day of the month. */
        private val TIME = Regex("""(?<![\d.:])(\d{1,2})(?:[.:](\d{2}))?\s*(am|pm|o'clock)?(?!\d|st|nd|rd|th)""", RegexOption.IGNORE_CASE)
        /** "15th", "22nd", "3rd", "1st": a day of the month, written as one. Never a time — TIME refuses the suffix. */
        private val ORDINAL = Regex("""(?<![\d.:])(\d{1,2})(?:st|nd|rd|th)\b""", RegexOption.IGNORE_CASE)
        /** A number standing alone: not part of a clock ("7.30", "8pm"), not an ordinal ("8th"), at most two digits. */
        private val BARE = Regex("""(?<![\d.:])\d{1,2}(?![\d.:]|\s*(?:am|pm|o'clock)|st|nd|rd|th)""", RegexOption.IGNORE_CASE)
        private val MONTH_AFTER = Regex("""^\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)""", RegexOption.IGNORE_CASE)
        private val MONTH_BEFORE = Regex("""(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*$""", RegexOption.IGNORE_CASE)
        private val MONTHS = listOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")
        private val WEEKDAYS = DayOfWeek.values().map { it.getDisplayName(TextStyle.FULL, Locale.UK) }
        // Written by hand rather than by a locale: Java's UK locale prints "Sept", and the page prints "Sep".
        private val DOW = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        private val MON = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
        private fun dayOf(d: LocalDate): String = "${DOW[d.dayOfWeek.value - 1]} ${d.dayOfMonth} ${MON[d.monthValue - 1]}"

        /** The scorelines written in the text, as written: "5-3", "7–2". The model chooses among these or none. */
        public fun scorelines(text: String): List<String> {
            val written = SCORE.findAll(text).map { it.value.trim() }.distinct().toList()
            if (written.isNotEmpty()) return written
            // "Dolphin 6 Grange A 2": the legs either side of a name. Exactly two bare numbers, neither a clock, an
            // ordinal nor beside a month's name — and then they are the scoreline, in the order they were written.
            val bare = BARE.findAll(text).filter { m ->
                !(MONTH_AFTER.containsMatchIn(text.substring(m.range.last + 1)) || MONTH_BEFORE.containsMatchIn(text.substring(0, m.range.first)))
            }.map { it.value }.toList()
            return if (bare.size == 2) listOf("${bare[0]}-${bare[1]}") else emptyList()
        }

        /**
         * The days of the month the text actually offers, as numbers: an ordinal ("the 22nd"), or a bare number beside a
         * month's name ("5 November", "October 15"). Nothing else.
         *
         * **Why this exists (PD-131).** The day question used to offer 1..31 whatever the sentence said, so the "7" of
         * "at 7" — already found by `times()` — was a legal answer to it as well, and on the real model it was given as
         * one: "how about this Friday at 7?" came back `month=October day=7` and resolved a year away. A code cannot be
         * read as two things at once if it is only ever offered as one, which is cheaper and surer than reconciling two
         * answers afterwards. A bare number with no ordinal and no month beside it is left out: in a captain's sentence
         * it is a time far more often than a date, and leaving it out costs a glance at the date picker, while taking it
         * costs a wrong date that reads as certain.
         */
        public fun daysOfMonth(text: String): List<String> {
            val scores = SCORE.findAll(text).map { it.range }.toList()
            fun inScore(r: IntRange) = scores.any { s -> r.first in s }
            val ordinals = ORDINAL.findAll(text).filterNot { inScore(it.range) }.map { it.groupValues[1] }
            val besideMonth = BARE.findAll(text).filterNot { inScore(it.range) }.filter { m ->
                MONTH_AFTER.containsMatchIn(text.substring(m.range.last + 1)) || MONTH_BEFORE.containsMatchIn(text.substring(0, m.range.first))
            }.map { it.value }
            return (ordinals + besideMonth).map { it.trimStart('0').ifEmpty { "0" } }
                .filter { (it.toIntOrNull() ?: 0) in 1..31 }.distinct().toList()
        }

        /**
         * The times written in the text, as written: "8", "20:30", "7.30pm". A bare number that is part of a scoreline is
         * not a time, and a number over 24 is not one either.
         */
        public fun times(text: String): List<String> {
            val scores = SCORE.findAll(text).flatMap { m -> sequenceOf(m.range) }.toList()
            return TIME.findAll(text).filter { m -> scores.none { r -> m.range.first in r } }
                .filter { m -> m.groupValues[1].toInt() in 0..24 }
                // "8 Oct", "October 15": a bare number beside a month's name is a day of the month, not an hour.
                .filter { m -> m.groupValues[2].isNotEmpty() || m.groupValues[3].isNotEmpty()
                    || !(MONTH_AFTER.containsMatchIn(text.substring(m.range.last + 1)) || MONTH_BEFORE.containsMatchIn(text.substring(0, m.range.first))) }
                .filter { m -> m.groupValues[2].isNotEmpty() || m.groupValues[3].isNotEmpty() || m.groupValues[1].toInt() in 1..12 || m.groupValues[1].toInt() in 13..23 }
                .map { it.value.trim() }.distinct().toList()
        }

        /** What the desk knows about a season, read from the database; null when THRØ has no such season. */
        public fun desk(connection: Connection, season: UUID): Desk? {
            val plan = SeasonPlanning(connection).season(season) ?: return null
            val fixtures = Fixtures(connection).of(season).map { f ->
                Fixture(f.fixtureId, f.home ?: "A team", f.homeTeamId, f.away ?: "A team", f.awayTeamId, f.scheduledAt, decided = f.decided != null)
            }
            return Desk(fixtures, plan.teams.filter { it.status == "accepted" }.map { Team(it.teamId, it.name) }, plan.startsOn, plan.endsOn)
        }

        private fun label(f: Fixture): String =
            "${f.home} (home) v ${f.away} (away), ${dayOf(f.at.atZone(ZONE).toLocalDate())} ${f.at.atZone(ZONE).year}" + if (f.decided) " — played, a result is recorded" else ""
        private fun day(at: Instant): String = dayOf(at.atZone(ZONE).toLocalDate())
        private fun clock(t: LocalTime): String = DateTimeFormatter.ofPattern("h:mm a", Locale.UK).format(t).lowercase()
    }

    /** Reads the sentence, or null when the model gave no answer. */
    public fun understand(desk: Desk, text: String): Understood? {
        val clean = text.trim()
        // The candidates code found: the model can only choose what is there.
        val fixtures = desk.fixtures.sortedWith(compareBy<Fixture> { it.decided }.thenBy { it.at }).take(OPTION_CEILING)
        val fixtureKeys = fixtures.mapIndexed { i, f -> "f${i + 1}" to f }.toMap()
        val teamKeys = desk.teams.mapIndexed { i, t -> "t${i + 1}" to t }.toMap()
        val scores = scorelines(clean).mapIndexed { i, s -> "s${i + 1}" to s }.toMap()
        val times = times(clean).mapIndexed { i, s -> "h${i + 1}" to s }.toMap()

        val pointOptions: Map<String, String?> = (0..5).associate { it.toString() to null } + ("none" to "the sentence does not say")
        val state = obj("text" to clean, "scorelines_found" to arr(*scores.values.toTypedArray()), "today" to "${today()} (${today().dayOfWeek.getDisplayName(TextStyle.FULL, Locale.UK)})",
                        "context" to "A darts league secretary's desk. The sentence is about this league season's fixtures: two teams, a date, and often a scoreline in legs.")
        val questions = obj(
            "act" to choice("What is the sentence asking the desk to do?", ACTS),
            "fixture" to choice("Which fixture is the sentence about? Match the teams it names, however shortened; a team named first in the sentence may be either side of the fixture. A 'derby' is the fixture between two teams of the same pub or club (the same name, A and B). If the sentence adds a new fixture or names none, choose none.",
                                fixtureKeys.mapValues { label(it.value) } + ("none" to "The sentence is about no fixture listed, or adds a new one")),
            "score" to choice("Which of these scorelines found in the text is the result — the legs each side won?",
                              scores.mapValues { "the scoreline written as '${it.value}'" } + ("none" to "No scoreline is stated, or none of these is one")),
            // Asked as *which team*, not which side: measured on the real model (PD-123), a question about an entity
            // in the sentence is read far more surely than one about a role in a fixture it has not been told is chosen.
            "first_number_team" to choice("The first number of the scoreline is the legs won by which team? Usually the team the sentence names first or attaches the number to.",
                                          teamKeys.mapValues { it.value.name } + ("none" to "no scoreline, or it cannot be told")),
            "winner_team" to choice("Which team does the sentence say won — beat the other, or the other lost to it?",
                                    teamKeys.mapValues { it.value.name } + ("none" to "the sentence does not say who won, or it was a draw")),
            "award_team" to choice("If the sentence awards a fixture — a walkover, a forfeit, a team that did not turn up, could not raise a side, or broke a rule — which team gets it? The team that receives the walkover or the win, never the team at fault.",
                                   teamKeys.mapValues { it.value.name } + ("none" to "the sentence awards nothing to anybody")),
            "home_team" to choice("For a new fixture: which team is the home side — named first, or said to be at home?", teamKeys.mapValues { it.value.name } + ("none" to "not stated")),
            "away_team" to choice("For a new fixture: which team is the away side — named second, or said to be away?", teamKeys.mapValues { it.value.name } + ("none" to "not stated")),
            *dateQuestions(clean).toTypedArray(),
            // The league's rules (PD-125): small whole numbers offered, never written. "none" is "the sentence does not say".
            "win_points" to choice("How many points does the sentence give for a WIN?", pointOptions),
            "draw_points" to choice("How many points does the sentence give for a DRAW?", pointOptions),
            "loss_points" to choice("How many points does the sentence give for a LOSS?", pointOptions),
            "leg_points" to choice("How many points does the sentence give for EACH LEG won (a bonus per leg)?", pointOptions),
            "time" to choice("Which of these times found in the text is when the fixture is played?", times.mapValues { "the time written as '${it.value}'" } + ("none" to "no time stated")),
        )
        val answers = try { model.answers(state.s, questions.s) } catch (e: Exception) { null } ?: return null

        fun pick(id: String): Pair<String, Double>? = Companion.pick(answers, id)
        fun distribution(id: String): Map<String, Double> =
            ((answers[id] as? Map<*, *>)?.get("probabilities") as? Map<*, *>)?.entries?.associate { (k, v) -> k.toString() to ((v as? Number)?.toDouble() ?: 0.0) } ?: emptyMap()

        val (act, actP) = pick("act") ?: return null
        val used = mutableListOf(actP)
        var doubt: String? = null

        /**
         * Whether this read is offered for a tap (PD-157): every part present, **and** the model sure enough of the
         * least sure of them. `doubt == null` alone shipped a card the model was split on — the scorecard's
         * "station 5 riverside b 1", read reversed at 0.39 with nothing contradicting it. Where the parts are all
         * there but the confidence is not, the part in doubt is `sure`: not a missing fact, a shaky one.
         */
        fun settle(): Pair<Boolean, String?> =
            if (doubt != null) false to doubt
            else if (used.min() < SURE_ENOUGH) false to "sure"
            else true to null

        fun fixturePicked(): Picked? {
            val (key, p) = pick("fixture") ?: return null
            val f = fixtureKeys[key] ?: return null
            used += p
            val others = distribution("fixture").filterKeys { it != key && it != "none" }.entries.sortedByDescending { it.value }.take(3)
                .filter { it.value >= 0.05 }.mapNotNull { (k, v) -> fixtureKeys[k]?.let { Alternative(it.fixtureId, "${it.home} v ${it.away}, ${day(it.at)}", v) } }
            return Picked(f.fixtureId, f.home, f.away, f.at, p, others)
        }

        return when (act) {
            "result" -> {
                val fixture = fixturePicked()
                var result: Result? = null
                if (fixture == null) doubt = "fixture"
                val (scoreKey, scoreP) = pick("score") ?: ("none" to 0.0)
                val written = scores[scoreKey]
                if (written == null) { if (doubt == null) doubt = "score" }
                else {
                    used += scoreP
                    val m = SCORE.find(written)!!
                    val a = m.groupValues[1].toInt(); val b = m.groupValues[2].toInt()
                    val f = fixture?.let { p -> desk.fixtures.first { it.fixtureId == p.fixtureId } }
                    val winner = pick("winner_team")?.let { (k, pr) -> teamKeys[k]?.let { it to pr } }
                    val first = pick("first_number_team")?.let { (k, pr) -> teamKeys[k]?.let { it to pr } }
                    result = when {
                        f == null || a == b -> Result(a, b)   // a draw needs nobody's number told apart
                        // Who won is read more surely than whose number came first, and in darts the winner has the
                        // larger number: so where the sentence says who won, code does the rest.
                        winner != null && winner.first.teamId == f.homeTeamId -> { used += winner.second; Result(maxOf(a, b), minOf(a, b)) }
                        winner != null && winner.first.teamId == f.awayTeamId -> { used += winner.second; Result(minOf(a, b), maxOf(a, b)) }
                        first != null && first.first.teamId == f.homeTeamId -> { used += first.second; Result(a, b) }
                        first != null && first.first.teamId == f.awayTeamId -> { used += first.second; Result(b, a) }
                        else -> { doubt = "score"; used += 0.5; Result(a, b) }   // a team that is in neither side: say so
                    }
                }
                val say = if (fixture != null && result != null) "${fixture.home} ${result.legsHome}–${result.legsAway} ${fixture.away}, ${day(fixture.at)}"
                          else if (fixture != null) "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — which legs?" else "A result, but for which fixture?"
                settle().let { (ok, why) -> Understood(clean, act, used.min(), ok, say, why, fixture, result, null, null, null) }
            }
            "award" -> {
                val fixture = fixturePicked()
                var award: Award? = null
                if (fixture == null) doubt = "fixture"
                else {
                    val f = desk.fixtures.first { it.fixtureId == fixture.fixtureId }
                    val to = pick("award_team")?.let { (k, pr) -> teamKeys[k]?.let { it to pr } }
                    award = when (to?.first?.teamId) {
                        f.homeTeamId -> { used += to!!.second; Award(f.homeTeamId, f.home, clean) }
                        f.awayTeamId -> { used += to!!.second; Award(f.awayTeamId, f.away, clean) }
                        else -> { doubt = "side"; null }   // no team told, or one that is in neither side
                    }
                }
                val say = when {
                    fixture == null -> "An award, but for which fixture?"
                    award == null -> "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — awarded to which side?"
                    else -> "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — awarded to ${award.toName}"
                }
                settle().let { (ok, why) -> Understood(clean, act, used.min(), ok, say, why, fixture, null, award, null, clean) }
            }
            "void" -> {
                val fixture = fixturePicked()
                if (fixture == null) doubt = "fixture"
                val say = if (fixture != null) "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — result annulled, to be replayed" else "An annulment, but of which fixture?"
                settle().let { (ok, why) -> Understood(clean, act, used.min(), ok, say, why, fixture, null, null, null, clean) }
            }
            "move" -> {
                val fixture = fixturePicked()
                var move: Move? = null
                val f = fixture?.let { p -> desk.fixtures.first { it.fixtureId == p.fixtureId } }
                if (f == null || f.decided) doubt = "fixture"
                else {
                    val on = date(pick("date_mode"), pick("day_anchor"), pick("weekday"), pick("week_offset"), pick("month"), pick("day"), used)
                    val (tKey, tP) = pick("time") ?: ("none" to 0.0)
                    // No time in the sentence: the clock time the fixture already had, in London.
                    val time = times[tKey]?.let { used += tP; clockOf(it) } ?: f.at.atZone(ZONE).toLocalTime()
                    when {
                        on == null -> doubt = "date"
                        on.isBefore(desk.seasonStart) || on.isAfter(desk.seasonEnd) -> { doubt = "date"; move = Move(on, time, on.atTime(time).atZone(ZONE).toInstant()) }
                        else -> move = Move(on, time, on.atTime(time).atZone(ZONE).toInstant())
                    }
                }
                val say = when {
                    fixture == null -> "A move, but of which fixture?"
                    f != null && f.decided -> "${fixture.home} v ${fixture.away}, ${day(fixture.at)} has a result, so it is not moved. Annul the result first."
                    move == null -> "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — moved to when?"
                    else -> "${fixture.home} v ${fixture.away}, ${day(fixture.at)} → ${dayOf(move.on)}, ${clock(move.time)}"
                }
                settle().let { (ok, why) -> Understood(clean, act, used.min(), ok, say, why, fixture, null, null, null, null, move) }
            }
            "points" -> {
                // A part is taken only when the model is reasonably sure it was stated (PD-125): measured on the real model,
                // "nothing for a loss" against "does not say" sits near a coin's toss and flips between runs, and a part
                // left out is simply left as the league has it — the safe side of that doubt.
                fun part(id: String): Int? = pick(id)?.takeIf { it.second >= SURE_ENOUGH }?.let { (k, p) -> k.toIntOrNull()?.also { used += p } }
                val points = Points(part("win_points"), part("draw_points"), part("loss_points"), part("leg_points"))
                val stated = listOfNotNull(points.win?.let { "$it for a win" }, points.draw?.let { "$it for a draw" }, points.loss?.let { "$it for a loss" }, points.perLeg?.let { "$it a leg won" })
                if (stated.isEmpty()) doubt = "points"
                settle().let { (ok, why) ->
                    Understood(clean, act, used.min(), ok, if (stated.isEmpty()) "The points rules — but how many for a win?" else stated.joinToString(" · "), why,
                               null, null, null, null, null, null, if (stated.isEmpty()) null else points)
                }
            }
            "schedule" -> {
                val (hKey, hP) = pick("home_team") ?: ("none" to 0.0)
                val (aKey, aP) = pick("away_team") ?: ("none" to 0.0)
                val home = teamKeys[hKey]; val away = teamKeys[aKey]
                var schedule: Schedule? = null
                if (home == null || away == null) doubt = "teams"
                else if (home.teamId == away.teamId) doubt = "teams"
                else {
                    used += hP; used += aP
                    val on = date(pick("date_mode"), pick("day_anchor"), pick("weekday"), pick("week_offset"), pick("month"), pick("day"), used)
                    val (tKey, tP) = pick("time") ?: ("none" to 0.0)
                    val time = times[tKey]?.let { used += tP; clockOf(it) }
                    val at = if (on != null && time != null) on.atTime(time).atZone(ZONE).toInstant() else null
                    schedule = Schedule(home.teamId, home.name, away.teamId, away.name, on, time, at)
                    when {
                        on == null -> doubt = "date"
                        on.isBefore(desk.seasonStart) || on.isAfter(desk.seasonEnd) -> doubt = "date"
                        time == null -> doubt = "time"
                    }
                }
                val say = when {
                    schedule == null -> "A new fixture, but between which teams?"
                    schedule.on == null -> "${schedule.home} v ${schedule.away} — on what date?"
                    schedule.time == null -> "${schedule.home} v ${schedule.away}, ${dayOf(schedule.on)} — at what time?"
                    else -> "${schedule.home} v ${schedule.away}, ${dayOf(schedule.on)}, ${clock(schedule.time)}"
                }
                settle().let { (ok, why) -> Understood(clean, act, used.min(), ok, say, why, null, null, null, schedule, null) }
            }
            else -> Understood(clean, "none", actP, false, "That reads as a question or a note, not something THRØ can do from here. Try “Grange A beat Dolphin 5–3”, “Move Riverside v Grange to next Thursday”, “Add Riverside A v Dolphin next Thursday at 8” or “3 points for a win, 1 for a draw”.", null, null, null, null, null, null)
        }
    }

    // --- a pasted fixture list (PD-122) -------------------------------------------------------------------------------

    /** One fixture read from one line of a pasted list; [doubt] names what a person must settle before it is scheduled. */
    // --- the captain's sentence (PD-129) ---------------------------------------------------------------------------

    /** A captain's sentence about ONE fixture, read as a new day and time for it. [doubt] is `move` or `date`. */
    public data class MoveRead(val text: String, val move: Move?, val confidence: Double, val ready: Boolean, val say: String, val doubt: String?)

    /**
     * "Can we do the 22nd instead, the pub's shut" — on the fixture's own screen, so there is no fixture to choose and
     * no act to classify beyond whether it asks for a move at all. The same date questions as the desk's, the same
     * code doing the calendar, and the time stays where it was unless the sentence says one. Null when the model gave
     * no answer. Nothing is proposed by reading: the form is filled, and the captain sends it.
     */
    public fun readMove(fixture: Fixture, seasonStart: LocalDate, seasonEnd: LocalDate, text: String): MoveRead? {
        val clean = text.trim()
        val times = times(clean).mapIndexed { i, s -> "h${i + 1}" to s }.toMap()
        val state = obj("text" to clean, "fixture" to label(fixture), "today" to "${today()} (${today().dayOfWeek.getDisplayName(TextStyle.FULL, Locale.UK)})",
                        "context" to "A darts team's captain, on the screen of the one league fixture named here, typing to the other team's captain about playing it on another day. "
                            + "The fixture's own date is given so it is not mistaken for the new one: the new date is the one the sentence asks for.")
        val questions = obj(
            "asks_move" to choice("Does the sentence ask to play this fixture on another day or at another time — a postponement, a rearrangement, a suggestion of a date?",
                                  mapOf("yes" to null, "no" to "a greeting, a question about something else, or nothing about when it is played")),
            // Counted from the fixture, not from today: "put it back a week" is how a captain says it, and code adds the days.
            "shift" to choice("Does the sentence move the fixture by a number of weeks from the date it is on, rather than naming a date?",
                              mapOf("none" to "no: it names a date or a day, or says nothing of when", "week_later" to "one week later: 'back a week', 'the week after'",
                                    "fortnight_later" to "two weeks later: 'a fortnight', 'two weeks on'", "week_earlier" to "one week earlier: 'forward a week', 'the week before'")),
            *dateQuestions(clean).toTypedArray(),
            "time" to choice("Which of these times found in the text is when the fixture would be played?", times.mapValues { "the time written as '${it.value}'" } + ("none" to "no time stated")),
        )
        val answers = try { model.answers(state.s, questions.s) } catch (e: Exception) { null } ?: return null
        fun pick(id: String): Pair<String, Double>? = Companion.pick(answers, id)
        val used = mutableListOf<Double>()
        val asks = pick("asks_move") ?: return null
        used += asks.second
        if (asks.first != "yes") return MoveRead(clean, null, used.min(), false, "That does not read as a new date for this fixture.", "move")
        val was = fixture.at.atZone(ZONE)
        val shift = pick("shift")?.takeIf { it.first != "none" && it.second >= SURE_ENOUGH }
        val on = if (shift != null) {
            used += shift.second
            was.toLocalDate().plusDays(when (shift.first) { "week_later" -> 7L; "fortnight_later" -> 14L; else -> -7L })
        } else date(pick("date_mode"), pick("day_anchor"), pick("weekday"), pick("week_offset"), pick("month"), pick("day"), used)
        val (tKey, tP) = pick("time") ?: ("none" to 0.0)
        val time = times[tKey]?.let { used += tP; clockOf(it) } ?: was.toLocalTime()
        // Seen on the first real run: the fixture's own date read back as the new one. A move to where it is, is no move.
        if (on == was.toLocalDate() && time == was.toLocalTime()) return MoveRead(clean, null, used.min(), false, "That is when it already is. To when?", "date")
        if (on != null && on.isBefore(today())) return MoveRead(clean, null, used.min(), false, "${dayOf(on)} has gone. To when?", "date")
        if (on == null) return MoveRead(clean, null, used.min(), false, "A move, but to when?", "date")
        val move = Move(on, time, on.atTime(time).atZone(ZONE).toInstant())
        val inside = !on.isBefore(seasonStart) && !on.isAfter(seasonEnd)
        return MoveRead(clean, move, used.min(), inside, "${dayOf(on)}, ${clock(time)}" + (if (inside) "" else " is outside the season"), if (inside) null else "date")
    }

    public fun json(m: MoveRead): String = json(obj(
        "text" to m.text, "ready" to m.ready, "confidence" to m.confidence, "say" to m.say, "doubt" to m.doubt,
        "to" to m.move?.to?.toString(), "on" to m.move?.on?.toString(), "time" to m.move?.time?.toString(),
    ))

    /**
     * The date's parts, asked the same way wherever a date is read: the model reads the parts, code does the calendar.
     *
     * Asked of the sentence, not in the abstract (PD-131): the day of the month is offered only where the text writes
     * one, so a code `times()` already found cannot be answered here too. There were three byte-identical copies of
     * this list — here, in `understand` and in `readList` — and a fix applied to one left the other two wrong; there is
     * one now, and `the desk and the captain's screen ask the same date questions` holds them together.
     */
    private fun dateQuestions(text: String): List<Pair<String, Any?>> = listOf(
        "date_mode" to choice("How is the fixture's date written? 'absolute' names a month or a day of the month; 'relative' is given from today (today, tomorrow, a named weekday such as 'next Thursday'); 'none' when no date is stated.",
                              mapOf("absolute" to null, "relative" to null, "none" to null)),
        "day_anchor" to choice("If the date is given from today, which day is it?",
                               mapOf("today" to "the sentence says today, tonight or this evening, and names no day of the week",
                                     "tomorrow" to "the sentence says tomorrow", "day_after" to "the day after tomorrow",
                                     "weekday" to "a named day of the week, such as 'this Friday'",
                                     "none" to "the date is not given from today")),
        "weekday" to choice("If the date names a day of the week, which?", WEEKDAYS.associateWith { null } + ("none" to "no weekday named")),
        "week_offset" to choice("If the date names a weekday: 'this' means the coming one, 'next' means the one in the week after.",
                                mapOf("this" to "this week, or the coming one", "next" to "next week", "none" to "the date names no day of the week")),
        "month" to choice("If the date is absolute, which month?", MONTHS.associateWith { null } + ("none" to "no month named; the day of the month alone, or none")),
        "day" to choice("If the date is absolute, which day of the month? Only the days written in the sentence are offered.",
                        daysOfMonth(text).associateWith { null } + ("none" to "no day of the month named")),
    )

    public data class ListRow(val line: Int, val text: String, val homeTeamId: UUID?, val home: String?, val awayTeamId: UUID?, val away: String?,
                              val on: LocalDate?, val time: LocalTime?, val scheduledAt: Instant?, val confidence: Double, val doubt: String?)
    public data class Skipped(val line: Int, val text: String, val why: String)
    public data class ListRead(val rows: List<ListRow>, val skipped: List<Skipped>)

    /**
     * Reads a league's fixture list as it was pasted. One request per line that says anything, six at a time: is it a
     * fixture, which of the season's teams is at home and away, which month and day, which of the times code found.
     * Code carries a date heading down to the fixtures beneath it, picks the year that puts a date inside the season,
     * gives a fixture with no time the list's usual one, and names each row's doubt. Null when the model answered
     * nothing at all. Nothing is scheduled here.
     */
    public fun readList(desk: Desk, text: String): ListRead? {
        val lines = text.lines().mapIndexed { i, l -> (i + 1) to l.trim() }.filter { it.second.isNotEmpty() }
        require(lines.size <= 200) { "A list is at most 200 lines. Paste it in parts." }
        if (lines.isEmpty()) return ListRead(emptyList(), emptyList())
        val teamKeys = desk.teams.mapIndexed { i, t -> "t${i + 1}" to t }.toMap()
        val teamOptions = teamKeys.mapValues { it.value.name } + ("none" to "no team of this season is named here")

        fun ask(line: String): Pair<Map<String, Any?>?, Map<String, String>> {
            val found = times(line).mapIndexed { i, t -> "h${i + 1}" to t }.toMap()
            val state = obj("line" to line, "context" to "One line from a darts league's published fixture list. Most lines are a fixture: a home team, 'v', an away team, often a date and a time. Some are headings: a date on its own, a division's name, a week number, a note.")
            val questions = obj(
                "is_fixture" to obj("type" to "noul", "instructions" to "Is `line` a fixture — two teams playing each other?",
                                    "criteria" to obj("true" to "two teams are named as playing each other", "false" to "a heading, a date on its own, a note, a bye, or anything else")),
                "home_team" to choice("Which of the season's teams is the home side in `line` — the one named first? A name may be shortened or misspelt.", teamOptions),
                "away_team" to choice("Which of the season's teams is the away side in `line` — the one named second? A name may be shortened or misspelt.", teamOptions),
                "month" to choice("Which month does `line` name, if any?", MONTHS.associateWith { null } + ("none" to "no month is named")),
                // Only the days the line writes (PD-131): "Stn Hotel v Riverside B - 8.15" must not answer day = 8.
                "day" to choice("Which day of the month does `line` name, if any? Only the days written in the line are offered.",
                                daysOfMonth(line).associateWith { null } + ("none" to "no day of the month is named")),
                "time" to choice("Which of these times found in `line` is when the fixture is played?", found.mapValues { "the time written as '${it.value}'" } + ("none" to "no time is stated")),
            )
            return (try { model.answers(state.s, questions.s) } catch (e: Exception) { null }) to found
        }

        val pool = java.util.concurrent.Executors.newFixedThreadPool(6)   // the endpoint rate-limits above roughly eight
        val answered = try { lines.map { (_, l) -> pool.submit<Pair<Map<String, Any?>?, Map<String, String>>> { ask(l) } }.map { it.get() } } finally { pool.shutdown() }
        if (answered.all { it.first == null }) return null

        fun inSeason(month: Int, day: Int): Pair<LocalDate?, Boolean> {
            val candidates = (desk.seasonStart.year..desk.seasonEnd.year).mapNotNull { y -> runCatching { LocalDate.of(y, month, day) }.getOrNull() }
            val inside = candidates.firstOrNull { !it.isBefore(desk.seasonStart) && !it.isAfter(desk.seasonEnd) }
            return (inside ?: candidates.firstOrNull()) to (inside != null)
        }

        class Draft(val line: Int, val text: String, val home: Team?, val away: Team?, val on: LocalDate?, val onInSeason: Boolean, val time: LocalTime?, val confidence: Double)
        val drafts = mutableListOf<Draft>(); val skipped = mutableListOf<Skipped>()
        var carried: Pair<LocalDate?, Boolean>? = null
        var headingTime: LocalTime? = null
        for ((index, entry) in lines.withIndex()) {
            val (number, line) = entry
            val (answers, found) = answered[index]
            if (answers == null) { skipped += Skipped(number, line, "THRØ could not read this line"); continue }
            fun pick(id: String): Pair<String, Double>? = Companion.pick(answers, id)
            val isFixture = ((answers["is_fixture"] as? Map<*, *>)?.get("noul") as? Number)?.toDouble() ?: 0.0
            val month = pick("month")?.takeIf { it.first != "none" }; val day = pick("day")?.takeIf { it.first != "none" }
            val own = if (month != null && day != null) inSeason(MONTHS.indexOf(month.first) + 1, day.first.toInt()) else null
            if (isFixture < 0.5) {
                // A heading may carry a date down, or state the league's usual time ("all matches 7.30pm unless shown").
                // Only a clock that says it is one — "7.30pm", "19:30" — never a bare number: "Week 3" is not three o'clock.
                val stated = pick("time")?.let { (k, _) -> found[k]?.takeIf { w -> Regex("""[.:]\d{2}|am|pm|o'clock""", RegexOption.IGNORE_CASE).containsMatchIn(w) }?.let { clockOf(it) } }
                when {
                    own != null -> { carried = own; skipped += Skipped(number, line, "a date, carried down") }
                    stated != null && headingTime == null -> { headingTime = stated; skipped += Skipped(number, line, "the league's usual time, carried down") }
                    else -> skipped += Skipped(number, line, "not a fixture")
                }
                continue
            }
            if (own != null) carried = own
            val used = mutableListOf(isFixture)
            val home = pick("home_team"); val away = pick("away_team")
            home?.let { used += it.second }; away?.let { used += it.second }
            if (own != null) { used += month!!.second; used += day!!.second }
            val time = pick("time")?.let { (k, p) -> found[k]?.let { used += p; clockOf(it) } }
            drafts += Draft(number, line, teamKeys[home?.first], teamKeys[away?.first], (own ?: carried)?.first, (own ?: carried)?.second ?: false, time, used.min())
        }
        // The list's usual time: the league's own word in a heading; failing that, the one stated most often on the
        // fixtures, the first stated when two tie.
        val usual = headingTime ?: drafts.mapNotNull { it.time }.let { stated -> stated.groupingBy { it }.eachCount().maxWithOrNull(compareBy<Map.Entry<LocalTime, Int>> { it.value }.thenBy { -stated.indexOf(it.key) })?.key }
        val rows = drafts.map { d ->
            val time = d.time ?: usual
            val doubt = when {
                d.home == null || d.away == null || d.home.teamId == d.away.teamId -> "teams"
                d.on == null || !d.onInSeason -> "date"
                time == null -> "time"
                else -> null
            }
            val at = if (doubt == null) d.on!!.atTime(time!!).atZone(ZONE).toInstant() else null
            ListRow(d.line, d.text, d.home?.teamId, d.home?.name, d.away?.teamId, d.away?.name, d.on, time, at, d.confidence, doubt)
        }
        return ListRead(rows, skipped)
    }

    public fun json(l: ListRead): String {
        fun q(s: String?) = s?.let { Contract.q(it) } ?: "null"
        return "{\"rows\":[" + l.rows.joinToString(",") { r ->
            """{"line":${r.line},"text":${q(r.text)},"homeTeamId":${q(r.homeTeamId?.toString())},"home":${q(r.home)},"awayTeamId":${q(r.awayTeamId?.toString())},"away":${q(r.away)},""" +
                """"on":${q(r.on?.toString())},"time":${q(r.time?.toString())},"scheduledAt":${q(r.scheduledAt?.toString())},"confidence":${"%.2f".format(Locale.ROOT, r.confidence)},"doubt":${q(r.doubt)}}"""
        } + "],\"skipped\":[" + l.skipped.joinToString(",") { """{"line":${it.line},"text":${q(it.text)},"why":${q(it.why)}}""" } + "]}"
    }

    /** The calendar, done by code from the parts the model read (the date-extraction cookbook's split). */
    private fun date(mode: Pair<String, Double>?, anchor: Pair<String, Double>?, weekday: Pair<String, Double>?, offset: Pair<String, Double>?,
                     month: Pair<String, Double>?, day: Pair<String, Double>?, used: MutableList<Double>): LocalDate? {
        val now = today()
        mode?.let { used += it.second }
        // The parts are things in the sentence; the mode is a category about them, and the model is surer of things
        // (PD-123, and seen again in PD-129: "tomorrow at 8" read as tomorrow, and called absolute). So where it says
        // absolute and read no day of the month, and the relative parts make a date, the parts decide. The mode's own
        // probability stays in `used`, so a reading rescued this way is never more confident than the part it got wrong.
        //
        // The same lesson once more (PD-131): a named day of the week is a thing in the sentence, and the anchor is a
        // category about it. Read on the real model, "how about this Friday at 7?" came back anchored on *today* and
        // naming *Friday* in the same breath. Where a weekday is named, it decides; "today" is left to the sentences
        // that say today, tonight or this evening, which name no weekday at all.
        val named = weekday?.first?.takeIf { it != "none" }
            ?.let { name -> DayOfWeek.values().firstOrNull { it.getDisplayName(TextStyle.FULL, Locale.UK) == name } }
        val anchorKey = if (named != null) "weekday" else anchor?.first
        val relativeParts = anchorKey in setOf("today", "tomorrow", "day_after", "weekday")
        val read = if (mode?.first == "absolute" && day?.first?.toIntOrNull() == null && relativeParts) "relative" else mode?.first
        return when (read) {
            "relative" -> when (anchorKey) {
                "today" -> { used += anchor!!.second; now }
                "tomorrow" -> { used += anchor!!.second; now.plusDays(1) }
                "day_after" -> { used += anchor!!.second; now.plusDays(2) }
                "weekday" -> {
                    val wd = named ?: return null
                    weekday!!.let { used += it.second }
                    // From tomorrow: said on a Friday, "this Friday" is the Friday to come — nobody proposes a move to
                    // the day they are speaking on, and a captain who means tonight says tonight (PD-131 records this).
                    var d = now.plusDays(1)
                    while (d.dayOfWeek != wd) d = d.plusDays(1)
                    if (offset?.first == "next") { used += offset.second; d = d.plusWeeks(1) }
                    d
                }
                else -> null
            }
            "absolute" -> {
                val dd = day?.first?.toIntOrNull() ?: return null
                val m = month?.first?.let { name -> MONTHS.indexOf(name) + 1 }?.takeIf { it > 0 }
                if (m == null) {
                    // "the 16th", with no month: the next 16th to come, today's included.
                    day.let { used += it.second }
                    var d = now
                    repeat(62) { if (d.dayOfMonth == dd) return d; d = d.plusDays(1) }
                    return null
                }
                month?.let { used += it.second }; day.let { used += it.second }
                // No year is ever asked for: the first such date on or after today is the one a secretary means.
                var d = runCatching { LocalDate.of(now.year, m, dd) }.getOrNull() ?: return null
                if (d.isBefore(now)) d = d.plusYears(1)
                d
            }
            else -> null
        }
    }

    /** "8" is eight in the evening, because darts is; "20:30" and "7.30pm" say what they say. */
    private fun clockOf(written: String): LocalTime? {
        val m = TIME.find(written) ?: return null
        var hour = m.groupValues[1].toInt()
        val minute = m.groupValues[2].toIntOrNull() ?: 0
        val suffix = m.groupValues[3].lowercase()
        if (suffix == "pm" && hour < 12) hour += 12
        if (suffix == "am" && hour == 12) hour = 0
        // "8" and "8 o'clock" alike: only "am" means the morning.
        if ((suffix.isEmpty() || suffix == "o'clock") && hour in 1..11) hour += 12
        return runCatching { LocalTime.of(hour, minute) }.getOrNull()
    }

    public fun json(u: Understood): String {
        fun q(s: String?) = s?.let { Contract.q(it) } ?: "null"
        fun n(d: Double) = "%.2f".format(Locale.ROOT, d)
        val fixture = u.fixture?.let { f ->
            """{"fixtureId":"${f.fixtureId}","home":${q(f.home)},"away":${q(f.away)},"scheduledAt":"${f.at}","p":${n(f.p)},"alternatives":[""" +
                f.alternatives.joinToString(",") { """{"fixtureId":"${it.fixtureId}","label":${q(it.label)},"p":${n(it.p)}}""" } + "]}"
        } ?: "null"
        val result = u.result?.let { """{"legsHome":${it.legsHome},"legsAway":${it.legsAway}}""" } ?: "null"
        val award = u.award?.let { """{"toTeamId":"${it.toTeamId}","toName":${q(it.toName)},"reason":${q(it.reason)}}""" } ?: "null"
        val schedule = u.schedule?.let { s ->
            """{"homeTeamId":"${s.homeTeamId}","home":${q(s.home)},"awayTeamId":"${s.awayTeamId}","away":${q(s.away)},"on":${q(s.on?.toString())},"time":${q(s.time?.toString())},"scheduledAt":${q(s.scheduledAt?.toString())}}"""
        } ?: "null"
        val points = u.points?.let { """{"win":${it.win},"draw":${it.draw},"loss":${it.loss},"pointsPerLegWon":${it.perLeg}}""" } ?: "null"
        val move = u.move?.let { """{"on":"${it.on}","time":"${it.time}","to":"${it.to}"}""" } ?: "null"
        return """{"text":${q(u.text)},"act":${q(u.act)},"confidence":${n(u.confidence)},"ready":${u.ready},"say":${q(u.say)},"doubt":${q(u.doubt)},""" +
            """"fixture":$fixture,"result":$result,"award":$award,"schedule":$schedule,"move":$move,"points":$points,"reason":${q(u.reason)}}"""
    }

    /**
     * JSON this class has built, as distinct from a string somebody typed. The builder used to tell the two apart by
     * whether a string began with a bracket, so a sentence that did — "[derby] is off" — was spliced into the request
     * unquoted and broke it. A type says which is which; nothing is guessed from the first character.
     */
    private class Raw(val s: String) { override fun toString(): String = s }

    private fun choice(instructions: String, criteria: Map<String, String?>): Raw =
        obj("type" to "choice", "instructions" to instructions, "criteria" to obj(*criteria.entries.map { it.key to it.value }.toTypedArray()))
    private fun arr(vararg items: Any?): Raw = Raw(items.joinToString(",", "[", "]") { json(it) })
    private fun obj(vararg pairs: Pair<String, Any?>): Raw = Raw(pairs.joinToString(",", "{", "}") { (k, v) -> "${Contract.q(k)}:${json(v)}" })
    private fun json(v: Any?): String = when (v) {
        null -> "null"
        is Raw -> v.s
        is Number, is Boolean -> v.toString()
        is String -> Contract.q(v)
        else -> Contract.q(v.toString())
    }
}
