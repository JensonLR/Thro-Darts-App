package thro.engine

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Conformance: the engine must reproduce the generated corpus exactly.
 *
 * This is the contract that lets ADR-002 leave the shared-code question open. Whatever
 * implementation strategy is chosen later, it is proved correct by passing this — so the corpus is
 * never wasted work, and an implementation that has not passed it is not an implementation.
 */
class ConformanceTest {

    private val vectors: File = generateSequence(File(".").absoluteFile) { it.parentFile }
        .map { File(it, "packages/domain-spec/vectors") }
        .firstOrNull { it.isDirectory }
        ?: File("../domain-spec/vectors")

    @Test
    fun `engine reproduces every conformance vector`() {
        assertTrue(vectors.isDirectory, "corpus not found at ${vectors.absolutePath}")
        val files = vectors.listFiles { f -> f.extension == "jsonl" }?.sortedBy { it.name }.orEmpty()
        assertTrue(files.isNotEmpty(), "no vector files found")

        var cases = 0
        var commands = 0
        val failures = mutableListOf<String>()

        for (file in files) {
            file.forEachLine { line ->
                if (line.isNotBlank()) {
                    cases++
                    commands += runCase(parseJson(line).obj(), failures)
                }
            }
        }

        println("conformance: $cases cases, $commands commands, across ${files.size} vector files")
        if (failures.isNotEmpty()) {
            fail("${failures.size} conformance failures:\n  " + failures.take(20).joinToString("\n  "))
        }
    }

    private fun runCase(case: Map<String, J>, failures: MutableList<String>): Int {
        val id = case.getValue("id").str()
        val setup = case.getValue("setup").obj()
        val format = format(setup.getValue("format").obj())
        val players = setup.getValue("players").arr().map { PlayerId(it.obj().getValue("id").str()) }

        var state = MatchState.start(format, players[0], players[1])
        val cmds = case.getValue("commands").arr()
        val expected = case.getValue("expect").obj().getValue("outcomes").arr()

        for ((i, c) in cmds.withIndex()) {
            val cmd = c.obj()
            val exp = expected[i].obj()
            val outcome = Engine.apply(
                state,
                Command.RecordVisit(
                    player = PlayerId(cmd.getValue("player").str()),
                    visitTotal = cmd.getValue("visitTotal").int(),
                    dartsUsed = cmd.opt("dartsUsed")?.int(),
                ),
            )
            val seq = cmd.getValue("seq").int()
            when (outcome) {
                is Outcome.Rejected -> {
                    val want = exp.getValue("result").str()
                    if (want != "rejected") {
                        failures += "$id seq$seq: engine rejected (${outcome.reason}) but corpus expects $want"
                    } else {
                        val wantReason = exp.opt("reason")?.str()
                        if (wantReason != null && wantReason != outcome.reason.name) {
                            failures += "$id seq$seq: rejection reason ${outcome.reason} != $wantReason"
                        }
                    }
                }
                is Outcome.Accepted -> {
                    val want = exp.getValue("result").str()
                    if (want != "accepted") {
                        failures += "$id seq$seq: engine accepted (${outcome.effect}) but corpus expects $want"
                    } else {
                        val wantEffect = exp.opt("effect")?.str()
                        if (wantEffect != null && wantEffect != effectName(outcome.effect)) {
                            failures += "$id seq$seq: effect ${effectName(outcome.effect)} != $wantEffect"
                        }
                        val wantReason = exp.opt("reason")?.str()
                        if (wantReason != null && wantReason != outcome.bustReason?.name) {
                            failures += "$id seq$seq: bust reason ${outcome.bustReason} != $wantReason"
                        }
                    }
                    state = outcome.state
                }
            }
        }

        // Final state, which catches drift the per-command outcomes would not.
        val ws = case.getValue("expect").obj().getValue("state").obj()
        val wantRemaining = ws.getValue("remaining").obj()
        for ((p, v) in wantRemaining) {
            val got = state.remaining.getValue(PlayerId(p))
            if (got != v.int()) failures += "$id: remaining[$p] $got != ${v.int()}"
        }
        val wantLegs = ws.getValue("legsWon").obj()
        for ((p, v) in wantLegs) {
            val got = state.legsWonTotal.getValue(PlayerId(p))
            if (got != v.int()) failures += "$id: legsWon[$p] $got != ${v.int()}"
        }
        val wantWinner = ws.opt("winnerId")?.str()
        if (wantWinner != state.winner?.value) {
            failures += "$id: winner ${state.winner?.value} != $wantWinner"
        }
        val wantThrower = ws.opt("throwerId")?.str()
        if (wantThrower != null && wantThrower != state.thrower?.value) {
            failures += "$id: thrower ${state.thrower?.value} != $wantThrower"
        }
        val wantLeg = ws.opt("currentLeg")?.int()
        if (wantLeg != null && wantLeg != state.currentLeg) {
            failures += "$id: currentLeg ${state.currentLeg} != $wantLeg"
        }
        return cmds.size
    }

    private fun effectName(e: Effect): String = when (e) {
        Effect.SCORED -> "scored"
        Effect.BUST -> "bust"
        Effect.LEG_WON -> "leg_won"
        Effect.SET_WON -> "set_won"
        Effect.MATCH_WON -> "match_won"
    }

    private fun format(f: Map<String, J>): MatchFormat {
        val structure = f.getValue("structure").obj()
        val legs = Structure(
            mode = if (structure.containsKey("firstTo")) StructureMode.FIRST_TO else StructureMode.BEST_OF,
            target = (structure.opt("firstTo") ?: structure.getValue("bestOf")).int(),
        )
        return MatchFormat(
            startingScore = f.getValue("startingScore").int(),
            inRule = when (f.getValue("inRule").str()) {
                "double" -> InRule.DOUBLE
                "master" -> InRule.MASTER
                else -> InRule.STRAIGHT
            },
            outRule = when (f.getValue("outRule").str()) {
                "master" -> OutRule.MASTER
                "straight" -> OutRule.STRAIGHT
                else -> OutRule.DOUBLE
            },
            legs = legs,
            throwFirst = PlayerId(f.getValue("throwFirst").str()),
            alternation = if (f.opt("alternateStart")?.str() == "perSet") Alternation.PER_SET
                          else Alternation.PER_LEG,
        )
    }

    @Test
    fun `rule tables match the generated spec version`() {
        assertEquals("1.1.0", RuleTables.SPEC_VERSION)
        assertEquals(180, RuleTables.MAX_VISIT_TOTAL)
        assertEquals(170, RuleTables.checkouts(OutRule.DOUBLE).max())
        assertEquals(180, RuleTables.checkouts(OutRule.MASTER).max())
        assertEquals(21, RuleTables.ONE_DART_FINISHES_DOUBLE.size)
    }
}
