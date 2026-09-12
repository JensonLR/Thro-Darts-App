package thro.org

/**
 * What happens to an image somebody supplies — a club's badge, a person's picture (PD-014, OD-019).
 *
 * The founder answered the four questions this waited on. They are recorded here as **rules with
 * tests**, not as prose in a document, because every one of them is the kind of thing that gets
 * quietly forgotten between a decision and a deployment.
 *
 * One caveat is stated once and applies throughout: which of these shapes is actually available to
 * THRØ is a legal question this repository does not answer. What is here is the founder's product
 * intent, expressed as behaviour. Nothing in it is a legal conclusion.
 */
public object ImagePolicy {

    /** How an image is checked before anyone sees it. */
    public enum class Screening {
        /** An automated classifier on the way in; anything it flags waits for a person. */
        AUTOMATED_THEN_HUMAN_ON_FLAG,
    }

    public val screening: Screening = Screening.AUTOMATED_THEN_HUMAN_ON_FLAG

    /**
     * How long the bytes may survive a deletion.
     *
     * The image stops being served the moment it is deleted; the bytes are purged on a schedule that
     * covers backups and an accidental-deletion window. The gap is real and is meant to be stated in
     * a privacy notice rather than discovered.
     */
    public const val PURGE_WITHIN_DAYS: Int = 30

    /** Whether the app still serves an image it has been told to delete. */
    public fun servedAfterDeletion(): Boolean = false

    /**
     * Whether somebody of this age band may have a picture at all.
     *
     * **No.** A member recorded as a minor wears the initials mark, and so does one whose age has not
     * been established — treated the same way for the same reason the announcements are: what is not
     * known is whether this is a child. The control is not shown to them rather than shown and
     * refused, because the point is that there is no image of a child in the system to leak,
     * mis-serve, cache, or have to delete.
     *
     * This is the safeguarding rule in its second place. The first is [Announcements.deliver].
     */
    public fun mayHavePicture(ageBand: AgeBand): Boolean = ageBand == AgeBand.ADULT

    /**
     * Everything an image must have passed before it is shown to anybody but its owner.
     *
     * `reEncoded` is not a founder decision, it is engineering's: an image is always decoded and
     * written out again, and every piece of metadata is dropped. A phone photograph carries the place
     * it was taken, and a club badge uploaded by a fifteen-year-old carries their house.
     */
    public data class Intake(
        val reEncoded: Boolean,
        val metadataStripped: Boolean,
        val screened: Boolean,
        val uploaderWarrantedTheRight: Boolean,
    )

    /** Why an image may not be published. Empty means it may. */
    public fun refusals(intake: Intake, ageBand: AgeBand): List<String> {
        val out = mutableListOf<String>()
        if (!mayHavePicture(ageBand)) {
            out += if (ageBand == AgeBand.MINOR) "the person is recorded as under 18"
                   else "the person's age has not been established, and is treated as under 18"
        }
        if (!intake.reEncoded) out += "the image was not re-encoded"
        if (!intake.metadataStripped) out += "the image still carries its metadata"
        if (!intake.screened) out += "the image has not been screened"
        if (!intake.uploaderWarrantedTheRight) out += "nobody has warranted the right to use it"
        return out
    }

    public fun mayPublish(intake: Intake, ageBand: AgeBand): Boolean = refusals(intake, ageBand).isEmpty()

    /**
     * A takedown route exists whichever way the copyright question is answered.
     *
     * The founder's intent is that the uploader warrants the right and THRØ removes on notice. Every
     * other answer to that question also needs a way to take an image down, so the mechanism is not
     * conditional on it — only the words in the terms are, and the terms are not engineering's.
     */
    public data class Takedown(val assetId: String, val reason: String, val raisedBy: String) {
        init {
            require(assetId.isNotBlank()) { "a takedown names the asset" }
            require(reason.isNotBlank()) { "a takedown says why" }
        }
    }

    /** After a takedown the image is gone from the app immediately, whatever the storage schedule. */
    public fun servedAfterTakedown(): Boolean = false
}
