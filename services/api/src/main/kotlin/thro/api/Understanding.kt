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
    public data class Schedule(val homeTeamId: UUID, val home: String, val awayTeamId: UUID, val away: String, val on: LocalDate?, val time: LocalTime?, val scheduledAt: Instant?)
    /**
     * What the sentence was read as. [ready] when every part the act needs is there and nothing contradicts; [doubt]
     * names the part that is missing or in question. [confidence] is the least certain of the parts read, as the
     * cookbook has it: one wrong argument spoils the call, so the weakest link is the number that matters.
     */
    public data class Understood(
        val text: String, val act: String, val confidence: Double, val ready: Boolean, val say: String, val doubt: String?,
        val fixture: Picked?, val result: Result?, val award: Award?, val schedule: Schedule?, val reason: String?,
    )

    public companion object {
        /** Darts in the UK: every date and time the desk reads is London's. */
        public val ZONE: ZoneId = ZoneId.of("Europe/London")
        public val ACTS: Map<String, String> = linkedMapOf(
            "result" to "Recording what a fixture finished as: the legs each side won, e.g. 'Grange A beat Dolphin 5-3'",
            "award" to "Awarding a fixture nobody played to one side: a walkover, a forfeit, a team that did not turn up",
            "void" to "Annulling a result already recorded, so the fixture is played again",
            "schedule" to "Adding a new fixture to the season: two teams and a date",
            "none" to "None of these: a question, a note, a greeting, or something the desk cannot do",
        )
        /** "5-3", "7–2", "5 to 3", "5 v 3". Not "20:30": a colon is a clock, not a scoreline. */
        private val SCORE = Regex("""(?<!\d)(\d{1,2})\s*(?:-|–|—|to|v)\s*(\d{1,2})(?!\d)""", RegexOption.IGNORE_CASE)
        /** "8", "20:30", "7.30pm", "8 o'clock". Not "15th": an ordinal is a day of the month. */
        private val TIME = Regex("""(?<![\d.:])(\d{1,2})(?:[.:](\d{2}))?\s*(am|pm|o'clock)?(?!\d|st|nd|rd|th)""", RegexOption.IGNORE_CASE)
        private val MONTHS = listOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")
        private val WEEKDAYS = DayOfWeek.values().map { it.getDisplayName(TextStyle.FULL, Locale.UK) }
        // Written by hand rather than by a locale: Java's UK locale prints "Sept", and the page prints "Sep".
        private val DOW = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        private val MON = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
        private fun dayOf(d: LocalDate): String = "${DOW[d.dayOfWeek.value - 1]} ${d.dayOfMonth} ${MON[d.monthValue - 1]}"

        /** The scorelines written in the text, as written: "5-3", "7–2". The model chooses among these or none. */
        public fun scorelines(text: String): List<String> = SCORE.findAll(text).map { it.value.trim() }.distinct().toList()

        /**
         * The times written in the text, as written: "8", "20:30", "7.30pm". A bare number that is part of a scoreline is
         * not a time, and a number over 24 is not one either.
         */
        public fun times(text: String): List<String> {
            val scores = SCORE.findAll(text).flatMap { m -> sequenceOf(m.range) }.toList()
            return TIME.findAll(text).filter { m -> scores.none { r -> m.range.first in r } }
                .filter { m -> m.groupValues[1].toInt() in 0..24 }
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
        val fixtures = desk.fixtures.sortedWith(compareBy<Fixture> { it.decided }.thenBy { it.at }).take(200)
        val fixtureKeys = fixtures.mapIndexed { i, f -> "f${i + 1}" to f }.toMap()
        val teamKeys = desk.teams.mapIndexed { i, t -> "t${i + 1}" to t }.toMap()
        val scores = scorelines(clean).mapIndexed { i, s -> "s${i + 1}" to s }.toMap()
        val times = times(clean).mapIndexed { i, s -> "h${i + 1}" to s }.toMap()

        val state = obj("text" to clean, "today" to "${today()} (${today().dayOfWeek.getDisplayName(TextStyle.FULL, Locale.UK)})",
                        "context" to "A darts league secretary's desk. The sentence is about this league season's fixtures: two teams, a date, and often a scoreline in legs.")
        val questions = obj(
            "act" to choice("What is the sentence asking the desk to do?", ACTS),
            "fixture" to choice("Which fixture is the sentence about? Match the teams it names; a team named first in the sentence may be either side of the fixture. If the sentence adds a new fixture or names none, choose none.",
                                fixtureKeys.mapValues { label(it.value) } + ("none" to "The sentence is about no fixture listed, or adds a new one")),
            "score" to choice("Which of these scorelines found in the text is the result — the legs each side won?",
                              scores.mapValues { "the scoreline written as '${it.value}'" } + ("none" to "No scoreline is stated, or none of these is one")),
            "first_number" to choice("The first number of the scoreline belongs to which side of the fixture chosen — the home side (named first in the fixture) or the away side? A scoreline usually follows the side the sentence names first.",
                                     mapOf("home" to "the home side's legs come first", "away" to "the away side's legs come first")),
            "winner" to choice("Which side does the sentence say won, if it says?", mapOf("home" to "the home side won", "away" to "the away side won", "none" to "the sentence does not say who won")),
            "award_to" to choice("If the fixture is awarded — a walkover, a forfeit, a team that did not turn up — which side does it go to?",
                                 mapOf("home" to "awarded to the home side", "away" to "awarded to the away side")),
            "home_team" to choice("For a new fixture: which team is the home side — named first, or said to be at home?", teamKeys.mapValues { it.value.name } + ("none" to "not stated")),
            "away_team" to choice("For a new fixture: which team is the away side — named second, or said to be away?", teamKeys.mapValues { it.value.name } + ("none" to "not stated")),
            "date_mode" to choice("How is the fixture's date written? 'absolute' names a month or a day of the month; 'relative' is given from today (today, tomorrow, a named weekday such as 'next Thursday'); 'none' when no date is stated.",
                                  mapOf("absolute" to null, "relative" to null, "none" to null)),
            "day_anchor" to choice("If the date is relative to today, which day is it?", mapOf("today" to null, "tomorrow" to null, "day_after" to "the day after tomorrow", "weekday" to "a named day of the week")),
            "weekday" to choice("If the date names a day of the week, which?", WEEKDAYS.associateWith { null } + ("none" to "no weekday named")),
            "week_offset" to choice("If the date names a weekday: 'this' means the coming one, 'next' means the one in the week after.", mapOf("this" to "this week, or the coming one", "next" to "next week")),
            "month" to choice("If the date is absolute, which month?", MONTHS.associateWith { null } + ("none" to "no month named; the day of the month alone, or none")),
            "day" to choice("If the date is absolute, which day of the month?", (1..31).associate { it.toString() to null } + ("none" to "no day of the month named")),
            "time" to choice("Which of these times found in the text is when the fixture is played?", times.mapValues { "the time written as '${it.value}'" } + ("none" to "no time stated")),
        )
        val answers = try { model.answers(state, questions) } catch (e: Exception) { null } ?: return null

        fun pick(id: String): Pair<String, Double>? {
            val a = answers[id] as? Map<*, *> ?: return null
            val option = a["choice"] as? String ?: return null
            val p = ((a["probabilities"] as? Map<*, *>)?.get(option) as? Number)?.toDouble() ?: (a["confidence"] as? Number)?.toDouble() ?: 0.0
            return option to p
        }
        fun distribution(id: String): Map<String, Double> =
            ((answers[id] as? Map<*, *>)?.get("probabilities") as? Map<*, *>)?.entries?.associate { (k, v) -> k.toString() to ((v as? Number)?.toDouble() ?: 0.0) } ?: emptyMap()

        val (act, actP) = pick("act") ?: return null
        val used = mutableListOf(actP)
        var doubt: String? = null

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
                    val (side, sideP) = pick("first_number") ?: ("home" to 0.5)
                    used += sideP
                    result = if (side == "home") Result(a, b) else Result(b, a)
                    val (winner, _) = pick("winner") ?: ("none" to 0.0)
                    if (winner != "none" && result.legsHome != result.legsAway && ((winner == "home") != (result.legsHome > result.legsAway))) {
                        doubt = "score"; used += 0.5
                    }
                }
                val say = if (fixture != null && result != null) "${fixture.home} ${result.legsHome}–${result.legsAway} ${fixture.away}, ${day(fixture.at)}"
                          else if (fixture != null) "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — which legs?" else "A result, but for which fixture?"
                Understood(clean, act, used.min(), doubt == null, say, doubt, fixture, result, null, null, null)
            }
            "award" -> {
                val fixture = fixturePicked()
                var award: Award? = null
                if (fixture == null) doubt = "fixture"
                else {
                    val (to, toP) = pick("award_to") ?: ("home" to 0.5)
                    used += toP
                    val f = desk.fixtures.first { it.fixtureId == fixture.fixtureId }
                    award = if (to == "home") Award(f.homeTeamId, f.home, clean) else Award(f.awayTeamId, f.away, clean)
                }
                val say = if (fixture != null && award != null) "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — awarded to ${award.toName}" else "An award, but for which fixture?"
                Understood(clean, act, used.min(), doubt == null, say, doubt, fixture, null, award, null, clean)
            }
            "void" -> {
                val fixture = fixturePicked()
                if (fixture == null) doubt = "fixture"
                val say = if (fixture != null) "${fixture.home} v ${fixture.away}, ${day(fixture.at)} — result annulled, to be replayed" else "An annulment, but of which fixture?"
                Understood(clean, act, used.min(), doubt == null, say, doubt, fixture, null, null, null, clean)
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
                Understood(clean, act, used.min(), doubt == null, say, doubt, null, null, null, schedule, null)
            }
            else -> Understood(clean, "none", actP, false, "That reads as a question or a note, not something THRØ can do from here. Try “Grange A beat Dolphin 5–3” or “Add Riverside A v Dolphin next Thursday at 8”.", null, null, null, null, null, null)
        }
    }

    /** The calendar, done by code from the parts the model read (the date-extraction cookbook's split). */
    private fun date(mode: Pair<String, Double>?, anchor: Pair<String, Double>?, weekday: Pair<String, Double>?, offset: Pair<String, Double>?,
                     month: Pair<String, Double>?, day: Pair<String, Double>?, used: MutableList<Double>): LocalDate? {
        val now = today()
        mode?.let { used += it.second }
        return when (mode?.first) {
            "relative" -> when (anchor?.first) {
                "today" -> now
                "tomorrow" -> now.plusDays(1)
                "day_after" -> now.plusDays(2)
                "weekday" -> {
                    val wd = weekday?.first?.let { name -> DayOfWeek.values().firstOrNull { it.getDisplayName(TextStyle.FULL, Locale.UK) == name } } ?: return null
                    weekday.let { used += it.second }
                    var d = now
                    while (d.dayOfWeek != wd) d = d.plusDays(1)
                    if (offset?.first == "next") { used += offset.second; d = d.plusWeeks(1) }
                    d
                }
                else -> null
            }
            "absolute" -> {
                val m = month?.first?.let { name -> MONTHS.indexOf(name) + 1 }?.takeIf { it > 0 } ?: return null
                val dd = day?.first?.toIntOrNull() ?: return null
                month.let { used += it.second }; day.let { used += it.second }
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
        if (suffix.isEmpty() && hour in 1..11) hour += 12
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
        return """{"text":${q(u.text)},"act":${q(u.act)},"confidence":${n(u.confidence)},"ready":${u.ready},"say":${q(u.say)},"doubt":${q(u.doubt)},""" +
            """"fixture":$fixture,"result":$result,"award":$award,"schedule":$schedule,"reason":${q(u.reason)}}"""
    }

    private fun choice(instructions: String, criteria: Map<String, String?>): String =
        obj("type" to "choice", "instructions" to instructions, "criteria" to obj(*criteria.entries.map { it.key to it.value }.toTypedArray()))
    private fun obj(vararg pairs: Pair<String, Any?>): String = pairs.joinToString(",", "{", "}") { (k, v) -> "${Contract.q(k)}:${json(v)}" }
    private fun json(v: Any?): String = when (v) {
        null -> "null"
        is Number, is Boolean -> v.toString()
        is String -> if (v.startsWith("{") || v.startsWith("[")) v else Contract.q(v)
        else -> Contract.q(v.toString())
    }
}
