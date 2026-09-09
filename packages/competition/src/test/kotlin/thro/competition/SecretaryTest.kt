package thro.competition

import java.time.Instant
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * The Secretary's pure rules. The property that matters most is the last test: there is no path
 * through the transition table by which THRØ alone can say a league acknowledged or accepted
 * anything.
 */
class SecretaryTest {

    @Test
    fun `a registration policy is parsed strictly - unknown requirements are refused, not ignored`() {
        val p = RegistrationPolicy.parse(mapOf("requires" to listOf("name", "age_band"), "deadline_days_before_first_fixture" to 7))
        assertEquals(setOf(RegistrationFact.NAME, RegistrationFact.AGE_BAND), p.requires)
        assertEquals(RegistrationDeadline.DaysBeforeFirstFixture(7), p.deadline)
        assertEquals(false, p.dualRegistrationPermitted)

        // A league that requires a passport photo has a rule THRØ cannot check. Passing it silently
        // would register a player the league would not have.
        assertFailsWith<IllegalArgumentException> { RegistrationPolicy.parse(mapOf("requires" to listOf("name", "photo"))) }
        assertFailsWith<IllegalArgumentException> { RegistrationPolicy.parse(mapOf("requires" to listOf("name"), "fee_paid" to true)) }
        assertFailsWith<IllegalArgumentException> {
            RegistrationPolicy.parse(mapOf("registration_closes_on" to "2026-09-30", "deadline_days_before_first_fixture" to 7))
        }
        assertEquals(RegistrationDeadline.On(LocalDate.of(2026, 9, 30)),
            RegistrationPolicy.parse(mapOf("registration_closes_on" to "2026-09-30")).deadline)
        assertEquals(RegistrationDeadline.None, RegistrationPolicy.parse(emptyMap()).deadline)
    }

    @Test
    fun `missing facts are exactly the required facts THRØ does not hold`() {
        val policy = RegistrationPolicy(setOf(RegistrationFact.NAME, RegistrationFact.AGE_BAND, RegistrationFact.CONSENT), RegistrationDeadline.None)
        val unclaimedTypedByCaptain = RegistrationFacts(hasName = true, ageBandKnown = false, accountClaimed = false, consentRecorded = false)
        assertEquals(setOf(RegistrationFact.AGE_BAND, RegistrationFact.CONSENT), unclaimedTypedByCaptain.missing(policy))
        val complete = RegistrationFacts(hasName = true, ageBandKnown = true, accountClaimed = true, consentRecorded = true)
        assertEquals(emptySet(), complete.missing(policy))
        // A policy that requires nothing is missing nothing, whatever THRØ knows.
        assertEquals(emptySet(), unclaimedTypedByCaptain.missing(RegistrationPolicy(emptySet(), RegistrationDeadline.None)))
    }

    @Test
    fun `the inbox headings follow state and deadline`() {
        val now = Instant.parse("2026-09-10T12:00:00Z")
        val eod = Instant.parse("2026-09-10T23:59:59Z")
        assertEquals(InboxSection.ACTION_REQUIRED, Inbox.sectionOf(TaskState.OPEN, now.minusSeconds(60), now, eod))
        assertEquals(InboxSection.DUE_TODAY, Inbox.sectionOf(TaskState.OPEN, eod.minusSeconds(60), now, eod))
        assertEquals(InboxSection.UPCOMING, Inbox.sectionOf(TaskState.OPEN, eod.plusSeconds(60), now, eod))
        assertEquals(InboxSection.UPCOMING, Inbox.sectionOf(TaskState.OPEN, null, now, eod))
        assertEquals(InboxSection.WAITING_FOR_LEAGUE, Inbox.sectionOf(TaskState.WAITING_LEAGUE, now.minusSeconds(60), now, eod))
        assertEquals(InboxSection.WAITING_FOR_OPPONENT, Inbox.sectionOf(TaskState.WAITING_OPPONENT, null, now, eod))
        assertEquals(InboxSection.WAITING_FOR_PLAYER, Inbox.sectionOf(TaskState.WAITING_PLAYER, null, now, eod))
        assertEquals(InboxSection.COMPLETED, Inbox.sectionOf(TaskState.DONE, null, now, eod))
        assertEquals(InboxSection.COMPLETED, Inbox.sectionOf(TaskState.CANCELLED, now.minusSeconds(60), now, eod))
    }

    @Test
    fun `every transition demands the evidence its kind requires`() {
        val t = SubmissionTransitions
        assertEquals(SubmissionTransitions.Verdict.Permitted, t.check(SubmissionState.DRAFT, SubmissionState.READY, null, actorNamed = false))
        assertTrue(t.check(SubmissionState.READY, SubmissionState.SUBMITTED, null, actorNamed = false) is SubmissionTransitions.Verdict.Refused)
        assertEquals(SubmissionTransitions.Verdict.Permitted, t.check(SubmissionState.READY, SubmissionState.SUBMITTED, null, actorNamed = true))
        // Delivered needs transport evidence; "we sent it" is not evidence.
        assertTrue(t.check(SubmissionState.SUBMITTED, SubmissionState.DELIVERED, null, actorNamed = false) is SubmissionTransitions.Verdict.Refused)
        assertEquals(SubmissionTransitions.Verdict.Permitted, t.check(SubmissionState.SUBMITTED, SubmissionState.DELIVERED, EvidenceKind.MESSAGE_ID, actorNamed = false))
        // Acknowledged needs the counterparty, named. A message id proves delivery, not reading.
        assertTrue(t.check(SubmissionState.DELIVERED, SubmissionState.ACKNOWLEDGED, EvidenceKind.MESSAGE_ID, actorNamed = true) is SubmissionTransitions.Verdict.Refused)
        assertTrue(t.check(SubmissionState.DELIVERED, SubmissionState.ACKNOWLEDGED, EvidenceKind.COUNTERPARTY_MESSAGE, actorNamed = false) is SubmissionTransitions.Verdict.Refused)
        assertEquals(SubmissionTransitions.Verdict.Permitted, t.check(SubmissionState.DELIVERED, SubmissionState.ACKNOWLEDGED, EvidenceKind.COUNTERPARTY_MESSAGE, actorNamed = true))
        // No skipping: submitted cannot become accepted.
        assertTrue(t.check(SubmissionState.SUBMITTED, SubmissionState.ACCEPTED, EvidenceKind.COUNTERPARTY_MESSAGE, actorNamed = true) is SubmissionTransitions.Verdict.Refused)
        // Action required goes back to ready, by the submitter.
        assertEquals(SubmissionTransitions.Verdict.Permitted, t.check(SubmissionState.ACTION_REQUIRED, SubmissionState.READY, null, actorNamed = true))
        // Terminal states do not move.
        for (terminal in listOf(SubmissionState.ACCEPTED, SubmissionState.REJECTED, SubmissionState.WITHDRAWN)) {
            for (to in SubmissionState.entries) {
                assertTrue(t.check(terminal, to, EvidenceKind.HUMAN_CONFIRMATION, actorNamed = true) is SubmissionTransitions.Verdict.Refused,
                    "$terminal must not move to $to")
            }
        }
    }

    @Test
    fun `THRØ alone can never take a submission to acknowledged, accepted, rejected or action required`() {
        // Exhaustive over the table: every rule landing in one of those states requires a named
        // actor and counterparty evidence, and is moved by the counterparty, never by THRØ.
        for (rule in SubmissionTransitions.RULES) {
            if (rule.to in SubmissionTransitions.NEVER_BY_THRO) {
                assertTrue(rule.actorRequired, "${rule.to} without a named actor")
                assertEquals(Mover.COUNTERPARTY, rule.mover, "${rule.to} moved by ${rule.mover}")
                assertTrue(rule.evidence.isNotEmpty(), "${rule.to} without evidence")
            }
            if (rule.mover == Mover.THRO) {
                assertTrue(rule.to !in SubmissionTransitions.NEVER_BY_THRO)
            }
        }
        // And there is no rule at all that lands in those states from a state THRØ controls alone.
        for (from in listOf(SubmissionState.DRAFT, SubmissionState.READY, SubmissionState.SUBMITTED)) {
            for (to in SubmissionTransitions.NEVER_BY_THRO) {
                assertTrue(SubmissionTransitions.check(from, to, EvidenceKind.API_RESPONSE, actorNamed = true) is SubmissionTransitions.Verdict.Refused,
                    "$from -> $to must not exist")
            }
        }
    }
}
