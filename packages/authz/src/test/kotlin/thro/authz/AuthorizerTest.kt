package thro.authz

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The conflict-of-interest rule, and the properties around it.
 *
 * The scenario is not contrived. In darts the same people organise and play, so an official who is
 * also a competitor in the match they would be adjudicating is the ordinary case. ADR-008 chose a
 * relationship engine over role-based access control specifically because RBAC cannot express the
 * negation these tests exercise.
 */
class AuthorizerTest {

    private val org = ObjectRef(ObjectType.ORGANISATION, "org")
    private val event = ObjectRef(ObjectType.EVENT, "county-open")
    private val theirMatch = ObjectRef(ObjectType.MATCH, "m1")
    private val herMatch = ObjectRef(ObjectType.MATCH, "m2")
    private val board = ObjectRef(ObjectType.BOARD, "b3")
    private val team = ObjectRef(ObjectType.TEAM, "red-lion")

    private val dana = Subject("dana")     // tournament director, and also a competitor
    private val alice = Subject("alice")
    private val bob = Subject("bob")
    private val chalker = Subject("chalker")
    private val stranger = Subject("stranger")

    private val hierarchy = Hierarchy(
        mapOf(
            event to setOf(org),
            theirMatch to setOf(event, board),
            herMatch to setOf(event, board),
            team to setOf(event),
        ),
    )

    private val tuples = TupleSource { relation, obj ->
        when (relation to obj) {
            "official" to event -> setOf(dana)
            "organiser" to event -> setOf(dana)
            "scorer" to board -> setOf(chalker)
            // Dana is playing in her own match, m2, but not in m1.
            "participant" to theirMatch -> setOf(alice, bob)
            "participant" to herMatch -> setOf(dana, alice)
            else -> emptySet()
        }
    }

    private val authz = Authorizer(tuples, hierarchy, Rules.DEFAULT)

    // ------------------------------------------------------------------- the rule ADR-008 names

    @Test
    fun `an official may correct a match they are not playing in`() {
        val d = authz.check(dana, "match.correct", theirMatch)
        assertTrue(d.allowed, "the tournament director must be able to do their job")
        assertEquals("event:county-open#official", d.grantedBy)
        assertNull(d.excludedBy)
    }

    @Test
    fun `the same official may NOT correct the match they are playing in`() {
        // This is the whole reason ADR-008 rejected role-based access control. Dana's role has not
        // changed; the object has. A role column cannot see the difference.
        val d = authz.check(dana, "match.correct", herMatch)
        assertFalse(d.allowed, "an official corrected their own match")
        assertEquals("event:county-open#official", d.grantedBy, "the grant is still reported")
        assertEquals("match:m2#participant", d.excludedBy, "and so is the reason it was withdrawn")
    }

    @Test
    fun `the denial explains itself well enough to act on`() {
        val d = authz.check(dana, "match.correct", herMatch)
        assertNotNull(d.grantedBy)
        assertNotNull(d.excludedBy)
        // "You are an official here but you are also playing in this match" is the only useful
        // thing to tell someone; a bare 403 is not operable.
    }

    @Test
    fun `adjudicating carries the same exclusion as correcting`() {
        assertTrue(authz.check(dana, "match.adjudicate", theirMatch).allowed)
        assertFalse(authz.check(dana, "match.adjudicate", herMatch).allowed)
    }

    @Test
    fun `exclusion also reaches a competitor's team`() {
        // Dana is not listed on m1 herself, but her team is playing it. The exclusion must follow
        // the team, or the conflict is one indirection away from being invisible.
        val viaTeam = Hierarchy(hierarchy.parents + (theirMatch to setOf(event, board, team)))
        val withTeam = TupleSource { relation, obj ->
            if (relation == "member" && obj == team) setOf(dana) else tuples.subjectsWith(relation, obj)
        }
        val a = Authorizer(withTeam, viaTeam, Rules.DEFAULT)
        val d = a.check(dana, "match.correct", theirMatch)
        assertFalse(d.allowed, "the conflict was one indirection away and got through")
        assertEquals("team:red-lion#member", d.excludedBy)
    }

    @Test
    fun `the answer depends on the object, which is what RBAC cannot represent`() {
        // Same subject. Same action. Same role. Opposite answers. A role-based system stores the
        // permission against (subject, role) and has nowhere to put the difference, so it must
        // either let Dana correct her own match or stop her doing her job on everyone else's.
        val onOthers = authz.check(dana, "match.correct", theirMatch)
        val onOwn = authz.check(dana, "match.correct", herMatch)
        assertTrue(onOthers.allowed)
        assertFalse(onOwn.allowed)
        assertEquals(
            onOthers.grantedBy, onOwn.grantedBy,
            "the granting relation is identical — only the object differs",
        )
    }

    // ------------------------------------------------------------------------- deny by default

    @Test
    fun `an unknown action is denied, not allowed`() {
        assertFalse(authz.check(dana, "match.delete", theirMatch).allowed)
        assertFalse(authz.check(dana, "", theirMatch).allowed)
    }

    @Test
    fun `a stranger holds nothing anywhere`() {
        for (action in Rules.DEFAULT.keys) {
            for (obj in listOf(theirMatch, herMatch, event, board)) {
                assertFalse(
                    authz.check(stranger, action, obj).allowed,
                    "a stranger was allowed $action on $obj",
                )
            }
        }
    }

    @Test
    fun `there is no ambient administrator bypass`() {
        // Nothing in the model grants by virtue of being important. The organisation owner is a
        // subject with tuples like anyone else, and holds nothing they were not given.
        val owner = Subject("owner")
        val withOwner = TupleSource { relation, obj ->
            if (relation == "owner" && obj == org) setOf(owner) else tuples.subjectsWith(relation, obj)
        }
        val a = Authorizer(withOwner, hierarchy, Rules.DEFAULT)
        for (action in Rules.DEFAULT.keys) {
            assertFalse(a.check(owner, action, theirMatch).allowed, "owner bypassed $action")
        }
    }

    // -------------------------------------------------------------- permissions sit below events

    @Test
    fun `a scorer is assigned to a board, not to a competition`() {
        assertTrue(authz.check(chalker, "match.score", theirMatch).allowed)
        assertEquals("board:b3#scorer", authz.check(chalker, "match.score", theirMatch).grantedBy)
        // and that does not make them an official
        assertFalse(authz.check(chalker, "match.correct", theirMatch).allowed)
        assertFalse(authz.check(chalker, "event.manage", event).allowed)
    }

    @Test
    fun `a participant may score their own match and nobody else's`() {
        assertTrue(authz.check(alice, "match.score", theirMatch).allowed, "alice plays m1")
        assertTrue(authz.check(alice, "match.score", herMatch).allowed, "alice plays m2 too")
        assertFalse(authz.check(bob, "match.score", herMatch).allowed, "bob does not play m2")
    }

    @Test
    fun `attesting is a participant's act and an official cannot do it for them`() {
        // The point of a participant attestation is that the person who played it says so. An
        // organiser confirming on a player's behalf is a different fact and must not wear this name.
        assertTrue(authz.check(alice, "match.attest", theirMatch).allowed)
        assertFalse(authz.check(dana, "match.attest", theirMatch).allowed)
    }

    // --------------------------------------------------------------------------- graph hygiene

    @Test
    fun `inheritance reaches through more than one level`() {
        // Dana is an official on the event; the event hangs off the organisation. An official
        // appointed at organisation level must also reach the match.
        val atOrg = TupleSource { relation, obj ->
            if (relation == "official" && obj == org) setOf(bob) else tuples.subjectsWith(relation, obj)
        }
        val a = Authorizer(atOrg, hierarchy, Rules.DEFAULT)
        assertFalse(a.check(bob, "match.correct", theirMatch).allowed, "bob plays in m1")
        assertTrue(a.check(bob, "match.correct", herMatch).allowed, "but not in m2")
    }

    @Test
    fun `a cycle in the object graph terminates`() {
        val cyclic = Hierarchy(mapOf(event to setOf(theirMatch), theirMatch to setOf(event)))
        val a = Authorizer(tuples, cyclic, Rules.DEFAULT)
        // The assertion is simply that this returns at all.
        assertFalse(a.check(stranger, "match.correct", theirMatch).allowed)
    }

    @Test
    fun `an object with no parents grants nothing by inheritance`() {
        val orphan = ObjectRef(ObjectType.MATCH, "orphan")
        assertFalse(authz.check(dana, "match.correct", orphan).allowed)
    }
}
