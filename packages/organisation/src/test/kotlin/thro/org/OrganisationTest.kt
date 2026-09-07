package thro.org

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OrganisationTest {

    private fun member(role: OrgRole, band: AgeBand = AgeBand.ADULT, id: String = "p", org: String = "o") =
        Membership(OrganisationId(org), PersonId(id), role, band)

    // ---------------------------------------------------------------- authority

    /**
     * The whole authority surface of an organisation, asserted as a table rather than as examples,
     * so an action added without a decision about who owns it fails here rather than shipping open.
     */
    @Test
    fun `every role and action pair is decided, and a stranger may do nothing`() {
        val expected = mapOf(
            OrgRole.MEMBER to setOf(OrgAction.VIEW, OrgAction.VIEW_MEMBERS),
            OrgRole.OFFICIAL to setOf(
                OrgAction.VIEW, OrgAction.VIEW_MEMBERS, OrgAction.ANNOUNCE, OrgAction.MANAGE_FIXTURES,
            ),
            OrgRole.ADMIN to OrgAction.entries.toSet(),
        )
        for (role in OrgRole.entries) {
            for (action in OrgAction.entries) {
                assertEquals(action in expected.getValue(role), Permissions.may(role, action),
                             "$role and $action")
            }
        }
        // A public front and a private inside (PD-009): a stranger may open the page and nothing else.
        assertTrue(Permissions.may(null, OrgAction.VIEW), "a club's front is public")
        for (action in OrgAction.entries - OrgAction.VIEW) {
            assertFalse(Permissions.may(null, action), "a stranger may not $action")
        }
        // A member cannot announce, and an official cannot change who is a member. Both are the
        // separations that matter, so they are named as well as covered by the table.
        assertFalse(Permissions.may(member(OrgRole.MEMBER), OrgAction.ANNOUNCE))
        assertFalse(Permissions.may(member(OrgRole.OFFICIAL), OrgAction.MANAGE_MEMBERS))
        assertTrue(Permissions.may(member(OrgRole.ADMIN), OrgAction.MANAGE_MEMBERS))
    }

    /**
     * A member recorded as a minor, or whose age is not established, is listed only to an admin
     * (PD-009). A function rather than a convention, so a caller cannot render the list without it.
     */
    @Test
    fun `a minor is never listed to anyone but an admin, and a stranger sees no list at all`() {
        val members = listOf(
            member(OrgRole.MEMBER, AgeBand.ADULT, "adult"),
            member(OrgRole.OFFICIAL, AgeBand.MINOR, "junior"),
            member(OrgRole.MEMBER, AgeBand.UNKNOWN, "unstated"),
        )
        assertEquals(emptyList(), Permissions.visibleMembers(null, members), "a stranger sees no list")
        assertEquals(
            listOf(PersonId("adult")),
            Permissions.visibleMembers(member(OrgRole.MEMBER), members).map { it.person },
            "a member sees the adults",
        )
        assertEquals(
            listOf(PersonId("adult")),
            Permissions.visibleMembers(member(OrgRole.OFFICIAL), members).map { it.person },
            "and so does an official: running a club is not a reason to see a child's name",
        )
        assertEquals(members, Permissions.visibleMembers(member(OrgRole.ADMIN), members),
                     "an admin sees everybody, because somebody has to")
    }

    // ---------------------------------------------------------------- branding

    /**
     * The palette this package measures against is the generated token layer's, and this reads the
     * generated file to prove it. A hardcoded copy that drifts would make every ratio below a
     * confident measurement of the wrong thing — which is worse than not measuring.
     */
    @Test
    fun `the palette is the generated token layer's, read from the generated file`() {
        val tokens = generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "packages/design-tokens/generated/ThroTokens.kt") }
            .firstOrNull { it.isFile }
        assertNotNull(tokens, "the generated token file must be findable from the test's working directory")
        val text = tokens.readText()
        // The light theme is the first block, so the first match of each name is its light value.
        fun light(name: String): String {
            val m = Regex("""$name = Color\(0xFF([0-9A-Fa-f]{6})\)""").find(text)
            assertNotNull(m, "$name is not in the generated tokens")
            return "#" + m.groupValues[1].uppercase()
        }
        assertEquals(light("colorTextPrimary"), Palette.ink.hex)
        assertEquals(light("colorTextInverse"), Palette.chalk.hex)
        assertEquals(light("colorBackgroundPrimary"), Palette.surfaceLight.hex)
        assertEquals(light("throGreen"), Palette.brandGreen.hex)
        // The dark theme's background is the light theme's ink, which is why one value serves both.
        assertEquals(Palette.ink.hex, Palette.surfaceDark.hex)
    }

    @Test
    fun `contrast agrees with the published ratios, and a colour is six hex digits or nothing`() {
        // White on black is 21:1; a colour against itself is 1:1. Both are definitional.
        assertEquals(21.0, Contrast.ratio(Colour.of("#FFFFFF"), Colour.of("#000000")), 1e-9)
        assertEquals(1.0, Contrast.ratio(Palette.ink, Palette.ink), 1e-9)
        // Symmetric, always.
        assertEquals(Contrast.ratio(Palette.ink, Palette.chalk), Contrast.ratio(Palette.chalk, Palette.ink), 1e-12)
        // The brand green carries chalk comfortably; that is the number the app already ships.
        assertEquals(11.24, Contrast.ratio(Palette.brandGreen, Palette.chalk), 0.01)

        assertEquals("#0F3D2E", Colour.of("0f3d2e").hex, "case and the hash are both optional")
        assertFailsWith<IllegalArgumentException> { Colour.of("#fc0") }
        assertFailsWith<IllegalArgumentException> { Colour.of("#0F3D2G") }
        assertFailsWith<IllegalArgumentException> { Colour.of("") }
        assertEquals(Colour.of("#0F3D2E"), Colour.rgb(0x0F, 0x3D, 0x2E))
    }

    /**
     * A club may pick its colour, and it cannot pick an unreadable app.
     *
     * The stronger form of that turned out to be true and worth proving rather than assuming: because
     * the brand's two neutrals sit near the ends of the luminance range, the WORST any colour can do
     * against the better of them is about 4.17:1 — above the 3:1 floor. So no accent is ever refused,
     * and the guarantee is not "we will stop you" but "there is nothing you can pick that breaks it".
     *
     * What does vary is whether an accent carries BODY text (4.5:1) or only large text, and that is
     * reported rather than hidden, because the app has to use the right type role on it.
     */
    @Test
    fun `no colour a club can pick falls below the floor, and the headroom is measured`() {
        // Text on an accent is chosen, never configured: dark accents take chalk, light take ink.
        assertEquals(Palette.chalk, BrandCheck.verdict(Colour.of("#0F3D2E")).foreground)
        assertEquals(Palette.ink, BrandCheck.verdict(Colour.of("#FFE000")).foreground)

        // Greys span the whole luminance range, and the best-ratio depends only on luminance, so a
        // sweep of greys finds the worst case. A coarse sweep of the colour cube confirms it.
        val worstGrey = (0..255).map { Colour.rgb(it, it, it) }.minBy { BrandCheck.verdict(it).ratio }
        val worst = BrandCheck.verdict(worstGrey).ratio
        assertEquals("#777777", worstGrey.hex)
        assertEquals(4.20, worst, 0.01)
        var cubeWorst = Double.MAX_VALUE
        for (r in 0..255 step 17) for (g in 0..255 step 17) for (b in 0..255 step 17) {
            cubeWorst = minOf(cubeWorst, BrandCheck.verdict(Colour.rgb(r, g, b)).ratio)
        }
        assertEquals(4.17, cubeWorst, 0.01, "greys really are the worst case")
        assertTrue(cubeWorst > Contrast.LARGE_TEXT_MINIMUM,
                   "so no accent is ever refused: the floor has ${"%.2f".format(cubeWorst - 3.0)} of headroom")
        // Which is why the refusal cannot fire today. If the neutrals ever move towards each other
        // this assertion is what fails first, before a club sees an unreadable page.
        assertEquals(17.39, Contrast.ratio(Palette.ink, Palette.chalk), 0.01,
                     "the neutrals are 17.4:1 apart, and that spread is what buys the headroom")

        // The real distinction, and the one the app has to act on: body text or large text only.
        val bodyText = (0..255).map { Colour.rgb(it, it, it) }.filter { BrandCheck.verdict(it).carriesText }
        val largeOnly = (0..255).map { Colour.rgb(it, it, it) }.filterNot { BrandCheck.verdict(it).carriesText }
        assertTrue(bodyText.isNotEmpty() && largeOnly.isNotEmpty(), "both cases exist")
        assertTrue(BrandCheck.verdict(largeOnly.first()).explain().contains("large text only"))
        assertTrue(BrandCheck.verdict(bodyText.first()).explain().contains("passes 4.5:1"))

        // The brand's own green is the default, and it is a background colour, not a text colour:
        // 11.24:1 on the light surface, 1.55:1 on the dark one. The verdict says so rather than
        // leaving the app to find out on a dark screen.
        val default = Branding.default
        assertEquals(Palette.brandGreen, default.accent)
        assertTrue(default.verdict.carriesText)
        assertNull(default.logo)
        assertFalse(default.verdict.usableAsText)
        assertEquals(1.55, default.verdict.asTextRatio, 0.01)
        assertTrue(default.verdict.explain().contains("may not be used for text"), default.verdict.explain())
    }

    @Test
    fun `an organisation needs a name it can be called by`() {
        val org = Organisation(OrganisationId("o"), OrganisationKind.CLUB, "The Feathers")
        assertEquals(Branding.default, org.branding)
        assertFailsWith<IllegalArgumentException> {
            Organisation(OrganisationId("o"), OrganisationKind.LEAGUE, "   ")
        }
        assertFailsWith<IllegalArgumentException> {
            Organisation(OrganisationId("o"), OrganisationKind.LEAGUE, "x".repeat(121))
        }
        assertFailsWith<IllegalArgumentException> { OrganisationId("") }
        assertFailsWith<IllegalArgumentException> { PersonId(" ") }
        assertFailsWith<IllegalArgumentException> { AssetRef("") }
    }

    // ---------------------------------------------------------------- communications

    /**
     * The safeguarding boundary, enforced rather than documented.
     *
     * An app shipped with no answer to OD-010 cannot message a child. That is what this asserts, and
     * it asserts it for UNKNOWN as well as MINOR, because the thing not known is whether this is a
     * child and the safe reading of "I do not know" is the restrictive one.
     */
    @Test
    fun `a minor and an unknown age receive nothing until somebody has answered`() {
        val org = OrganisationId("o")
        val note = Announcement(org, PersonId("sec"), "Tuesday is off", "The boiler has gone.")
        val members = listOf(
            member(OrgRole.MEMBER, AgeBand.ADULT, "adult"),
            member(OrgRole.MEMBER, AgeBand.MINOR, "junior"),
            member(OrgRole.MEMBER, AgeBand.UNKNOWN, "unstated"),
            member(OrgRole.MEMBER, AgeBand.ADULT, "elsewhere", org = "other"),
        )

        val shipped = Announcements.deliver(note, members, CommunicationPolicy.undecided)
        assertEquals(listOf(PersonId("adult")), shipped.to)
        assertEquals(Withheld.MINOR_AND_NO_POLICY, shipped.withheld[PersonId("junior")])
        assertEquals(Withheld.UNKNOWN_AGE_AND_NO_POLICY, shipped.withheld[PersonId("unstated")])
        assertEquals(Withheld.NOT_A_MEMBER, shipped.withheld[PersonId("elsewhere")])
        assertEquals(1, shipped.reached)
        assertEquals(3, shipped.notReached)
        // Total: everybody is in exactly one list, so nobody can be lost between them.
        assertEquals(members.size, shipped.reached + shipped.notReached)
        assertTrue(shipped.to.none { it in shipped.withheld.keys })

        // Once the question is answered the other way, minors receive; unknowns still do not,
        // because "unknown" is not "minor" — it is "not established", and it is still not adult.
        val decided = CommunicationPolicy(minorsMayReceive = true)
        val after = Announcements.deliver(note, members, decided)
        assertEquals(listOf(PersonId("adult"), PersonId("junior")), after.to)
        assertEquals(Withheld.UNKNOWN_AGE_AND_NO_POLICY, after.withheld[PersonId("unstated")])

        // And a policy that says no is not the same as no policy, but it withholds the same people.
        val refused = Announcements.deliver(note, members, CommunicationPolicy(minorsMayReceive = false))
        assertEquals(listOf(PersonId("adult")), refused.to)

        // Only an official or an admin may send at all.
        assertFalse(Announcements.mayAnnounce(null))
        assertFalse(Announcements.mayAnnounce(member(OrgRole.MEMBER)))
        assertTrue(Announcements.mayAnnounce(member(OrgRole.OFFICIAL)))
        assertTrue(Announcements.mayAnnounce(member(OrgRole.ADMIN)))

        assertFailsWith<IllegalArgumentException> { Announcement(org, PersonId("s"), "", "body") }
        assertFailsWith<IllegalArgumentException> { Announcement(org, PersonId("s"), "subject", "") }
        assertFailsWith<IllegalArgumentException> {
            Announcement(org, PersonId("s"), "subject", "x".repeat(4001))
        }
    }

    // ---------------------------------------------------------------- fixtures

    @Test
    fun `a fixture is scheduled, may be moved once, and never asserts a result`() {
        val f = Fixture(
            id = FixtureId("f1"), organisation = OrganisationId("o"),
            startsAt = "2026-09-15T19:30:00Z",
            home = Side(PersonId("a"), "Ann"), away = Side(null, "The Feathers B"),
            venue = "The Feathers",
        )
        assertEquals(FixtureState.SCHEDULED, f.state)
        assertEquals(FixtureState.POSTPONED, f.moveTo(FixtureState.POSTPONED).state)
        assertEquals(FixtureState.PLAYED, f.moveTo(FixtureState.POSTPONED).moveTo(FixtureState.PLAYED).state)
        // Terminal states are terminal: a played or cancelled fixture does not move again.
        assertFailsWith<IllegalArgumentException> { f.moveTo(FixtureState.PLAYED).moveTo(FixtureState.SCHEDULED) }
        assertFailsWith<IllegalArgumentException> { f.moveTo(FixtureState.CANCELLED).moveTo(FixtureState.PLAYED) }

        assertFailsWith<IllegalArgumentException> { f.copy(venue = " ") }
        assertFailsWith<IllegalArgumentException> { f.copy(startsAt = "next Tuesday") }
        assertFailsWith<IllegalArgumentException> { f.copy(startsAt = "2026-09-15") }
        assertEquals("2026-09-15T19:30+01:00", f.copy(startsAt = "2026-09-15T19:30+01:00").startsAt)
        assertFailsWith<IllegalArgumentException> { Side(null, "") }

        assertFalse(Fixtures.mayManage(member(OrgRole.MEMBER)))
        assertTrue(Fixtures.mayManage(member(OrgRole.OFFICIAL)))
    }

    // ---------------------------------------------------------------- images (PD-014, OD-019)

    /**
     * The safeguarding rule in its second place. The first is the announcement that is never sent;
     * this is the picture that never exists. Unknown is treated exactly as minor, for the reason it
     * always is: what is not known is whether this is a child.
     */
    @Test
    fun `a member under 18, or of unknown age, has no picture at all`() {
        assertTrue(ImagePolicy.mayHavePicture(AgeBand.ADULT))
        assertFalse(ImagePolicy.mayHavePicture(AgeBand.MINOR))
        assertFalse(ImagePolicy.mayHavePicture(AgeBand.UNKNOWN), "unknown is treated as under 18")

        val clean = ImagePolicy.Intake(reEncoded = true, metadataStripped = true,
                                       screened = true, uploaderWarrantedTheRight = true)
        assertTrue(ImagePolicy.mayPublish(clean, AgeBand.ADULT))
        for (band in listOf(AgeBand.MINOR, AgeBand.UNKNOWN)) {
            assertFalse(ImagePolicy.mayPublish(clean, band),
                        "a perfectly clean image is still refused for $band")
            assertEquals(1, ImagePolicy.refusals(clean, band).size)
        }
    }

    /**
     * Every gate is load-bearing, and the refusals name which one failed rather than saying no.
     * Re-encoding and stripping metadata are engineering's, not the founder's: a phone photograph
     * carries the place it was taken.
     */
    @Test
    fun `an image is refused for each thing it has not passed, by name`() {
        val nothing = ImagePolicy.Intake(reEncoded = false, metadataStripped = false,
                                         screened = false, uploaderWarrantedTheRight = false)
        val refusals = ImagePolicy.refusals(nothing, AgeBand.ADULT)
        assertEquals(4, refusals.size, refusals.toString())
        assertTrue(refusals.any { it.contains("re-encoded") })
        assertTrue(refusals.any { it.contains("metadata") })
        assertTrue(refusals.any { it.contains("screened") })
        assertTrue(refusals.any { it.contains("warranted") })

        // And each one alone is enough.
        val clean = ImagePolicy.Intake(true, true, true, true)
        assertFalse(ImagePolicy.mayPublish(clean.copy(screened = false), AgeBand.ADULT))
        assertFalse(ImagePolicy.mayPublish(clean.copy(reEncoded = false), AgeBand.ADULT))
        assertFalse(ImagePolicy.mayPublish(clean.copy(metadataStripped = false), AgeBand.ADULT))
        assertFalse(ImagePolicy.mayPublish(clean.copy(uploaderWarrantedTheRight = false), AgeBand.ADULT))
    }

    /**
     * Deletion and takedown both stop the image being served at once. The thirty days are the bytes,
     * not the serving, and the difference is the whole reason the number is written down.
     */
    @Test
    fun `deleting stops it being served now, and the bytes go within thirty days`() {
        assertFalse(ImagePolicy.servedAfterDeletion())
        assertFalse(ImagePolicy.servedAfterTakedown())
        assertEquals(30, ImagePolicy.PURGE_WITHIN_DAYS)

        val takedown = ImagePolicy.Takedown("asset-1", "not their badge", "the other club")
        assertEquals("asset-1", takedown.assetId)
        assertFailsWith<IllegalArgumentException> { ImagePolicy.Takedown(" ", "why", "who") }
        assertFailsWith<IllegalArgumentException> { ImagePolicy.Takedown("asset-1", " ", "who") }
    }
}
