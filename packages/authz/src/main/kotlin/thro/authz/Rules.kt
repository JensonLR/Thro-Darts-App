package thro.authz

/**
 * How a permission is computed from relationships.
 *
 * Deliberately a small algebra rather than a general policy language. It has exactly what ADR-008's
 * constraining rule needs — direct relations, relations inherited from a parent object, union, and
 * **exclusion** — and nothing else. A larger language would be harder to reason about at the one
 * point in the system where being wrong grants someone else's authority.
 */
public sealed interface Rule {

    /** The subject holds [relation] directly on the object being checked. */
    public data class Direct(val relation: String) : Rule

    /**
     * The subject holds [relation] on one of the object's ancestors.
     *
     * This is how `event#official` reaches a match: officials are appointed to the event, and the
     * match hangs off it.
     */
    public data class Inherited(val relation: String) : Rule

    public data class AnyOf(val rules: List<Rule>) : Rule

    /**
     * [base] minus [minus] — the negation naive role-based access control cannot express.
     *
     * Organiser conflict of interest is not hypothetical in darts: the same people organise and
     * play, so an official who is also a competitor in the match they are adjudicating is the
     * normal case, not the exception.
     */
    public data class Except(val base: Rule, val minus: Rule) : Rule
}

/** Why a decision came out the way it did. A denial with no explanation cannot be operated. */
public data class Decision(
    val allowed: Boolean,
    /** The relation that granted it, for the audit record ADR-008 requires. */
    val grantedBy: String? = null,
    /** The relation that took it away, when an exclusion fired. */
    val excludedBy: String? = null,
) {
    public companion object {
        public val DENY: Decision = Decision(false)
    }
}

/**
 * The single decision point. Deny by default, no ambient administrator bypass.
 *
 * Permissions are resolved **per request** and never carried by the client or embedded in a token.
 * A removed organiser who kept power until their token expired would be a live authority the system
 * believes it has revoked. ADR-006's offline scoring grant is the one bounded exception, and it
 * authorises recording evidence only — never reading another player's data, never an organiser
 * action.
 */
public class Authorizer(
    private val tuples: TupleSource,
    private val hierarchy: Hierarchy,
    private val rules: Map<String, Rule>,
    /**
     * Age requirements by action. Empty by default: an action carries one only when it is
     * deliberately attached, because OD-010 is open and inventing restrictions would be as wrong
     * as omitting the dimension.
     */
    private val ageRequirements: Map<String, AgeRequirement> = emptyMap(),
) {

    /**
     * Resolves `(subject, action, object)`. An action with no rule is denied, not allowed.
     *
     * [attributes] carries the age dimension. It is a parameter of every decision rather than a
     * lookup inside some of them, which is what stops the dimension being forgotten: adding an age
     * rule to an action later requires no change at any call site.
     */
    public fun check(
        subject: Subject,
        action: String,
        obj: ObjectRef,
        attributes: SubjectAttributes = SubjectAttributes(),
    ): Decision {
        val rule = rules[action] ?: return Decision.DENY
        ageRequirements[action]?.let { requirement ->
            if (!requirement.isSatisfiedBy(attributes)) {
                return Decision(false, excludedBy = "age:${attributes.ageBand.name.lowercase()}")
            }
        }
        return evaluate(subject, rule, obj)
    }

    private fun evaluate(subject: Subject, rule: Rule, obj: ObjectRef): Decision = when (rule) {
        is Rule.Direct ->
            if (subject in tuples.subjectsWith(rule.relation, obj)) {
                Decision(true, grantedBy = "${obj}#${rule.relation}")
            } else {
                Decision.DENY
            }

        is Rule.Inherited ->
            hierarchy.ancestorsOf(obj)
                .firstOrNull { subject in tuples.subjectsWith(rule.relation, it) }
                ?.let { Decision(true, grantedBy = "${it}#${rule.relation}") }
                ?: Decision.DENY

        is Rule.AnyOf ->
            rule.rules.asSequence()
                .map { evaluate(subject, it, obj) }
                .firstOrNull { it.allowed }
                ?: Decision.DENY

        is Rule.Except -> {
            val base = evaluate(subject, rule.base, obj)
            if (!base.allowed) {
                Decision.DENY
            } else {
                val blocked = evaluate(subject, rule.minus, obj)
                if (blocked.allowed) {
                    // The exclusion won. Report both, because "you are an official but you are also
                    // playing in this match" is the only useful thing to tell the person.
                    Decision(false, grantedBy = base.grantedBy, excludedBy = blocked.grantedBy)
                } else {
                    base
                }
            }
        }
    }
}

/**
 * THRØ's rule set.
 *
 * `MATCH_CORRECT` is the one ADR-008 calls out as constraining the whole engine choice.
 */
public object Rules {

    /** An official appointed to the event, or to anything the event hangs off. */
    private val eventOfficial = Rule.Inherited("official")

    /** Anyone playing in this match, including through the team that is playing it. */
    private val matchParticipant = Rule.AnyOf(
        listOf(Rule.Direct("participant"), Rule.Inherited("member")),
    )

    public val DEFAULT: Map<String, Rule> = mapOf(
        // The conflict-of-interest rule:
        //   match#can_correct = event#official BUT NOT (match#participant ∪ participant's team)
        "match.correct" to Rule.Except(base = eventOfficial, minus = matchParticipant),

        // Scoring sits below the event: a scorer is assigned to a board, not to a competition.
        "match.score" to Rule.AnyOf(
            listOf(Rule.Direct("participant"), Rule.Inherited("scorer")),
        ),

        // Attesting is a participant's act and nobody else's, officials included: the point of a
        // participant attestation is that the person who played it says so.
        "match.attest" to Rule.Direct("participant"),

        // Adjudicating a dispute carries the same conflict-of-interest exclusion as correcting.
        "match.adjudicate" to Rule.Except(base = eventOfficial, minus = matchParticipant),

        "event.manage" to Rule.AnyOf(listOf(Rule.Direct("organiser"), Rule.Inherited("organiser"))),
    )
}
