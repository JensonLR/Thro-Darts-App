package thro.api

import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import thro.competition.Entrant
import thro.competition.EntrantKind
import thro.competition.EventAccess
import thro.competition.MembershipRole
import thro.competition.Requirement

/**
 * "Show me darts I can play" — and why each card is there.
 *
 * The properties are about honesty rather than ranking: an event appears with reasons that are
 * facts; a gated event is called eligible only when its organiser stated the requirement in terms
 * THRØ can check and the store says the player meets it, and otherwise says which rule stands in
 * the way or that none was stated; a capacity the organiser did not state is "not stated", never
 * "unlimited"; an event the player has entered is not offered again; and a series the player
 * already plays in surfaces its other legs.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class DiscoveryTest {

    @Test
    fun `every card explains itself, and nothing is called eligible that THRØ cannot check`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — discovery tests skipped")
            return
        }
        val c = TestDatabase.migrated()
        val orgs = Organisations(c)
        val comp = Competitions(c)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        // Friday 11 September 2026, evening. The weekend is the 12th and 13th.
        val now = Instant.parse("2026-09-11T18:00:00Z")
        val sam = orgs.createPlayer()
        val riverside = orgs.createTeam("Riverside A", "Stockton")
        orgs.addMember(riverside, sam, MembershipRole.PLAYER, from = now.minus(30, ChronoUnit.DAYS))
        val stockton = orgs.createVenue("Riverside Club", "Stockton")
        val durham = orgs.createVenue("Durham WMC", "Durham")
        val tour = orgs.createSeries("North East Tour")
        val tour2026 = orgs.openSeriesSeason(tour, "2026", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))

        fun event(name: String, at: Instant, venue: UUID?, access: EventAccess = EventAccess.OPEN, kind: EntrantKind = EntrantKind.PLAYER,
                  closes: Instant? = null, capacity: Int? = null): UUID {
            val id = UUID.randomUUID()
            comp.openEvent(id, name, at, at.plus(8, ChronoUnit.HOURS), venueId = venue, entrantKind = kind, access = access,
                entriesCloseAt = closes, capacity = capacity)
            return id
        }
        val weekendOpen = event("Stockton Saturday Open", Instant.parse("2026-09-12T11:00:00Z"), stockton, closes = Instant.parse("2026-09-12T10:00:00Z"), capacity = 64)
        val durhamNextMonth = event("Durham Open", Instant.parse("2026-10-10T11:00:00Z"), durham, capacity = 32)
        val invitational = event("Champions Invitational", Instant.parse("2026-09-19T11:00:00Z"), stockton, access = EventAccess.INVITATIONAL)
        val memberOnly = event("Members' Night", Instant.parse("2026-09-13T18:00:00Z"), stockton, access = EventAccess.MEMBER_ONLY)
        val pairs = event("Sunday Pairs", Instant.parse("2026-09-13T12:00:00Z"), stockton, kind = EntrantKind.PAIR)
        val full = event("Full House Open", Instant.parse("2026-09-26T11:00:00Z"), stockton, capacity = 1)
        val tourLeg1 = event("Tour Leg 1", Instant.parse("2026-09-05T11:00:00Z"), durham)     // already happened; Sam played it
        val tourLeg2 = event("Tour Leg 2", Instant.parse("2026-10-24T11:00:00Z"), durham)
        val entered = event("Grange Open", Instant.parse("2026-09-20T11:00:00Z"), stockton)
        orgs.linkEventToSeries(tour2026, tourLeg1, 1); orgs.linkEventToSeries(tour2026, tourLeg2, 2)
        comp.enter(tourLeg1, sam); comp.enter(entered, sam)
        comp.enter(full, orgs.createPlayer())   // the one place is taken

        // V019: what the gated events require, in terms THRØ can check.
        val organiser = UUID.randomUUID()
        val grange = orgs.createTeam("Grange B", "Stockton")
        val othersOnly = event("Grange Members' Night", Instant.parse("2026-09-27T18:00:00Z"), stockton, access = EventAccess.MEMBER_ONLY)
        val qualified = event("Tour Finals", Instant.parse("2026-11-07T11:00:00Z"), durham, access = EventAccess.QUALIFIED)
        val adultsOnly = event("Late Licence Open", Instant.parse("2026-10-03T20:00:00Z"), stockton, access = EventAccess.RESTRICTED)
        val unstated = event("Committee Cup", Instant.parse("2026-10-17T11:00:00Z"), stockton, access = EventAccess.RESTRICTED)
        val invitedTo = event("Captains' Invitational", Instant.parse("2026-10-31T11:00:00Z"), stockton, access = EventAccess.INVITATIONAL)
        val memberAndAdult = event("Members' Late Night", Instant.parse("2026-10-04T20:00:00Z"), stockton, access = EventAccess.RESTRICTED)
        orgs.requireForEntry(memberOnly, 1, Requirement.TeamMember(riverside.toString()), organiser)
        orgs.requireForEntry(memberOnly, 1, Requirement.TeamMember(grange.toString()), organiser)         // A side or B side
        val wrongTeam = orgs.requireForEntry(othersOnly, 1, Requirement.TeamMember(grange.toString()), organiser)
        orgs.requireForEntry(qualified, 1, Requirement.EnteredEvent(tourLeg1.toString()), organiser)
        orgs.requireForEntry(adultsOnly, 1, Requirement.AgeBand("adult"), organiser)
        orgs.requireForEntry(invitedTo, 1, Requirement.Invited(sam.toString()), organiser)
        orgs.requireForEntry(memberAndAdult, 1, Requirement.TeamMember(riverside.toString()), organiser)
        orgs.requireForEntry(memberAndAdult, 2, Requirement.AgeBand("adult"), organiser)
        val openRefused = try { orgs.requireForEntry(weekendOpen, 1, Requirement.Invited(sam.toString()), organiser); false }
            catch (e: org.postgresql.util.PSQLException) { e.message!!.contains("open event states no eligibility requirement") }

        val d = Discovery(c).forPlayer(sam, from = now, to = now.plus(60, ChronoUnit.DAYS), homeLocality = "Stockton")
        val all = d[Discovery.Section.ALL].orEmpty()
        fun card(id: UUID) = all.single { it.eventId == id }
        fun ids(s: Discovery.Section) = d[s].orEmpty().map { it.eventId }.toSet()

        check("a past event is not offered", all.none { it.eventId == tourLeg1 })
        check("every card carries at least a date, a kind and an access reason", all.all { it.reasons.size >= 3 })
        check("this weekend is Saturday and Sunday, not Friday night's view of the week", ids(Discovery.Section.THIS_WEEKEND) == setOf(weekendOpen, memberOnly, pairs))
        check("near you is the locality where the team plays, from venues, not from the person", ids(Discovery.Section.NEAR_YOU).containsAll(setOf(weekendOpen, invitational, pairs)) && durhamNextMonth !in ids(Discovery.Section.NEAR_YOU))
        check("closing soon is a stated closing date within a week", ids(Discovery.Section.CLOSING_SOON) == setOf(weekendOpen))
        check("an unstated closing date is said to be unstated", card(durhamNextMonth).reasons.contains("closing date not stated by the organiser"))
        check("eligible means open entry or a stated requirement met, singles, still open to entries, with a place if a capacity was stated",
            ids(Discovery.Section.YOU_ARE_ELIGIBLE) == setOf(weekendOpen, durhamNextMonth, tourLeg2, memberOnly, qualified, invitedTo))
        check("an invitational with no invitation stated is never called eligible, and says so",
            invitational !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(invitational).reasons.contains("by invitation — requirement not stated in terms THRØ can check"))
        check("an invitation by name is a requirement THRØ can check", card(invitedTo).reasons.contains("by invitation — you qualify: invited by name"))
        check("a member-only event names the membership that was met — either side of the club",
            card(memberOnly).reasons.contains("member_only entry — you qualify: member of Riverside A"))
        check("a member-only event for another team names the membership that is missing, and is not called eligible",
            othersOnly !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(othersOnly).reasons.contains("member_only entry — requires membership of Grange B"))
        check("a qualifier entered is a qualification THRØ can check", card(qualified).reasons.contains("qualified entry — you qualify: entered Tour Leg 1"))
        check("an unclaimed player's age band is unknown, and unknown satisfies no age requirement",
            adultsOnly !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(adultsOnly).reasons.contains("restricted entry — requires a claimed account whose age band is adult"))
        check("a restricted event whose organiser stated nothing THRØ can check is said to be so, never eligible",
            unstated !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(unstated).reasons.contains("restricted entry — requirement not stated in terms THRØ can check"))
        check("every group must hold: a member who cannot show an age band is not eligible, and the card names the unmet group",
            memberAndAdult !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(memberAndAdult).reasons.contains("restricted entry — requires a claimed account whose age band is adult"))
        check("an open event refuses a requirement: open means open", openRefused)
        check("the store's own answer agrees with the card", orgs.satisfiesEvent(sam, memberOnly, now) == true && orgs.satisfiesEvent(sam, othersOnly, now) == false && orgs.satisfiesEvent(sam, unstated, now) == null)
        orgs.withdrawRequirement(wrongTeam, organiser, "stated on the wrong team")
        val after = Discovery(c).forPlayer(sam, from = now, to = now.plus(60, ChronoUnit.DAYS), homeLocality = "Stockton")[Discovery.Section.ALL].orEmpty().single { it.eventId == othersOnly }
        check("a withdrawn requirement leaves the event with none stated — not with the player eligible",
            after.reasons.contains("member_only entry — requirement not stated in terms THRØ can check") && !after.qualifies)
        check("a pairs event is not offered as something a player enters alone", pairs !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(pairs).reasons.contains("pairs"))
        check("a full event is not called eligible, and says it has no places", full !in ids(Discovery.Section.YOU_ARE_ELIGIBLE) && card(full).spotsRemaining == 0)
        check("an unstated capacity is null — not stated, never unlimited", card(invitational).spotsRemaining == null && card(invitational).reasons.contains("capacity not stated by the organiser"))
        check("places remaining are counted from live entries", card(weekendOpen).spotsRemaining == 64)
        check("a series the player already plays in surfaces its other legs, and says why",
            ids(Discovery.Section.YOUR_SERIES) == setOf(tourLeg2) && card(tourLeg2).reasons.contains("part of a series you play in") && card(tourLeg2).seriesLabels == listOf("North East Tour 2026"))
        check("an event already entered is shown as entered, and offered in no other section",
            ids(Discovery.Section.ALREADY_ENTERED) == setOf(entered) && Discovery.Section.entries.filter { it != Discovery.Section.ALL && it != Discovery.Section.ALREADY_ENTERED }.none { entered in ids(it) })
        check("nothing about the player's location was read: the locality came from the team's venue", card(weekendOpen).reasons.contains("in Stockton, where your team plays"))

        println("  $passed discovery properties held")
        assertEquals(25, passed)
    }
}
