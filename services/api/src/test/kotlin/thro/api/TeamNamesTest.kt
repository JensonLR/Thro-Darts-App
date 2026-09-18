package thro.api

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Matching a team by its name, in code (PD-158).
 *
 * This is the floor a model question has to beat. Eleven of the fourteen Jev proposals died because a normaliser
 * and an edit distance did the work; one judge reproduced a hand-written venue table 25 out of 25 with `difflib`
 * rather than argue about it. The same is true of team names, and the cases below are the ones real pub leagues
 * produce: a leading "The", a trailing side letter, "F.C" against "Football Club", a missing apostrophe.
 *
 * **The A/B rule is the whole reason this is not fuzzy-matching with a threshold.** Two names that share a
 * normalised stem and differ only in a trailing letter are DIFFERENT SIDES — Grange A is not Grange B — and that
 * is a regex, not a probability. A matcher that scores them as similar is worse than useless: it is confidently
 * wrong about the one distinction a league cares most about.
 */
class TeamNamesTest {

    @Test
    fun `a name is folded to what it has in common with how people write it`() {
        assertEquals("blue bell", TeamNames.fold("The Blue Bell"))
        assertEquals("blue bell", TeamNames.fold("blue  bell"))
        // "fc" carries no identity — a league writes it or leaves it out — so both forms land on the club itself.
        assertEquals("thornaby", TeamNames.fold("Thornaby F.C"))
        assertEquals("thornaby", TeamNames.fold("Thornaby Football Club"))
        assertEquals("ogradys", TeamNames.fold("O' Gradys"))
        assertEquals("ogradys", TeamNames.fold("O'Grady's"))
        assertEquals("station hotel", TeamNames.fold("STATION HOTEL"))
    }

    @Test
    fun `a side letter is kept apart from the name it hangs off`() {
        assertEquals("grange" to "a", TeamNames.stem("Grange A"))
        assertEquals("grange" to "b", TeamNames.stem("grange b"))
        assertEquals("riverside" to null, TeamNames.stem("Riverside"))
        assertEquals("bell" to "b", TeamNames.stem("The Bell B"))
    }

    @Test
    fun `two sides of one club are never the same team, however alike the names look`() {
        assertFalse(TeamNames.same("Grange A", "Grange B"), "the one distinction a league cares most about")
        assertFalse(TeamNames.same("Riverside A", "Riverside B"))
        assertTrue(TeamNames.same("Grange A", "grange a"))
        assertTrue(TeamNames.same("The Blue Bell", "Blue Bell"))
        assertTrue(TeamNames.same("Thornaby F.C", "Thornaby Football Club"))
    }

    @Test
    fun `a name a sentence shortens is still found in it`() {
        assertTrue(TeamNames.mentions("Grange lost 3-5 at Riverside", "Grange A"),
                   "a secretary drops the side letter constantly, and the sentence still names the club")
        assertTrue(TeamNames.mentions("the Crown and the Sun drew 4 each", "Crown"))
        assertTrue(TeamNames.mentions("station 5 riverside b 1", "Station Hotel"),
                   "one word of a two-word name, lower case, with no punctuation")
        assertTrue(TeamNames.mentions("station 5 riverside b 1", "Riverside B"))
        assertTrue(TeamNames.mentions("Sun Inn didn't turn up at the Crown", "Sun Inn"))
    }

    @Test
    fun `a name the sentence does not contain is not found in it`() {
        assertFalse(TeamNames.mentions("Riverside A beat Grange A 5-3", "Dolphin"))
        assertFalse(TeamNames.mentions("thanks Lee, see you Thursday", "Crown"))
        assertFalse(TeamNames.mentions("who's top of the table", "Station Hotel"))
        // The trap: a sentence about Riverside B must not count as naming Riverside A.
        assertFalse(TeamNames.mentions("station 5 riverside b 1", "Riverside A"),
                    "a side letter in the sentence pins which side it is")
    }

    @Test
    fun `a short word is not allowed to match on its own`() {
        // "Sun" appears inside "Sunday", and a league has a Sun Inn. A three-letter token matching loosely would
        // read "see you Sunday" as naming the Sun Inn.
        assertFalse(TeamNames.mentions("thanks Lee, see you Sunday", "Sun Inn"))
    }
}
