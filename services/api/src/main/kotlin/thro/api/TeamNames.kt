package thro.api

/**
 * Matching a team by its name, in code (PD-158).
 *
 * **Why this is not a model question.** PD-154 ruled out eleven of fourteen Jev proposals, and most of them died
 * here: a normaliser plus an edit distance does the work, with no probability anywhere and no network round trip.
 * One judge reproduced a hand-written venue table 25 out of 25 with nothing but folding and `difflib`. Team names
 * are the same shape of problem — "The Blue Bell" against "Blue Bell", "Thornaby F.C" against "Thornaby Football
 * Club", "O' Gradys" against "O'Grady's" — and the residue a model could help with is small enough that it has to
 * be measured against this before it is worth paying for.
 *
 * **The A and B rule is why there is no similarity threshold.** Two names sharing a stem and differing only in a
 * trailing side letter are different sides. Grange A is not Grange B, and a matcher that scored them as 95% alike
 * would be confidently wrong about the one distinction a league cares most about. So the side letter is split off
 * first and compared exactly; everything fuzzy happens to what is left.
 */
public object TeamNames {

    /** Words that carry no identity and that people put in or leave out at random. */
    private val NOISE = setOf("the", "fc", "afc", "cc", "sc", "rfc", "wmc", "club", "team", "darts")

    /** Long forms people write out, folded to the short form they also write. */
    private val LONG = listOf(
        "football club" to "fc", "athletic club" to "afc", "cricket club" to "cc",
        "social club" to "sc", "rugby football club" to "rfc",
        "working mens club" to "wmc", "working men s club" to "wmc",
    )

    /** A side letter, or a colour or number doing a side letter's job, at the end of a name. */
    private val SIDE = Regex("""\s+([a-z]|i{1,3}|[1-9]|reds?|blues?|greens?|whites?)$""")

    /**
     * A name folded to what it has in common with the ways people write it: lower case, no punctuation, long club
     * forms shortened, and the spacing normalised. The side letter is *kept* — [stem] is what takes it off.
     */
    public fun fold(name: String): String {
        var s = name.lowercase()
        // An apostrophe closes up rather than becoming a space, so the four ways a pub writes O'Grady — "O'Grady's",
        // "O' Gradys", "OGradys", "o grady s" — meet at one string. A possessive goes first, then an apostrophe
        // hanging off a lone letter takes any space with it, then any that are left.
        s = s.replace(Regex("""[’']s\b"""), "s")
        s = s.replace(Regex("""\b([a-z])[’']\s*"""), "$1")
        s = s.replace(Regex("""[’']"""), "")
        // A dot straight after a LONE letter is an abbreviation's, so "F.C" closes up to "fc" rather than
        // splitting into two one-letter words — "st." keeps its dot here and becomes "st", because the letter
        // before it is not on its own.
        s = s.replace(Regex("""\b([a-z])\."""), "$1")
        s = s.replace(Regex("""[^a-z0-9]+"""), " ").trim()
        for ((long, short) in LONG) if (s.contains(long)) s = s.replace(long, short)
        val words = s.split(" ").filter { it.isNotBlank() }
        val kept = words.filterIndexed { i, w -> w !in NOISE || (i == words.lastIndex && words.count { it !in NOISE } == 0) }
        return (if (kept.isEmpty()) words else kept).joinToString(" ")
    }

    /** A folded name split into the club and its side letter, where it has one. `Grange A` is `grange` and `a`. */
    public fun stem(name: String): Pair<String, String?> {
        val folded = fold(name)
        val m = SIDE.find(folded) ?: return folded to null
        return folded.removeRange(m.range).trim() to m.groupValues[1]
    }

    /**
     * Whether two names are the same side. The stems must match; the side letters must match **exactly**, and a
     * name with a side letter is never the same side as one without — "Grange" on its own is the club, and which
     * of its two teams is meant is a thing the name does not say.
     */
    public fun same(a: String, b: String): Boolean {
        val (sa, la) = stem(a); val (sb, lb) = stem(b)
        return sa == sb && la == lb
    }

    /**
     * Whether [text] names this team, however shortened — the question the desk actually asks.
     *
     * A sentence drops the side letter constantly ("Grange lost 3-5 at Riverside" is about Grange A), so a stem
     * match alone counts. But where the sentence *does* carry a side letter for that stem, it pins which side is
     * meant, and a different letter is a different team: "station 5 riverside b 1" names Riverside B and does not
     * name Riverside A.
     *
     * A single token under four letters never matches on its own — "Sun" lives inside "Sunday", and a league with
     * a Sun Inn would otherwise read "see you Sunday" as naming it.
     */
    public fun mentions(text: String, name: String): Boolean {
        val (wanted, letter) = stem(name)
        if (wanted.isEmpty()) return false
        val hay = " " + fold(text) + " "
        val words = wanted.split(" ").filter { it.isNotBlank() }

        // The whole stem, as a run of words.
        val whole = hay.contains(" $wanted ")
        // Or its longest distinctive word, which is how a secretary shortens a two-word pub name: "the Crown and
        // the Sun" is Crown and Sun Inn. Three letters is the floor, not four — the match is space-delimited, so
        // "Sun" does not find "Sunday", and a four-letter floor lost every three-letter pub name in the league.
        val longest = words.maxByOrNull { it.length }
        val byWord = longest != null && longest.length >= 3 && hay.contains(" $longest ")
        // Or, last, the stem with its spaces taken out, against the text with its spaces taken out: a secretary
        // writing "o grady s" means O'Grady's, and no amount of word matching will meet it. Six characters, so a
        // short name cannot collide with the middle of an unrelated word.
        val squashed = wanted.replace(" ", "")
        val byRun = squashed.length >= 6 && hay.replace(" ", "").contains(squashed)
        if (!whole && !byWord && !byRun) return false

        // Where the sentence names a side letter for this stem, it must be this team's.
        val anchor = if (whole) wanted else if (byWord) longest!! else squashed
        // **Every** occurrence, not the first. "grange a 4 grange b 4" names both sides of one club, and a check
        // that read only the first said the line was about Grange A and not about Grange B — so the derby, the one
        // fixture where this matters most, was seen as naming no pair at all.
        val letters = Regex(Regex.escape(" $anchor ") + """([a-z]|i{1,3}|[1-9])\s""").findAll(hay)
            .map { it.groupValues[1] }.toList()
        // A word that merely follows the name is not a side letter: only a lone character counts, and only when
        // this team has one to disagree with, or the sentence's letter names a side at all.
        return when {
            letters.isEmpty() -> true
            letter == null -> true    // the sentence is more specific than the team list; the desk decides which
            else -> letters.contains(letter)
        }
    }
}
