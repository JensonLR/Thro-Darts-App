package thro.client

import thro.engine.RejectionReason
import thro.engine.RuleTables
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/// The rules the Android screens obey (PD-083). None of these needs a device, and every one of them is a
/// sentence a player reads or a number they cannot type.
class WordsTest {

    // MARK: the keypad

    @Test
    fun `a visit is three digits at most`() {
        assertEquals("18", ThroScoringWords.typed("1", 8))
        assertEquals("180", ThroScoringWords.typed("18", 0))
        assertEquals("180", ThroScoringWords.typed("180", 1), "a fourth digit is refused, not truncated")
    }

    @Test
    fun `nothing above the engine's ceiling can be typed at all`() {
        // 180 is the most three darts make, and the engine says so. Stopping it at the keypad is the
        // difference between a control that cannot be misused and a rejection the player has to read.
        assertEquals(180, RuleTables.MAX_VISIT_TOTAL)
        assertEquals("18", ThroScoringWords.typed("18", 9), "189 never gets typed")
        assertEquals("9", ThroScoringWords.typed("", 9))
        assertEquals("99", ThroScoringWords.typed("9", 9))
    }

    @Test
    fun `a leading zero is replaced rather than kept`() {
        // "05" is not a number anybody means, and "0" then "5" is somebody correcting themselves.
        assertEquals("5", ThroScoringWords.typed("0", 5))
        assertEquals("0", ThroScoringWords.typed("", 0))
    }

    // MARK: refusals

    @Test
    fun `every refusal the engine can give has words a player can act on`() {
        // The enum's own name is true and useless: a person holding three darts needs to know what to type
        // instead. This walks every case, so a new reason in the engine fails here rather than reaching a
        // screen as "That cannot be scored".
        for (reason in RejectionReason.entries) {
            val said = ThroScoringWords.refused(reason)
            assertTrue(said.isNotBlank(), "$reason says nothing")
            assertFalse(said.contains("_"), "$reason leaks the enum: $said")
            assertFalse(said.uppercase() == said, "$reason is shouting an identifier: $said")
        }
    }

    @Test
    fun `not being in yet is told apart from an impossible total`() {
        // The engine keeps these distinct on purpose: 180 is a perfectly possible visit and cannot open a
        // double-in leg, so calling it impossible would be telling the player something false.
        assertTrue(ThroScoringWords.refused(RejectionReason.IMPOSSIBLE_VISIT_TOTAL) !=
                   ThroScoringWords.refused(RejectionReason.IMPOSSIBLE_OPENING_TOTAL))
    }

    // MARK: setting a match up

    @Test
    fun `both players must be named and they cannot be the same person`() {
        // The engine refuses a competitor playing itself with a `require`, which would crash rather than
        // explain. It never gets the chance.
        assertFalse(ThroSetupWords.ready("", "Ethan"))
        assertFalse(ThroSetupWords.ready("Jenson", "   "))
        assertFalse(ThroSetupWords.ready("Jenson", "jenson"), "the same name in a different case")
        assertTrue(ThroSetupWords.ready("Jenson", "Ethan"))
    }

    @Test
    fun `a name is trimmed because trailing spaces are nobody's name`() {
        assertEquals("Jenson", ThroSetupWords.tidy("  Jenson "))
    }
}
