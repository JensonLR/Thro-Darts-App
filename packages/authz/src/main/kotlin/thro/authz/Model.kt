package thro.authz

/**
 * The object types permissions are expressed over.
 *
 * Permissions in THRØ sit *below* the event — scorers are assigned to individual boards, not to
 * competitions — and roles are season-bounded. A global role column would force a rewrite of every
 * endpoint the first time one person is simultaneously tournament director, captain, listed player
 * and venue scorer, which the approved design shows happening on day one.
 */
public enum class ObjectType {
    ORGANISATION, LEAGUE, SEASON, DIVISION, TEAM, EVENT, DRAW, MATCH, BOARD, VENUE, PLAYER,
}

public data class ObjectRef(val type: ObjectType, val id: String) {
    override fun toString(): String = "${type.name.lowercase()}:$id"
}

/** A subject is anything that can hold a relation. In practice an account, sometimes a team. */
public data class Subject(val id: String) {
    override fun toString(): String = id
}

/**
 * One relationship: this subject stands in this relation to this object.
 *
 * Tuples are the whole authorization state. There is no role column anywhere, because the moment
 * one exists someone writes `role = 'admin'` and the conflict-of-interest rule below becomes
 * unexpressible.
 */
public data class Tuple(
    val subject: Subject,
    val relation: String,
    val obj: ObjectRef,
)

/** How objects hang off one another, so a rule can reach an object's event or team. */
public data class Hierarchy(val parents: Map<ObjectRef, Set<ObjectRef>> = emptyMap()) {
    public fun parentsOf(o: ObjectRef): Set<ObjectRef> = parents[o].orEmpty()

    /** Every ancestor, not just immediate parents. Cycles are tolerated and terminate. */
    public fun ancestorsOf(o: ObjectRef): Set<ObjectRef> {
        val seen = mutableSetOf<ObjectRef>()
        val queue = ArrayDeque(parentsOf(o))
        while (queue.isNotEmpty()) {
            val next = queue.removeFirst()
            if (seen.add(next)) queue += parentsOf(next)
        }
        return seen
    }
}

/** Where tuples come from. Kept an interface so rule evaluation needs no database to be tested. */
public fun interface TupleSource {
    /** Every subject standing in [relation] to [obj]. */
    public fun subjectsWith(relation: String, obj: ObjectRef): Set<Subject>
}
