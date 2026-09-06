package thro.authz

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Age as an authorization dimension.
 *
 * These test the *dimension*, not a policy. OD-010 is open — the thresholds, the evidence that
 * establishes them, and what each unlocks must be researched against primary sources. What is
 * asserted here is that the dimension exists at every decision, that an unknown band is treated as
 * the most restrictive case, and that attaching a requirement later needs no change at any call
 * site. That last property is the retrofit ADR-008 is trying to avoid.
 */
class AgeTest {

    private val event = ObjectRef(ObjectType.EVENT, "e")
    private val match = ObjectRef(ObjectType.MATCH, "m")
    private val dana = Subject("dana")
    private val hierarchy = Hierarchy(mapOf(match to setOf(event)))
    private val tuples = TupleSource { relation, obj ->
        if (relation == "official" && obj == event) setOf(dana) else emptySet()
    }

    @Test
    fun `no action carries an age requirement by default`() {
        // Inventing restrictions while OD-010 is open would be as wrong as omitting the dimension,
        // in the opposite direction. The default is that nothing is age-gated.
        val a = Authorizer(tuples, hierarchy, Rules.DEFAULT)
        assertTrue(a.check(dana, "match.correct", match).allowed)
        assertTrue(
            a.check(dana, "match.correct", match, SubjectAttributes(AgeBand.UNKNOWN)).allowed,
            "an unknown band was gated by a rule nobody wrote",
        )
    }

    @Test
    fun `attaching a requirement later changes no call site`() {
        // This is the retrofit ADR-008 exists to avoid. The same call, unchanged, becomes
        // age-aware purely by configuring the authorizer.
        val gated = Authorizer(
            tuples, hierarchy, Rules.DEFAULT,
            ageRequirements = mapOf("match.correct" to AgeRequirement.adultsOnly()),
        )
        val adult = SubjectAttributes(AgeBand.ADULT, AgeAssurance.VERIFIED)
        assertTrue(gated.check(dana, "match.correct", match, adult).allowed)
        assertFalse(gated.check(dana, "match.correct", match, SubjectAttributes(AgeBand.MINOR)).allowed)
    }

    @Test
    fun `an unknown band is the most restrictive case, not a permissive one`() {
        val gated = Authorizer(
            tuples, hierarchy, Rules.DEFAULT,
            ageRequirements = mapOf("match.correct" to AgeRequirement.adultsOnly()),
        )
        val d = gated.check(dana, "match.correct", match, SubjectAttributes(AgeBand.UNKNOWN))
        assertFalse(d.allowed, "not knowing whether someone is a child must not read as adult")
        assertEquals("age:unknown", d.excludedBy)
    }

    @Test
    fun `assurance is evidence quality and can be required separately from the band`() {
        val requiresVerified = AgeRequirement.adultsOnly(minimumAssurance = AgeAssurance.VERIFIED)
        assertFalse(
            requiresVerified.isSatisfiedBy(SubjectAttributes(AgeBand.ADULT, AgeAssurance.SELF_DECLARED)),
            "a self-declared adult satisfied a rule that asked for verification",
        )
        assertTrue(requiresVerified.isSatisfiedBy(SubjectAttributes(AgeBand.ADULT, AgeAssurance.VERIFIED)))

        // And a rule that does not ask for verification is satisfied by a self-declaration.
        val declaredIsEnough = AgeRequirement(setOf(AgeBand.ADULT))
        assertTrue(declaredIsEnough.isSatisfiedBy(SubjectAttributes(AgeBand.ADULT, AgeAssurance.SELF_DECLARED)))
    }

    @Test
    fun `an age requirement never grants what a relation withheld`() {
        // Age is a further restriction, never a substitute for a relationship. A verified adult
        // with no relation to the event still cannot correct its matches.
        val gated = Authorizer(
            tuples, hierarchy, Rules.DEFAULT,
            ageRequirements = mapOf("match.correct" to AgeRequirement.adultsOnly()),
        )
        val stranger = Subject("stranger")
        assertFalse(
            gated.check(stranger, "match.correct", match, SubjectAttributes(AgeBand.ADULT, AgeAssurance.VERIFIED)).allowed,
        )
    }

    @Test
    fun `every band is handled, so adding one is a compile error rather than a silent gap`() {
        val requirement = AgeRequirement.adultsOnly(AgeAssurance.NONE)
        val results = AgeBand.entries.associateWith {
            requirement.isSatisfiedBy(SubjectAttributes(it, AgeAssurance.VERIFIED))
        }
        assertEquals(3, results.size, "a band was added without this test noticing")
        assertEquals(mapOf(AgeBand.UNKNOWN to false, AgeBand.MINOR to false, AgeBand.ADULT to true), results)
    }
}
