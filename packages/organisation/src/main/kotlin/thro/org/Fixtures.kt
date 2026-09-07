package thro.org

/**
 * The smallest honest model of "arrange things": a fixture an official puts on the calendar.
 *
 * Deliberately thin. Who confirms a fixture, whether a player may propose one, what happens when
 * somebody cannot make it, and whether a postponement needs both captains are all product rules
 * about how a particular league runs itself, and they differ between leagues. Inventing them would
 * put one league's constitution into everybody's app. They are OD-018.
 *
 * What is here is what every league has: a date, two sides, somewhere to play, and a state that says
 * whether it is still going ahead.
 */

@JvmInline
public value class FixtureId(public val value: String) {
    init { require(value.isNotBlank()) { "a fixture id cannot be blank" } }
}

/**
 * Where a fixture has got to. `PLAYED` is terminal and carries no result: a result belongs to the
 * match aggregate and its provenance, and a fixture that could assert one would be a second,
 * unverified place a score could come from.
 */
public enum class FixtureState { SCHEDULED, POSTPONED, CANCELLED, PLAYED }

/** One side of a fixture: a person, or a name for a team this package does not model. */
public data class Side(val person: PersonId?, val label: String) {
    init { require(label.isNotBlank()) { "a side needs something to call it" } }
}

public data class Fixture(
    val id: FixtureId,
    val organisation: OrganisationId,
    /** ISO-8601, in the venue's own offset. Stored as text because a fixture is a local occasion. */
    val startsAt: String,
    val home: Side,
    val away: Side,
    val venue: String,
    val state: FixtureState = FixtureState.SCHEDULED,
) {
    init {
        require(venue.isNotBlank()) { "a fixture needs a venue" }
        require(ISO.matches(startsAt)) { "a fixture's time must be ISO-8601, got \"$startsAt\"" }
    }

    /** A fixture that has been played or cancelled does not move again. */
    public fun moveTo(state: FixtureState): Fixture {
        require(this.state == FixtureState.SCHEDULED || this.state == FixtureState.POSTPONED) {
            "a fixture that is ${this.state} cannot be changed"
        }
        return copy(state = state)
    }

    private companion object {
        val ISO = Regex("""^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?([+-]\d{2}:\d{2}|Z)?$""")
    }
}

public object Fixtures {
    public fun mayManage(membership: Membership?): Boolean =
        Permissions.may(membership, OrgAction.MANAGE_FIXTURES)
}
